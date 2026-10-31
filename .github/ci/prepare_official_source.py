import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
import re
import signal
import tempfile
import threading
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


def is_ci():
    return any(os.environ.get(name, '').lower() in {'true', '1', 'yes'}
               for name in ['CI', 'GITHUB_ACTIONS'])


def load_configuration(root=ROOT, config_path=None):
    raw = os.environ.get('HONGGUO_SIGNING_CONFIG', '')
    if config_path is not None:
        raw = Path(config_path).read_text(encoding='utf-8')
    elif not raw and not is_ci():
        path = root.parent.parent / 'publicinfo' / 'THLRedGuo-signing.json'
        if path.is_file():
            raw = path.read_text(encoding='utf-8')
    if not raw:
        raise ValueError(
            'Missing publicinfo/THLRedGuo-signing.json or HONGGUO_SIGNING_CONFIG'
        )
    return parse_configuration(raw)


@contextmanager
def exclusive_source_build(root):
    path = root / 'build' / 'official-source-build.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as lock:
        if path.stat().st_size == 0:
            lock.write(b'0')
            lock.flush()
        try:
            change_build_lock(lock, acquire=True)
        except OSError:
            raise RuntimeError(
                'Another build is using the official source; wait for it to finish'
            ) from None
        try:
            yield
        finally:
            change_build_lock(lock, acquire=False)


def change_build_lock(lock, *, acquire):
    if os.name == 'nt':
        import msvcrt
        lock.seek(0)
        operation = msvcrt.LK_NBLCK if acquire else msvcrt.LK_UNLCK
        msvcrt.locking(lock.fileno(), operation, 1)
    else:
        import fcntl
        operation = fcntl.LOCK_EX | fcntl.LOCK_NB if acquire else fcntl.LOCK_UN
        fcntl.flock(lock.fileno(), operation)


def write_source(path, data):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            dir=path.parent, prefix='.hongguo-', delete=False,
        ) as file:
            temporary = Path(file.name)
            file.write(data)
        temporary.chmod(path.stat().st_mode & 0o777)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def interrupt_build(signum, frame):
    raise SystemExit(128 + signum)


@contextmanager
def prepared_official_source(root=ROOT):
    if is_ci() and not os.environ.get('HONGGUO_SIGNING_CONFIG'):
        yield
        return
    root = Path(root)
    source = root / 'assets' / 'sources' / 'hongguo.js'
    with exclusive_source_build(root):
        original = source.read_bytes()
        template = restore_template(original.decode('utf-8')).encode('utf-8')
        configuration = load_configuration(root)
        prepared = prepare_source(template.decode('utf-8'), configuration).encode('utf-8')
        restored = original if is_ci() else template
        handlers = {}
        if threading.current_thread() is threading.main_thread():
            for name in [signal.SIGINT, signal.SIGTERM]:
                handlers[name] = signal.signal(name, interrupt_build)
        try:
            write_source(source, prepared)
            print('Official source prepared for build; configuration values are not logged', flush=True)
            yield
        finally:
            try:
                current = source.read_bytes()
                if current not in [prepared, original]:
                    restored = restore_template(current.decode('utf-8')).encode('utf-8')
                write_source(source, restored)
                print('Official source restored after build', flush=True)
            finally:
                for name, handler in handlers.items():
                    signal.signal(name, handler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--restore', action='store_true')
    options = parser.parse_args()
    try:
        if options.restore:
            options.source.write_text(
                restore_template(options.source.read_text(encoding='utf-8')),
                encoding='utf-8', newline='\n',
            )
            print('Official source template restored')
            return
        configuration = load_configuration(config_path=options.config)
        prepared = prepare_source(options.source.read_text(encoding='utf-8'), configuration)
        destination = options.output or options.source
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(prepared, encoding='utf-8', newline='\n')
        print('Playable official source prepared; SHA256:', hashlib.sha256(prepared.encode()).hexdigest())
    except (ValueError, OSError):
        raise SystemExit('Official source preparation failed; check the template and HONGGUO_SIGNING_CONFIG') from None


if __name__ == '__main__':
    main()
