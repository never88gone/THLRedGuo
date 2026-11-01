import argparse
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.github' / 'ci'))

from prepare_official_source import TOKENS, is_ci, load_configuration, prepare_source
from source_manifest import MANIFEST, SOURCE, digest, verify_bytes


def local_debug():
    mode = os.environ.get('FLUTTER_BUILD_MODE') or os.environ.get('CONFIGURATION', '')
    return mode.lower() == 'debug' and not is_ci()


def prepare_debug_asset(data, root=ROOT):
    if not local_debug() or not any(token.encode() in data for token in TOKENS.values()):
        return data
    return prepare_source(data.decode('utf-8'), load_configuration(root)).encode('utf-8')


def prepare_bundle(bundle):
    if not local_debug():
        return
    script = bundle / 'hongguo.js'
    manifest = bundle / MANIFEST
    original = script.read_bytes()
    metadata = verify_bytes(original, manifest.read_bytes(), SOURCE.read_bytes())
    prepared = prepare_debug_asset(original)
    if prepared == original:
        return
    metadata['sha256'] = digest(prepared)
    encoded = json.dumps(metadata, ensure_ascii=False, indent=2) + '\n'
    verify_bytes(prepared, encoded, prepared)
    script.write_bytes(prepared)
    manifest.write_text(encoded, encoding='utf-8')
    print('Local debug official source prepared; SHA256:', metadata['sha256'])


def main():
    parser = argparse.ArgumentParser()
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument('--input', type=Path)
    target.add_argument('--bundle', type=Path)
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    if options.input and not options.output:
        parser.error('--input requires --output')
    try:
        if options.bundle:
            prepare_bundle(options.bundle)
        else:
            data = prepare_debug_asset(options.input.read_bytes())
            options.output.parent.mkdir(parents=True, exist_ok=True)
            options.output.write_bytes(data)
    except (OSError, ValueError):
        raise SystemExit(
            'Local debug source preparation failed; check publicinfo/THLRedGuo-signing.json '
            'or HONGGUO_SIGNING_CONFIG. No configuration values are logged.'
        ) from None


if __name__ == '__main__':
    main()
