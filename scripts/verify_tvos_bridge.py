import subprocess
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / 'build/verification'
    output.mkdir(parents=True, exist_ok=True)
    source = (root / 'assets/sources/hongguo.js').read_text(encoding='utf-8')
    built_in = output / 'BuiltInHongguo.swift'
    built_in.write_text('public let BuiltInHongguoJSContent = #"""\n' + source + '\n"""#\n', encoding='utf-8')
    executable = output / 'verify-tvos-bridge'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        str(root / 'tvos/THLRedLook/Core/NativeBridge.swift'), str(built_in),
        str(root / 'scripts/verify_tvos_bridge.swift'), '-o', str(executable),
    ], check=True, cwd=root)
    subprocess.run([str(executable)], check=True, cwd=root)


if __name__ == '__main__':
    main()
