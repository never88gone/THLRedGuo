#!/usr/bin/env python3
import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]

def run(cmd, **kwargs):
    print("Executing: " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=kwargs.pop("cwd", root), check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description="真果·鉴 Apple tvOS 自动化构建与验证脚本")
    parser.add_argument("--clean", action="store_true", help="构建前清理构建产物")
    parser.add_argument("--release", action="store_true", help="构建 Release 配置")
    parser.add_argument("--device", action="store_true", help="构建真机版本 (默认构建模拟器版本)")
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
        print(f"未找到 Xcode 工程或 Workspace", file=sys.stderr)
        sys.exit(1)

    configuration = "Release" if args.release else "Debug"
    destination = "generic/platform=tvOS" if args.device else "generic/platform=tvOS Simulator"

    from datetime import datetime, timezone, timedelta
    tz_bj = timezone(timedelta(hours=8))
    beijing_build = datetime.now(tz_bj).strftime('%Y%m%d%H%M%S')
    print(f"🚀 动态注入北京时间编译号 (Build Number): {beijing_build}")

    info_plist = root / "tvos" / "THLRedLook" / "App" / "Info.plist"
    if info_plist.exists():
        subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleVersion {beijing_build}", str(info_plist)], capture_output=True)

    container_arg = ["-workspace", str(workspace_path)] if workspace_path.exists() else ["-project", str(project_path)]
    cmd = [
        xcodebuild,
        *container_arg,
        "-scheme", "THLRedLook",
        "-configuration", configuration,
        "-destination", destination,
        f"CURRENT_PROJECT_VERSION={beijing_build}",
    ]

    if args.device:
        cmd.append("-allowProvisioningUpdates")
    else:
        cmd.append("CODE_SIGNING_ALLOWED=NO")

    if args.clean:
        cmd.append("clean")
    cmd.append("build")

    print(f"开始构建 tvOS 工程 [{configuration}] -> {destination}...")
    run(cmd)
    print("tvOS 构建成功！")

if __name__ == "__main__":
    main()
