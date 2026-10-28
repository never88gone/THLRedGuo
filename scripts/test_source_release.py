import hashlib
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile

import source_manifest as manifest
from publish_testflight import public_status, select_build, select_public_group


class SourceReleaseTests(unittest.TestCase):
    def test_manifest_and_bundle_match_actual_source(self):
        with tempfile.TemporaryDirectory() as root:
            bundle = Path(root)
            value = manifest.write_bundle(bundle)
            data = (bundle / 'hongguo.js').read_bytes()
            self.assertEqual(value['sha256'], hashlib.sha256(data).hexdigest())
            self.assertEqual(manifest.verify_bytes(data, (bundle / manifest.MANIFEST).read_bytes(), manifest.SOURCE.read_bytes()), value)

    def test_rejects_modified_or_missing_manifest(self):
        with self.assertRaises(ValueError):
            manifest.verify_bytes(b'changed', json.dumps({'id': 'hongguo', 'sha256': 'stale'}), b'expected')
        with self.assertRaises(ValueError):
            manifest.verify_bytes(b'expected', json.dumps({'id': 'wrong', 'sha256': manifest.digest(b'expected')}), b'expected')

    def test_ipa_reads_only_single_app_source_and_metadata(self):
        with tempfile.TemporaryDirectory() as root:
            ipa = Path(root) / 'app.ipa'
            with ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/App.app/Info.plist', plistlib.dumps({'CFBundleVersion': '123'}))
                archive.writestr('Payload/App.app/hongguo.js', b'source')
                archive.writestr('Payload/App.app/hongguo-source.json', '{}')
            data, value, info = manifest.inspect_ipa(ipa)
            self.assertEqual(data, b'source')
            self.assertEqual(info['CFBundleVersion'], '123')

    def test_invalid_source_fails_packaging(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / 'empty.js'
            source.write_text('')
            with patch.object(manifest, 'SOURCE', source), self.assertRaises(ValueError):
                manifest.write_bundle(Path(root) / 'bundle')

    def test_build_selection_requires_exact_platform_number_and_version(self):
        response = {'data': [
            {'id': 'ios', 'attributes': {'version': '123'}, 'relationships': {'preReleaseVersion': {'data': {'type': 'preReleaseVersions', 'id': 'ios'}}}},
            {'id': 'tv', 'attributes': {'version': '123'}, 'relationships': {'preReleaseVersion': {'data': {'type': 'preReleaseVersions', 'id': 'tv'}}}},
        ], 'included': [
            {'id': 'ios', 'type': 'preReleaseVersions', 'attributes': {'platform': 'IOS', 'version': '1.0.0'}},
            {'id': 'tv', 'type': 'preReleaseVersions', 'attributes': {'platform': 'TV_OS', 'version': '1.0.0'}},
        ]}
        self.assertEqual(select_build(response, '123', '1.0.0')['id'], 'tv')
        self.assertIsNone(select_build(response, '124', '1.0.0'))
        self.assertIsNone(select_build(response, '123', '2.0.0'))

    def test_public_group_requires_unique_existing_public_link(self):
        public = {'id': 'public', 'attributes': {'name': '外部测试', 'isInternalGroup': False, 'publicLinkEnabled': True, 'publicLink': 'https://testflight.apple.com/join/example'}}
        internal = {'id': 'internal', 'attributes': {'isInternalGroup': True}}
        self.assertEqual(select_public_group([internal, public]), public)
        with self.assertRaises(ValueError):
            select_public_group([internal])
        with self.assertRaises(ValueError):
            select_public_group([public, dict(public)])

    def test_review_pending_is_not_reported_as_published(self):
        self.assertEqual(public_status('IN_BETA_TESTING', True), 'published')
        self.assertEqual(public_status('WAITING_FOR_REVIEW', True), 'submitted_for_review')
        with self.assertRaises(ValueError):
            public_status('READY_FOR_BETA_SUBMISSION', True)
        with self.assertRaises(ValueError):
            public_status('IN_BETA_TESTING', False)


if __name__ == '__main__':
    unittest.main()
