import base64
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import source_manifest as manifest
from prepare_official_source import TOKENS, prepare_source


class PackagedSourceTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = self.root / 'assets/sources/hongguo.js'
        self.source.parent.mkdir(parents=True)
        self.template = (
            'const meta={id:"hongguo",version:"synthetic"};\n'
            'const builtInConfiguration={id:"' + TOKENS['id'] + '",material:"' + TOKENS['material'] + '"};\n'
            + ' ' * 1000
        ).encode()
        configuration = {'id': base64.b64encode(b'synthetic').decode(),
                         'material': base64.b64encode(bytes(range(32))).decode()}
        self.prepared = prepare_source(self.template.decode(), configuration).encode()
        self.source.write_bytes(self.prepared)
        patches = [patch.object(manifest, 'SOURCE', self.source),
                   patch.dict(os.environ, {'CI': 'true', 'GITHUB_EVENT_NAME': 'push'}, clear=True),
                   patch('sys.stdout', new_callable=io.StringIO)]
        for item in patches:
            item.start()
            self.addCleanup(item.stop)

    def archive(self, source_path, data, extra=None):
        path = self.root / 'package.zip'
        with ZipFile(path, 'w') as archive:
            archive.writestr(source_path, data)
            if extra:
                archive.writestr(extra, b'synthetic unexpected source')
        return path

    def test_prepared_bytes_match_and_report_only_metadata(self):
        result = manifest.verify_flutter_source(self.prepared)
        self.assertEqual(result, {'sourceVersion': 'synthetic', 'sha256': manifest.digest(self.prepared)})

    def test_stale_or_tampered_bundle_is_rejected(self):
        for data in [self.prepared + b' ', self.template, b'']:
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                manifest.verify_flutter_source(data)

    def test_unprepared_expected_source_fails_for_release_events(self):
        self.source.write_bytes(self.template)
        for event in ['push', 'workflow_dispatch']:
            with patch.dict(os.environ, {'GITHUB_EVENT_NAME': event}), self.assertRaises(ValueError):
                manifest.verify_flutter_source(self.template)

    def test_pull_request_allows_only_unchanged_template(self):
        self.source.write_bytes(self.template)
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'pull_request'}):
            self.assertEqual(manifest.verify_flutter_source(self.template)['sha256'], manifest.digest(self.template))
            with self.assertRaises(ValueError):
                manifest.verify_flutter_source(self.prepared)

    def test_invalid_or_missing_configuration_is_rejected(self):
        for data in [self.prepared.replace(b'const builtInConfiguration', b'const missingConfiguration'),
                     self.prepared.replace(base64.b64encode(bytes(range(32))), b'invalid')]:
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                manifest.verify_flutter_source(data, expected=data)

    def test_android_and_windows_archive_paths(self):
        for source_path in ['assets/flutter_assets/assets/sources/hongguo.js',
                            'data/flutter_assets/assets/sources/hongguo.js']:
            with self.subTest(path=source_path):
                path = self.archive(source_path, self.prepared)
                self.assertEqual(manifest.verify_flutter_archive(path, source_path)['sha256'], manifest.digest(self.prepared))

    def test_archive_rejects_additional_or_missing_source(self):
        source_path = 'assets/flutter_assets/assets/sources/hongguo.js'
        path = self.archive(source_path, self.prepared, 'assets/flutter_assets/assets/sources/unexpected.js')
        with self.assertRaises(ValueError):
            manifest.verify_flutter_archive(path, source_path)
        path = self.archive('wrong/hongguo.js', self.prepared)
        with self.assertRaises(ValueError):
            manifest.verify_flutter_archive(path, source_path)

    def test_macos_staged_app_directory(self):
        directory = self.root / 'Example.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/sources'
        directory.mkdir(parents=True)
        (directory / 'hongguo.js').write_bytes(self.prepared)
        self.assertEqual(manifest.verify_flutter_directory(directory)['sha256'], manifest.digest(self.prepared))
        (directory / 'unexpected.js').write_bytes(b'synthetic')
        with self.assertRaises(ValueError):
            manifest.verify_flutter_directory(directory)

    def test_packaging_entrypoints_validate_final_android_and_windows_archives(self):
        tools = self.root / '.github/ci'
        tools.mkdir(parents=True)
        for name in ['package_release.py', 'source_manifest.py', 'prepare_official_source.py', 'app_build.py']:
            shutil.copy2(Path(__file__).parent / name, tools / name)
        (self.root / 'pubspec.yaml').write_text('version: 1.0.0+1\n')
        bundle = self.root / 'build/windows/x64/runner/Release'
        for name in ['THLRedLook.exe', 'flutter_windows.dll', 'libffmpegkit.dll', 'libmpv-2.dll',
                     'msvcp140.dll', 'vcruntime140.dll', 'data/icudtl.dat', 'data/app.so',
                     'data/flutter_assets/assets/sources/hongguo.js']:
            path = bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.prepared if name.endswith('hongguo.js') else b'synthetic')
        apk = self.root / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
        apk.parent.mkdir(parents=True)
        with ZipFile(apk, 'w') as archive:
            for name in ['libflutter.so', 'libapp.so', 'libmpv.so', 'libffmpegkit.so']:
                archive.writestr('lib/arm64-v8a/' + name, b'synthetic')
            archive.writestr('assets/flutter_assets/assets/sources/hongguo.js', self.prepared)
        for platform in ['android', 'windows']:
            args = ['--abi', 'arm64-v8a'] if platform == 'android' else []
            command = [sys.executable, str(tools / 'package_release.py'), '--platform', platform, *args]
            result = subprocess.run(command, cwd=self.root, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertIn(b'Packaged Flutter official source verified:', result.stdout)
            self.source.write_bytes(self.template)
            result = subprocess.run(command, cwd=self.root, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.source.write_bytes(self.prepared)


if __name__ == '__main__':
    unittest.main()
