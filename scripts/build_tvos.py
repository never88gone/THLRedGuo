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
from app_build import sync_project_version, get_beijing_timestamp_build_number

root = Path(__file__).resolve().parents[1]
sync_project_version(root, "1.0.0")

def run(cmd, **kwargs):
    print("Executing: " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=kwargs.pop("cwd", root), check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description="糖葫芦Haw Apple tvOS 自动化构建与打包脚本")
    parser.add_argument("--clean", action="store_true", help="构建前清理构建产物")
    parser.add_argument("--release", action="store_true", help="构建 Release 配置")
    parser.add_argument("--device", action="store_true", help="构建真机版本 (默认构建真机版本)")
    parser.add_argument("--package", action="store_true", help="归档并打包输出到 dist/tvos")
    parser.add_argument("--export-options", type=Path, help="使用指定的 ExportOptions.plist 导出签名 IPA")
    args = parser.parse_args()

    if platform.system() != "Darwin":
        print("tvOS 构建仅支持 macOS 系统。", file=sys.stderr)
        sys.exit(1)

    xcodebuild = shutil.which("xcodebuild")
    if not xcodebuild:
        print("未检测到 xcodebuild，请确保已安装 Xcode 命令行工具。", file=sys.stderr)
        sys.exit(1)

    workspace_path = root / "tvos" / "THLRedLook.xcworkspace"
    project_path = root / "tvos" / "THLRedLook.xcodeproj"
    if not workspace_path.exists() and not project_path.exists():
        print("未找到 Xcode 工程或 Workspace", file=sys.stderr)
        sys.exit(1)

    configuration = "Release" if (args.release or args.package) else "Debug"
    destination = "generic/platform=tvOS"

    beijing_build = get_beijing_timestamp_build_number()
    print(f"[INFO] 动态注入北京时间编译号 (Build Number): {beijing_build}")
    os.environ["TZ"] = "Asia/Shanghai"
    os.environ["BUILD_NUMBER"] = beijing_build

    info_plist = root / "tvos" / "THLRedLook" / "App" / "Info.plist"
    if info_plist.exists():
        subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleVersion {beijing_build}", str(info_plist)], capture_output=True)
        subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Set :CFBundleShortVersionString 1.0.0", str(info_plist)], capture_output=True)

    container_arg = ["-workspace", str(workspace_path)] if workspace_path.exists() else ["-project", str(project_path)]

    if args.package or args.release:
        archive_path = root / "build" / "tvos" / "THLRedLook.xcarchive"
        if archive_path.exists():
            shutil.rmtree(archive_path)
        archive_path.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            xcodebuild,
            "archive",
            *container_arg,
            "-scheme", "THLRedLook",
            "-configuration", configuration,
            "-destination", destination,
            "-archivePath", str(archive_path),
            "MARKETING_VERSION=1.0.0",
            f"CURRENT_PROJECT_VERSION={beijing_build}",
            f"BUILD_NUMBER={beijing_build}",
        ]
        if not args.export_options:
            cmd.extend([
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGN_IDENTITY=",
            ])
        if args.clean:
            cmd.insert(cmd.index("archive") + 1, "clean")

        print(f"开始归档 tvOS 工程 [{configuration}] -> {archive_path}...")
        run(cmd)

        app_dir = archive_path / "Products" / "Applications" / "THLRedLook.app"
        if not app_dir.exists():
            raise SystemExit(f"tvOS 归档产物不存在: {app_dir}")

        run([sys.executable, str(root / "scripts/source_manifest.py"), "verify", "--bundle", str(app_dir)])
        version = "1.0.0"

        output_dir = root / "dist" / "tvos"
        output_dir.mkdir(parents=True, exist_ok=True)

        # 1. 导出未签名 zip 包
        app_zip = output_dir / f"THLRedLook-{version}-tvos-unsigned-app.zip"
        if app_zip.exists():
            app_zip.unlink()
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app_dir), str(app_zip)])
        print(f"已生成 tvOS App Zip: {app_zip}")

        # 2. 导出未签名 IPA 包 (Payload 结构)
        payload_dir = output_dir / "Payload"
        if payload_dir.exists():
            shutil.rmtree(payload_dir)
        payload_dir.mkdir(parents=True, exist_ok=True)
        shutil.copytree(app_dir, payload_dir / "THLRedLook.app", symlinks=True)

        ipa_target = output_dir / f"THLRedLook-{version}-tvos-unsigned.ipa"
        if ipa_target.exists():
            ipa_target.unlink()
        run(["ditto", "-c", "-k", "--sequesterRsrc", str(payload_dir), str(ipa_target)])
        shutil.rmtree(payload_dir)
        print(f"已生成 tvOS 未签名 IPA: {ipa_target}")

        # 3. 若提供了 ExportOptions.plist，导出官方签名 IPA
        if args.export_options:
            export_plist = args.export_options.expanduser().resolve()
            if not export_plist.is_file():
                raise SystemExit(f"ExportOptions.plist 不存在: {export_plist}")
            export_dir = root / "build" / "tvos" / "export"
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
            print(f"导出签名 tvOS IPA: {' '.join(export_cmd)}")
            run(export_cmd)
            for exported_ipa in export_dir.glob("*.ipa"):
                signed_target = output_dir / f"THLRedLook-{version}-tvos-signed.ipa"
                shutil.copy2(exported_ipa, signed_target)
                print(f"已生成 tvOS 签名发布 IPA: {signed_target}")

        # 4. 生成 SHA256SUMS.txt
        checksums = []
        for artifact in sorted(output_dir.glob(f"*-{version}-tvos*")):
            digest = hashlib.sha256()
            with artifact.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            checksums.append(f"{digest.hexdigest()}  {artifact.name}")
        (output_dir / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="ascii")
        print("tvOS 打包完成！")
    else:
        cmd = [
            xcodebuild,
            *container_arg,
            "-scheme", "THLRedLook",
            "-configuration", configuration,
            "-destination", destination,
            "MARKETING_VERSION=1.0.0",
            f"CURRENT_PROJECT_VERSION={beijing_build}",
            f"BUILD_NUMBER={beijing_build}",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        if args.clean:
            cmd.append("clean")
        cmd.append("build")
        print(f"开始构建 tvOS 工程 [{configuration}] -> {destination}...")
        run(cmd)
        print("tvOS 构建成功！")

if __name__ == "__main__":
    main()
