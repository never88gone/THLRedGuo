import argparse
import base64
import hashlib
import json
import os
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/sources/hongguo.js'
TOKENS = {
    'id': '__THL_HONGGUO_SIGNING_ID_BASE64__',
    'material': '__THL_HONGGUO_SIGNING_MATERIAL_BASE64__',
}


def parse_configuration(raw):
    try:
        configuration = json.loads(raw)
        if not isinstance(configuration, dict) or set(configuration) != set(TOKENS):
            raise ValueError()
        for field, expected in [('id', 9), ('material', 32)]:
            value = configuration[field]
            if not isinstance(value, str):
                raise ValueError()
            decoded = base64.b64decode(value, validate=True)
            if len(decoded) != expected or base64.b64encode(decoded).decode() != value:
                raise ValueError()
        return configuration
    except (ValueError, TypeError):
        raise ValueError('Official source configuration is invalid') from None


def prepare_source(template, configuration):
    for field, token in TOKENS.items():
        if template.count(token) != 1:
            raise ValueError('Official source template must contain each placeholder exactly once')
        template = template.replace(token, configuration[field])
    return template


def restore_template(prepared):
    pattern = r'const builtInConfiguration=\{id:"[^"\r\n]*",material:"[^"\r\n]*"\};'
    replacement = ('const builtInConfiguration={id:"' + TOKENS['id'] +
                   '",material:"' + TOKENS['material'] + '"};')
    if len(re.findall(pattern, prepared)) != 1:
        raise ValueError('Official source configuration declaration is invalid')
    return re.sub(pattern, lambda _: replacement, prepared)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--restore', action='store_true')
    options = parser.parse_args()
    try:
        if options.restore:
            options.source.write_text(restore_template(options.source.read_text(encoding='utf-8')), encoding='utf-8', newline='\n')
            print('Official source template restored')
            return
        raw = (options.config.read_text(encoding='utf-8') if options.config else
               os.environ.get('HONGGUO_SIGNING_CONFIG', ''))
        if not raw:
            raise ValueError('HONGGUO_SIGNING_CONFIG is required to build a playable official source')
        configuration = parse_configuration(raw)
        prepared = prepare_source(options.source.read_text(encoding='utf-8'), configuration)
        destination = options.output or options.source
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(prepared, encoding='utf-8', newline='\n')
        print('Playable official source prepared; SHA256:', hashlib.sha256(prepared.encode()).hexdigest())
    except (ValueError, OSError):
        raise SystemExit('Official source preparation failed; check the template and HONGGUO_SIGNING_CONFIG') from None


if __name__ == '__main__':
    main()
