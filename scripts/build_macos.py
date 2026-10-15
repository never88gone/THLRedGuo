#!/usr/bin/env python3
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

root = Path(__file__).resolve().parents[1]
sync_project_version(root, "1.0.0")


def run(cmd, **kwargs):
    print("Executing: " + (" ".join(cmd) if isinstance(cmd, list) else cmd), flush=True)
    subprocess.run(cmd, cwd=kwargs.pop("cwd", root), check=True, **kwargs)


def main():
    if platform.system() != "Darwin":
        raise SystemExit("macOS 构建仅支持 macOS 系统。")

    parser = argparse.ArgumentParser(description="糖葫芦果鉴 macOS 自动化构建与打包脚本")
    parser.add_argument("--clean", action="store_true", help="构建前清理产物")
    parser.add_argument("--export-options", type=Path, help="使用指定的 ExportOptions.plist 导出签名 PKG")
    add_variant_argument(parser)
    options = parser.parse_args()
    variant = BuildVariant(options.all_sources)

    flutter = shutil.which("flutter")
    xcodebuild = shutil.which("xcodebuild")
    if not flutter or not xcodebuild:
        raise SystemExit("请先确保 Flutter 与 Xcode 命令行工具已正确安装并加入 PATH。")

    run([flutter, "pub", "get"])
    # 关键：先执行 flutter build macos --config-only 生成 ephemeral 依赖与 xcfilelist，避免 clean CI 环境下 xcodebuild 报错
    run([flutter, "build", "macos", "--config-only", "--release", *variant.flutter_arguments])
    run(["pod", "install"], cwd=root / "macos")

    # 兜底确保 ephemeral 下的关键 xcfilelist 文件存在
    ephemeral_dir = root / "macos" / "Flutter" / "ephemeral"
    ephemeral_dir.mkdir(parents=True, exist_ok=True)
    for fname in ["FlutterInputs.xcfilelist", "FlutterOutputs.xcfilelist"]:
        fpath = ephemeral_dir / fname
        if not fpath.exists():
            fpath.touch()

    version_match = re.search(r'^version:\s*(\S+)', (root / "pubspec.yaml").read_text(), re.MULTILINE)
    version = version_match.group(1) if version_match else "1.0.0"
    output_dir = root / "dist" / "macos"
    output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = []

    beijing_build = get_beijing_build_number()

    if options.export_options:
        export_plist = options.export_options.expanduser().resolve()
        if not export_plist.is_file():
            raise SystemExit(f"ExportOptions.plist 不存在: {export_plist}")

        archive_path = root / "build" / "macos" / "Runner.xcarchive"
        if archive_path.exists():
            shutil.rmtree(archive_path)
        archive_path.parent.mkdir(parents=True, exist_ok=True)

        archive_cmd = [
            xcodebuild,
            "archive",
            "-workspace", str(root / "macos" / "Runner.xcworkspace"),
            "-scheme", "Runner",
            "-configuration", "Release",
            "-destination", "generic/platform=macOS",
            "-archivePath", str(archive_path),
            "MARKETING_VERSION=1.0.0",
            f"CURRENT_PROJECT_VERSION={beijing_build}",
        ]
        if options.clean:
            archive_cmd.insert(archive_cmd.index("archive") + 1, "clean")
        print(f"开始归档 macOS 工程 -> {archive_path}...")
        run(archive_cmd)

        export_dir = root / "build" / "macos" / "export"
        if export_dir.exists():
            shutil.rmtree(export_dir)
        export_dir.mkdir(parents=True, exist_ok=True)

        export_cmd = [
            xcodebuild,
            "-exportArchive",
            "-archivePath", str(archive_path),
            "-exportPath", str(export_dir),
            "-exportOptionsPlist", str(export_plist),
            "-allowProvisioningUpdates",
        ]
        print(f"导出签名 macOS PKG: {' '.join(export_cmd)}")
        run(export_cmd)

        for pkg in export_dir.glob("*.pkg"):
            target_pkg = output_dir / f"{variant.slug}-{version}-macos.pkg"
            shutil.copy2(pkg, target_pkg)
            artifacts.append(target_pkg)
            print(f"已生成签名 macOS PKG 安装包: {target_pkg}")
    else:
        run([flutter, "build", "macos", "--release", "--no-pub", *variant.flutter_arguments])
        app_path = root / "build" / "macos" / "Build" / "Products" / "Release" / "THLRedLook.app"
        if not app_path.exists():
            candidates = list((root / "build" / "macos" / "Build" / "Products" / "Release").glob("*.app"))
            if candidates:
                app_path = candidates[0]
            else:
                raise SystemExit("未找到编译生成的 macOS .app 产物")

        zip_target = output_dir / f"{variant.slug}-{version}-macos-app.zip"
        if zip_target.exists():
            zip_target.unlink()
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app_path), str(zip_target)])
        artifacts.append(zip_target)
        print(f"已生成 macOS App Zip: {zip_target}")

    checksums = []
    for artifact in sorted(output_dir.glob(f"*-{version}-macos*")):
        digest = hashlib.sha256()
        with artifact.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        checksums.append(f"{digest.hexdigest()}  {artifact.name}")
        print(artifact)
    (output_dir / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="ascii")
    print("macOS 构建打包完成！")


if __name__ == "__main__":
    main()
