import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/sources/hongguo.js'
MANIFEST = 'hongguo-source.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git_value(*arguments):
    result = subprocess.run(['git', *arguments], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ''


def write_bundle(bundle):
    data = SOURCE.read_bytes()
    if len(data) < 1000 or not re.search(rb'id:\s*"hongguo"', data[:2000]):
        raise ValueError('Official source is missing or invalid')
    version = re.search(rb'version:\s*"([^"]+)"', data[:2000])
    metadata = {
        'id': 'hongguo', 'sha256': digest(data),
        'sourceVersion': version.group(1).decode() if version else '',
        'sourceCommit': git_value('log', '-1', '--format=%h', '--', 'assets/sources/hongguo.js'),
        'appCommit': os.environ.get('GITHUB_SHA') or git_value('rev-parse', 'HEAD'),
    }
    bundle.mkdir(parents=True, exist_ok=True)
    (bundle / 'hongguo.js').write_bytes(data)
    (bundle / MANIFEST).write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    verify_bytes(data, (bundle / MANIFEST).read_bytes(), data)
    print('Official source bundled:', metadata['sha256'], 'commit:', metadata['sourceCommit'])
    return metadata


def verify_bytes(data, manifest, expected):
    metadata = json.loads(manifest)
    if data != expected or metadata.get('id') != 'hongguo' or metadata.get('sha256') != digest(data):
        raise ValueError('Packaged official source does not match repository or manifest')
    return metadata


def inspect_ipa(path, require_manifest=True):
    with ZipFile(path) as archive:
        infos = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
        if len(infos) != 1:
            raise ValueError('IPA must contain exactly one app')
        prefix = infos[0].rsplit('/', 1)[0] + '/'
        data = archive.read(prefix + 'hongguo.js')
        manifest = archive.read(prefix + MANIFEST) if require_manifest else None
        info = plistlib.loads(archive.read(infos[0]))
        return data, manifest, info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['write', 'verify'])
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--ipa', type=Path)
    args = parser.parse_args()
    if args.action == 'write':
        if not args.bundle:
            parser.error('write requires --bundle')
        write_bundle(args.bundle)
        return
    if args.ipa:
        data, manifest, info = inspect_ipa(args.ipa)
        if info.get('CFBundleIdentifier') != 'com.never88gone.redlook' or info.get('CFBundleSupportedPlatforms') != ['AppleTVOS']:
            raise ValueError('IPA is not the intended tvOS app')
    elif args.bundle:
        data, manifest = (args.bundle / 'hongguo.js').read_bytes(), (args.bundle / MANIFEST).read_bytes()
    else:
        parser.error('verify requires --bundle or --ipa')
    metadata = verify_bytes(data, manifest, SOURCE.read_bytes())
    print('Official source verified:', metadata['sha256'])


if __name__ == '__main__':
    main()
