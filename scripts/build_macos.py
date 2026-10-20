#!/usr/bin/env python3
import argparse
import hashlib
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from app_build import BuildVariant, add_variant_argument, sync_project_version, get_beijing_build_number

root = Path(__file__).resolve().parents[1]
sync_project_version(root, "1.0.0")


def run(cmd, **kwargs):
    print("Executing: " + (" ".join(cmd) if isinstance(cmd, list) else cmd), flush=True)
    subprocess.run(cmd, cwd=kwargs.pop("cwd", root), check=True, **kwargs)


def create_dmg(app_path: Path, dmg_target: Path, volume_name: str = "糖葫芦Haw"):
    """使用 macOS 原生 hdiutil 命令生成标准的拖拽安装 DMG 镜像包"""
    if dmg_target.exists():
        dmg_target.unlink()

    staging_dir = dmg_target.parent / f"dmg_staging_{int(time.time())}"
    if staging_dir.exists():
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True, exist_ok=True)

    try:
        dest_app = staging_dir / app_path.name
        run(["ditto", str(app_path), str(dest_app)])

        app_link = staging_dir / "Applications"
        if not app_link.exists():
            os.symlink("/Applications", app_link)

        cmd = [
            "hdiutil", "create",
            "-volname", volume_name,
            "-srcfolder", str(staging_dir),
            "-ov",
            "-format", "UDZO",
            str(dmg_target),
        ]
        print(f"正在创建 macOS DMG 磁盘镜像安装包 -> {dmg_target}...")
        run(cmd)

        # 若环境中配置了解锁的签名证书，对 DMG 磁盘镜像进行签名
        try:
            sign_res = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True)
            id_match = re.search(r'"(Apple Distribution:[^"]+)"', sign_res.stdout) or re.search(r'"(Developer ID Application:[^"]+)"', sign_res.stdout)
            if id_match:
                identity = id_match.group(1)
                print(f"正在对 DMG 安装包进行代码签名 [{identity}]...")
                subprocess.run(["codesign", "--force", "--sign", identity, str(dmg_target)], check=True)
        except Exception as e:
            print(f"[NOTE] 跳过 DMG 签名: {e}")

        print(f"已生成 macOS DMG 安装包: {dmg_target}")
    finally:
        if staging_dir.exists():
            shutil.rmtree(staging_dir, ignore_errors=True)


def main():
    if platform.system() != "Darwin":
        raise SystemExit("macOS 构建仅支持 macOS 系统。")

    parser = argparse.ArgumentParser(description="糖葫芦Haw macOS 自动化构建与打包脚本")
    parser.add_argument("--clean", action="store_true", help="构建前清理产物")
    parser.add_argument("--export-options", type=Path, help="使用指定的 ExportOptions.plist 归档")
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
    os.environ["TZ"] = "Asia/Shanghai"
    os.environ["BUILD_NUMBER"] = beijing_build

    if options.export_options:
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
            f"BUILD_NUMBER={beijing_build}",
        ]
        if options.clean:
            archive_cmd.insert(archive_cmd.index("archive") + 1, "clean")
        print(f"开始归档 macOS 工程 -> {archive_path}...")
        run(archive_cmd)

        app_dir = archive_path / "Products" / "Applications"
        app_candidates = list(app_dir.glob("*.app"))
        if not app_candidates:
            raise SystemExit("归档产物中未找到 .app 目录。")
        target_app = app_candidates[0]

        # 仅生成原生的 DMG 磁盘镜像安装包
        dmg_target = output_dir / f"{variant.slug}-{version}-macos.dmg"
        create_dmg(target_app, dmg_target)
        artifacts.append(dmg_target)
    else:
        run([flutter, "build", "macos", "--release", "--no-pub", "--build-name=1.0.0", f"--build-number={beijing_build}", *variant.flutter_arguments])
        app_path = root / "build" / "macos" / "Build" / "Products" / "Release" / "THLRedLook.app"
        if not app_path.exists():
            candidates = list((root / "build" / "macos" / "Build" / "Products" / "Release").glob("*.app"))
            if candidates:
                app_path = candidates[0]
            else:
                raise SystemExit("未找到编译生成的 macOS .app 产物")

        # 仅生成原生的 DMG 磁盘镜像安装包
        dmg_target = output_dir / f"{variant.slug}-{version}-macos.dmg"
        create_dmg(app_path, dmg_target)
        artifacts.append(dmg_target)

    checksums = []
    for artifact in sorted(output_dir.glob(f"*-{version}-macos*")):
        digest = hashlib.sha256()
        with artifact.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        checksums.append(f"{digest.hexdigest()}  {artifact.name}")
        print(artifact)
    (output_dir / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="ascii")
    print("macOS DMG 构建打包完成！")


if __name__ == "__main__":
    main()
