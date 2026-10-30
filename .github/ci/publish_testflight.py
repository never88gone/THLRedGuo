import argparse
import json
import socket
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError

from set_testflight_notes import api_request, get_credentials, make_jwt
from source_manifest import SOURCE, inspect_ipa, verify_bytes

BASE = 'https://api.appstoreconnect.apple.com/v1'


def select_build(response, number, version):
    included = {(row['type'], row['id']): row for row in response.get('included', [])}
    for row in response.get('data', []):
        relation = row.get('relationships', {}).get('preReleaseVersion', {}).get('data') or {}
        pre = included.get((relation.get('type'), relation.get('id')), {}).get('attributes', {})
        if row['attributes']['version'] == number and pre.get('platform') == 'TV_OS' and pre.get('version') == version:
            return row
    return None


def select_public_group(groups, name=None):
    candidates = [g for g in groups if not g['attributes'].get('isInternalGroup')
                  and g['attributes'].get('publicLinkEnabled') and g['attributes'].get('publicLink')
                  and (not name or g['attributes']['name'] == name)]
    if len(candidates) != 1:
        raise ValueError('Expected one existing enabled public beta group; specify --group-name')
    return candidates[0]


def public_status(state, attached):
    if attached and state == 'IN_BETA_TESTING':
        return 'published'
    if attached and state == 'BETA_APPROVED':
        return 'approved_pending_distribution'
    if attached and state in ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'READY_FOR_BETA_TESTING']:
        return 'submitted_for_review'
    raise ValueError('Build is not available or submitted for external testing: ' + str(state))


def request_with_retry(operation, path, method='GET', body=None, sleep=time.sleep):
    for attempt in range(4):
        try:
            return operation(path, method, body)
        except (HTTPError, URLError, TimeoutError, ConnectionError) as error:
            temporary = not isinstance(error, HTTPError) or error.code in [429, 500, 502, 503, 504]
            if method != 'GET' or not temporary or attempt == 3:
                raise
            sleep(2 ** (attempt + 1))


def group_contains_build(request, group_id, build_id):
    path = f'/betaGroups/{group_id}/relationships/builds?limit=200'
    while path:
        response = request(path)
        if any(row['id'] == build_id for row in response['data']):
            return True
        next_url = response.get('links', {}).get('next')
        if next_url and not next_url.startswith(BASE + '/'):
            raise ValueError('Unexpected App Store Connect pagination URL')
        path = next_url[len(BASE):] if next_url else None
    return False


def distribute_build(request, build_id, group, number, version, metadata, sleep=time.sleep):
    notes = '修复游客请求混用系统Cookie和缓存会话异常导致的取流失败；完善起播后断流的自动重试、地址刷新和进度恢复。优先1080P完整片源，保留收藏与历史。\nJS ' + metadata['sha256'][:12]
    localizations = request(f'/builds/{build_id}/betaBuildLocalizations')['data']
    chinese = next((row for row in localizations if row['attributes']['locale'] == 'zh-Hans'), None)
    if chinese:
        request('/betaBuildLocalizations/' + chinese['id'], 'PATCH', {'data': {'type': 'betaBuildLocalizations', 'id': chinese['id'], 'attributes': {'whatsNew': notes}}})
    else:
        request('/betaBuildLocalizations', 'POST', {'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'zh-Hans', 'whatsNew': notes}, 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
    beta = request(f'/builds/{build_id}/buildBetaDetail')['data']
    if beta['attributes']['externalBuildState'] == 'READY_FOR_BETA_SUBMISSION':
        request('/betaAppReviewSubmissions', 'POST', {'data': {'type': 'betaAppReviewSubmissions', 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
    group_path = f'/builds/{build_id}/relationships/betaGroups'
    if not group_contains_build(request, group['id'], build_id):
        request(group_path, 'POST', {'data': [{'type': 'betaGroups', 'id': group['id']}]})
    for attempt in range(7):
        beta = request(f'/builds/{build_id}/buildBetaDetail')['data']
        state = beta['attributes']['externalBuildState']
        if state == 'IN_BETA_TESTING':
            break
        print('External TestFlight state:', number, state, flush=True)
        if attempt < 6:
            sleep(30)
    attached = group_contains_build(request, group['id'], build_id)
    return {'status': public_status(state, attached), 'version': version, 'buildNumber': number,
            'buildId': build_id, 'platform': 'TV_OS', 'externalBuildState': state,
            'group': group['attributes']['name'], 'publicLink': group['attributes']['publicLink'], 'source': metadata}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--group-name')
    parser.add_argument('--wait-seconds', type=int, default=900)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    data, manifest, info = inspect_ipa(args.ipa)
    metadata = verify_bytes(data, manifest, SOURCE.read_bytes())
    if info.get('CFBundleIdentifier') != 'com.never88gone.redlook' or info.get('CFBundleSupportedPlatforms') != ['AppleTVOS']:
        raise ValueError('Refusing to distribute a different app or platform')
    number, version = str(info['CFBundleVersion']), info['CFBundleShortVersionString']
    key_id, issuer, key = get_credentials()
    if not all([key_id, issuer, key]):
        raise ValueError('App Store Connect credentials are missing')
    socket.setdefaulttimeout(40)

    def operation(path, method, body):
        return api_request(BASE + path, make_jwt(key_id, issuer, key), method=method, data=body)

    def request(path, method='GET', body=None):
        return request_with_retry(operation, path, method, body)

    app = request('/apps?' + urlencode({'filter[bundleId]': info['CFBundleIdentifier']}))['data'][0]
    app_id = app['id']
    group = select_public_group(request(f'/apps/{app_id}/betaGroups')['data'], args.group_name)
    deadline = time.monotonic() + args.wait_seconds
    build = None
    while time.monotonic() < deadline:
        response = request('/builds?' + urlencode({'filter[app]': app_id, 'filter[version]': number, 'include': 'preReleaseVersion'}))
        build = select_build(response, number, version)
        if build:
            state = build['attributes']['processingState']
            if state == 'VALID':
                break
            if state in ['FAILED', 'INVALID']:
                raise ValueError('App Store Connect rejected processing: ' + state)
        print('Waiting for exact tvOS build processing:', number, flush=True)
        time.sleep(30)
    if not build or build['attributes']['processingState'] != 'VALID':
        raise TimeoutError('Exact tvOS build did not finish processing')
    build_id = build['id']
    result = distribute_build(request, build_id, group, number, version, metadata)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
