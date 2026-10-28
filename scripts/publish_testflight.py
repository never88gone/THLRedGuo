import argparse
import json
import socket
import time
from pathlib import Path
from urllib.parse import urlencode

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
    if attached and state in ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'READY_FOR_BETA_TESTING']:
        return 'submitted_for_review'
    raise ValueError('Build is not available or submitted for external testing: ' + str(state))


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

    def request(path, method='GET', body=None):
        return api_request(BASE + path, make_jwt(key_id, issuer, key), method=method, data=body)

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
    notes = '新增数据源版本、实际运行 JS 指纹与一致性检查；优化播放稳定性、1080P 优先和清晰度切换。保留收藏与观看进度。\nJS ' + metadata['sha256'][:12]
    localizations = request(f'/builds/{build_id}/betaBuildLocalizations')['data']
    chinese = next((row for row in localizations if row['attributes']['locale'] == 'zh-Hans'), None)
    if chinese:
        request('/betaBuildLocalizations/' + chinese['id'], 'PATCH', {'data': {'type': 'betaBuildLocalizations', 'id': chinese['id'], 'attributes': {'whatsNew': notes}}})
    else:
        request('/betaBuildLocalizations', 'POST', {'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'zh-Hans', 'whatsNew': notes}, 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
    beta = request(f'/builds/{build_id}/buildBetaDetail')['data']
    if beta['attributes']['externalBuildState'] == 'READY_FOR_BETA_SUBMISSION':
        request('/betaAppReviewSubmissions', 'POST', {'data': {'type': 'betaAppReviewSubmissions', 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
    existing = request(f'/builds/{build_id}/betaGroups')['data']
    if not any(row['id'] == group['id'] for row in existing):
        request(f'/builds/{build_id}/relationships/betaGroups', 'POST', {'data': [{'type': 'betaGroups', 'id': group['id']}]})
    for attempt in range(7):
        beta = request(f'/builds/{build_id}/buildBetaDetail')['data']
        state = beta['attributes']['externalBuildState']
        if state == 'IN_BETA_TESTING':
            break
        print('External TestFlight state:', number, state, flush=True)
        if attempt < 6:
            time.sleep(30)
    attached = any(row['id'] == group['id'] for row in request(f'/builds/{build_id}/betaGroups')['data'])
    result = {'status': public_status(state, attached), 'version': version, 'buildNumber': number,
              'buildId': build_id, 'platform': 'TV_OS', 'externalBuildState': state,
              'group': group['attributes']['name'], 'publicLink': group['attributes']['publicLink'], 'source': metadata}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
