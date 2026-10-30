import argparse
import hashlib
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

from app_build import BuildVariant, add_variant_argument, sync_project_version, get_beijing_build_number

root = Path(__file__).resolve().parents[2]
sync_project_version(root, "1.0.0")
beijing_build = get_beijing_build_number()
os.environ["TZ"] = "Asia/Shanghai"
os.environ["BUILD_NUMBER"] = beijing_build


def run(arguments, **kwargs):
    subprocess.run(arguments, cwd=kwargs.pop('cwd', root), check=True, **kwargs)


def main():
    if platform.system() != 'Darwin':
        raise SystemExit('iOS 构建需要 macOS 和完整 Xcode。')
    parser = argparse.ArgumentParser(description='构建糖葫芦Haw iOS 应用')
    parser.add_argument('--export-options', type=Path, help='使用自己的 Xcode 签名配置导出 IPA')
    add_variant_argument(parser)
    options = parser.parse_args()
    variant = BuildVariant(options.all_sources)
    flutter = shutil.which('flutter')
    if not flutter or not shutil.which('pod'):
        raise SystemExit('请安装 Flutter 和 CocoaPods。')
    run([flutter, 'pub', 'get'])
    run(['pod', 'install'], cwd=root / 'ios')
    output = root / 'dist' / 'ios'
    output.mkdir(parents=True, exist_ok=True)
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.MULTILINE).group(1)
    artifacts = []
    if options.export_options:
        config = options.export_options.expanduser().resolve()
        if not config.is_file():
            raise SystemExit('ExportOptions.plist 不存在。')
        run([flutter, 'build', 'ipa', '--release', '--no-pub', '--build-name=1.0.0', f'--build-number={beijing_build}', '--export-options-plist', str(config), *variant.flutter_arguments])
        for package in (root / 'build' / 'ios' / 'ipa').glob('*.ipa'):
            destination = output / f'{variant.slug}-{version}-ios.ipa'
            shutil.copy2(package, destination)
            artifacts.append(destination)
    else:
        run([flutter, 'build', 'ios', '--release', '--no-codesign', '--no-pub', '--build-name=1.0.0', f'--build-number={beijing_build}', *variant.flutter_arguments])
        application = root / 'build' / 'ios' / 'iphoneos' / 'Runner.app'
        destination = output / f'{variant.slug}-{version}-ios-unsigned-app.zip'
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(application), str(destination)])
        artifacts.append(destination)
        # 额外打包未签名 IPA：IPA 结构为 zip 内 Payload/Runner.app。
        # 便于用户用 AltStore / Sideloadly / TrollStore 自签后直接安装。
        payload = output / 'Payload'
        if payload.exists():
            shutil.rmtree(payload)
        payload.mkdir(parents=True)
        shutil.copytree(application, payload / application.name, symlinks=True)
        ipa = output / f'{variant.slug}-{version}-ios-unsigned.ipa'
        if ipa.exists():
            ipa.unlink()
        run(['ditto', '-c', '-k', '--sequesterRsrc', str(payload), str(ipa)])
        shutil.rmtree(payload)
        artifacts.append(ipa)
    if not artifacts:
        raise SystemExit('未生成 iOS 安装包。')
    checksums = []
    for artifact in sorted(output.glob(f'*-{version}-ios*')):
        digest = hashlib.sha256()
        with artifact.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        checksums.append(f'{digest.hexdigest()}  {artifact.name}')
        print(artifact)
    (output / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='ascii')


if __name__ == '__main__':
    main()
