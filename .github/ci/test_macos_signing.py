import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_macos


class MacOSSigningTests(unittest.TestCase):
    def test_get_developer_id_identity_ignores_app_store_distribution(self):
        fake_stdout = (
            '  1) AAAA "Apple Distribution: Test User (TEAM123456)"\n'
            '  2) BBBB "Apple Development: Test User (DEV123456)"\n'
        )
        with patch('build_macos.subprocess.run') as mock_run:
            mock_run.return_value.stdout = fake_stdout
            self.assertIsNone(build_macos.get_developer_id_identity())

    def test_get_developer_id_identity_matches_developer_id(self):
        fake_stdout = (
            '  1) AAAA "Apple Distribution: Test User (TEAM123456)"\n'
            '  2) CCCC "Developer ID Application: Test Corp (876385K952)"\n'
        )
        with patch('build_macos.subprocess.run') as mock_run:
            mock_run.return_value.stdout = fake_stdout
            self.assertEqual(
                build_macos.get_developer_id_identity(),
                'Developer ID Application: Test Corp (876385K952)',
            )

    def test_resolved_entitlements_strips_icloud_without_developer_id(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            app = tmp / 'THLRedLook.app'
            (app / 'Contents').mkdir(parents=True)
            out_plist = tmp / 'out.entitlements'
            build_macos._build_resolved_entitlements(
                app, out_plist, allow_icloud=False, team_id=None
            )
            data = plistlib.loads(out_plist.read_bytes())
            self.assertNotIn('com.apple.developer.ubiquity-kvstore-identifier', data)
            self.assertTrue(data.get('com.apple.security.app-sandbox'))

    def test_resolved_entitlements_expands_variables_for_developer_id(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            app = tmp / 'THLRedLook.app'
            (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(
                plistlib.dumps({'CFBundleIdentifier': 'com.never88gone.redlook'})
            )
            out_plist = tmp / 'out.entitlements'
            build_macos._build_resolved_entitlements(
                app, out_plist, allow_icloud=True, team_id='876385K952'
            )
            data = plistlib.loads(out_plist.read_bytes())
            self.assertEqual(
                data.get('com.apple.developer.ubiquity-kvstore-identifier'),
                '876385K952.com.never88gone.redlook',
            )

    def test_sign_and_prepare_removes_stale_profile_and_verifies_order(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            app = tmp / 'THLRedLook.app'
            fw_bin = app / 'Contents/Frameworks/Inner.framework/Versions/A/Libraries/libsub.dylib'
            fw_bin.parent.mkdir(parents=True)
            fw_bin.write_bytes(b'dylib')
            (app / 'Contents/MacOS').mkdir(parents=True)
            main_exe = app / 'Contents/MacOS/THLRedLook'
            main_exe.write_bytes(b'exe')
            stale_profile = app / 'Contents/embedded.provisionprofile'
            stale_profile.write_bytes(b'appstore-profile')

            calls = []

            def fake_run(cmd, **kwargs):
                calls.append(cmd)
                class R:
                    returncode = 0
                    stdout = ''
                return R()

            with patch('build_macos.get_developer_id_identity', return_value=None), \
                 patch('build_macos.subprocess.run', side_effect=fake_run):
                build_macos.sign_and_prepare_app(app)

            self.assertFalse(stale_profile.exists())
            sign_calls = [c for c in calls if c[0] == 'codesign' and '--sign' in c]
            verify_calls = [c for c in calls if c[0] == 'codesign' and '--verify' in c]
            self.assertEqual(len(verify_calls), 1)
            self.assertIn('--strict', verify_calls[0])
            # 内层 dylib 先于外层 framework、外层 framework 先于主 .app
            signed_targets = [c[-1] for c in sign_calls]
            self.assertLess(
                signed_targets.index(str(fw_bin)),
                signed_targets.index(str(app / 'Contents/Frameworks/Inner.framework')),
            )
            self.assertLess(
                signed_targets.index(str(app / 'Contents/Frameworks/Inner.framework')),
                signed_targets.index(str(app)),
            )


if __name__ == '__main__':
    unittest.main()
