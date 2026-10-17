import argparse
from pathlib import Path


def synchronize(root: Path, check: bool = False) -> None:
    source = (root / 'assets/sources/hongguo.js').read_text(encoding='utf-8').rstrip()
    targets = [
        ('lib/core/js/js_source_presets.dart', "    script: r'''", "''',"),
        ('tvos/THLRedLook/ViewModels/LibraryViewModel.swift',
         'public let BuiltInHongguoJSContent = #"""\n', '\n"""#'),
    ]
    for name, opening, closing in targets:
        path = root / name
        current = path.read_text(encoding='utf-8')
        start = current.index(opening) + len(opening)
        end = current.index(closing, start)
        replacement = source + ('\n' if name.endswith('.dart') else '')
        if current[start:end] == replacement:
            continue
        if check:
            raise SystemExit(f'内置红果源不同步: {name}')
        path.write_text(current[:start] + replacement + current[end:], encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    synchronize(Path(__file__).resolve().parents[1], args.check)
