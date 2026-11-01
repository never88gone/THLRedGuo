import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
from pathlib import Path
from zipfile import ZipFile

from prepare_official_source import TOKENS, is_ci, parse_configuration

ROOT = Path(__file__).resolve().parents[2]
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


def verify_flutter_source(data, expected=None):
    expected = SOURCE.read_bytes() if expected is None else expected
    if data != expected:
        raise ValueError('Packaged Flutter source does not match the prepared official source')
    configurations = re.findall(
        rb'const builtInConfiguration=\{id:"([^"\r\n]*)",material:"([^"\r\n]*)"\};',
        data,
    )
    if len(configurations) != 1:
        raise ValueError('Packaged Flutter source configuration is missing or invalid')
    values = dict(zip(TOKENS, (value.decode('ascii') for value in configurations[0])))
    if any(token.encode() in data for token in TOKENS.values()):
        if not (is_ci() and os.environ.get('GITHUB_EVENT_NAME') == 'pull_request' and values == TOKENS):
            raise ValueError('Packaged Flutter source still contains signing placeholders')
    else:
        parse_configuration(json.dumps(values))
    version = re.search(rb'version:\s*"([^"]+)"', data[:2000])
    if len(data) < 1000 or not re.search(rb'id:\s*"hongguo"', data[:2000]) or not version:
        raise ValueError('Packaged Flutter official source metadata is invalid')
    metadata = {'sourceVersion': version.group(1).decode(), 'sha256': digest(data)}
    print('Packaged Flutter official source verified:', metadata['sourceVersion'], metadata['sha256'])
    return metadata


def verify_flutter_archive(path, source_path):
    prefix = source_path.rsplit('/', 1)[0] + '/'
    with ZipFile(path) as archive:
        scripts = [name for name in archive.namelist() if name.startswith(prefix) and name.endswith('.js')]
        if scripts != [source_path]:
            raise ValueError('Flutter package must contain only the official source script')
        return verify_flutter_source(archive.read(source_path))


def verify_flutter_directory(directory):
    scripts = sorted(path.relative_to(directory).as_posix() for path in directory.rglob('*.js') if path.is_file())
    if scripts != ['hongguo.js']:
        raise ValueError('Flutter bundle must contain only the official source script')
    return verify_flutter_source((directory / 'hongguo.js').read_bytes())


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
