import hashlib
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile

import source_manifest as manifest
from publish_testflight import distribute_build, public_status, request_with_retry, select_build, select_public_group
from urllib.error import HTTPError, URLError


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

    def test_distribution_reads_group_relationships_and_confirms_public_state(self):
        calls = []
        attached = []
        group = {'id': 'public', 'attributes': {'name': '外部测试', 'publicLink': 'https://testflight.apple.com/join/example'}}
        def request(path, method='GET', body=None):
            calls.append((path, method))
            if path.endswith('/betaBuildLocalizations'):
                return {'data': [{'id': 'notes', 'attributes': {'locale': 'zh-Hans'}}]}
            if path.endswith('/buildBetaDetail'):
                return {'data': {'attributes': {'externalBuildState': 'IN_BETA_TESTING' if attached else 'BETA_APPROVED'}}}
            if path == '/betaGroups/public/relationships/builds?limit=200':
                return {'data': [{'type': 'builds', 'id': 'build'}] if attached else []}
            if path.endswith('/relationships/betaGroups') and method == 'POST':
                attached.extend(body['data'])
                return {}
            if method == 'PATCH':
                return {}
            raise AssertionError('Unexpected ASC route: ' + path)
        result = distribute_build(request, 'build', group, '123', '1.0.0', {'sha256': 'abc'}, sleep=lambda _: None)
        self.assertEqual(result['status'], 'published')
        self.assertIn(('/betaGroups/public/relationships/builds?limit=200', 'GET'), calls)
        self.assertNotIn(('/builds/build/relationships/betaGroups', 'GET'), calls)
        self.assertIn(('/builds/build/relationships/betaGroups', 'POST'), calls)

    def test_get_retries_transient_apple_errors_without_repeating_writes(self):
        calls = []
        def operation(path, method, body):
            calls.append(method)
            if len(calls) < 3:
                raise HTTPError(path, 500, 'temporary', {}, None)
            return {'data': []}
        self.assertEqual(request_with_retry(operation, '/build', sleep=lambda _: None), {'data': []})
        self.assertEqual(len(calls), 3)
        calls.clear()
        with self.assertRaises(HTTPError):
            request_with_retry(operation, '/build', method='POST', sleep=lambda _: None)
        self.assertEqual(calls, ['POST'])

    def test_get_recovers_transport_timeouts_and_disconnects(self):
        for error in [TimeoutError('read timed out'), URLError('connection closed'), ConnectionResetError('reset')]:
            calls = []
            delays = []
            def operation(path, method, body):
                calls.append(method)
                if len(calls) < 3:
                    raise error
                return {'data': []}
            self.assertEqual(request_with_retry(operation, '/build', sleep=delays.append), {'data': []})
            self.assertEqual(calls, ['GET', 'GET', 'GET'])
            self.assertEqual(delays, [2, 4])

    def test_persistent_transport_timeout_stops_after_four_reads(self):
        calls = []
        def operation(path, method, body):
            calls.append(method)
            raise TimeoutError('read timed out')
        with self.assertRaises(TimeoutError):
            request_with_retry(operation, '/build', sleep=lambda _: None)
        self.assertEqual(len(calls), 4)
        for method in ['POST', 'PATCH']:
            calls.clear()
            with self.assertRaises(TimeoutError):
                request_with_retry(operation, '/build', method=method, sleep=lambda _: None)
            self.assertEqual(calls, [method])

    def test_authorization_error_is_not_retried(self):
        calls = []
        def operation(path, method, body):
            calls.append(method)
            raise HTTPError(path, 401, 'unauthorized', {}, None)
        with self.assertRaises(HTTPError):
            request_with_retry(operation, '/build', sleep=lambda _: None)
        self.assertEqual(calls, ['GET'])

    def test_review_pending_is_not_reported_as_published(self):
        self.assertEqual(public_status('IN_BETA_TESTING', True), 'published')
        self.assertEqual(public_status('WAITING_FOR_REVIEW', True), 'submitted_for_review')
        self.assertEqual(public_status('BETA_APPROVED', True), 'approved_pending_distribution')
        with self.assertRaises(ValueError):
            public_status('READY_FOR_BETA_SUBMISSION', True)
        with self.assertRaises(ValueError):
            public_status('IN_BETA_TESTING', False)


if __name__ == '__main__':
    unittest.main()
