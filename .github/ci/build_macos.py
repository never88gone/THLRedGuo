#!/usr/bin/env python3
import argparse
import hashlib
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from app_build import BuildVariant, add_variant_argument, sync_project_version, get_beijing_build_number

from prepare_official_source import prepared_official_source
from source_manifest import verify_flutter_directory

root = Path(__file__).resolve().parents[2]


def run(cmd, **kwargs):
    print("Executing: " + (" ".join(cmd) if isinstance(cmd, list) else cmd), flush=True)
    subprocess.run(cmd, cwd=kwargs.pop("cwd", root), check=True, **kwargs)


def get_developer_id_identity():
    """仅查找可用于独立 DMG 分发的 Developer ID Application 证书，不选用 Mac App Store 证书。"""
    try:
        sign_res = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True)
        id_match = re.search(r'"(Developer ID Application:[^"]+)"', sign_res.stdout)
        return id_match.group(1) if id_match else None
    except Exception:
        return None


def find_developer_id_profile():
    """仅查找适用于 Developer ID 直接分发的描述文件，跳过 Mac App Store 专用描述文件。"""
    profiles_dir = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"
    if not profiles_dir.exists():
        return None
    for candidate in sorted(profiles_dir.glob("*.provisionprofile")):
        if "macOS_dis" in candidate.name or "appstore" in candidate.name.lower():
            continue
        try:
            res = subprocess.run(["security", "cms", "-D", "-i", str(candidate)], capture_output=True)
            if res.returncode != 0:
                continue
            plist = plistlib.loads(res.stdout)
            if plist.get("ProvisionsAllDevices") or plist.get("ProvisionedDevices"):
                continue
            certs = plist.get("DeveloperCertificates") or []
            if certs:
                return candidate
        except Exception:
            continue
    return None


def _build_resolved_entitlements(app_path: Path, output_plist: Path, allow_icloud: bool, team_id: str | None):
    entitlements_path = root / "macos" / "Runner" / "Release.entitlements"
    data = plistlib.loads(entitlements_path.read_bytes())

    if allow_icloud and team_id:
        info_plist = app_path / "Contents" / "Info.plist"
        bundle_id = "com.never88gone.redlook"
        if info_plist.exists():
            info = plistlib.loads(info_plist.read_bytes())
            bundle_id = info.get("CFBundleIdentifier") or bundle_id
        kv = data.get("com.apple.developer.ubiquity-kvstore-identifier")
        if isinstance(kv, str):
            kv = kv.replace("$(TeamIdentifierPrefix)", f"{team_id}.")
            kv = kv.replace("$(CFBundleIdentifier)", bundle_id)
            data["com.apple.developer.ubiquity-kvstore-identifier"] = kv
    else:
        data.pop("com.apple.developer.ubiquity-kvstore-identifier", None)

    output_plist.write_bytes(plistlib.dumps(data))


def _collect_nested_sign_targets(contents_dir: Path) -> list[Path]:
    targets = []
    search_roots = [
        contents_dir / "Frameworks",
        contents_dir / "PlugIns",
        contents_dir / "Helpers",
        contents_dir / "Library",
    ]
    extensions = {".dylib", ".so", ".bundle", ".xpc", ".appex", ".framework"}
    for base in search_roots:
        if not base.exists():
            continue
        for item in base.rglob("*"):
            if item.is_symlink():
                continue
            if item.suffix in extensions or (
                item.is_file()
                and item.parent.name in ("MacOS", "Helpers")
                and os.access(item, os.X_OK)
            ):
                targets.append(item)
    # 先签最深层嵌套文件，再签外层 framework/bundle，避免内外层签名不一致
    targets.sort(key=lambda p: (len(p.parts), str(p)), reverse=True)
    return targets


def sign_and_prepare_app(app_path: Path):
    """清理不兼容 DMG 分发的 App Store 配置，并按从内到外顺序完成规范签名与严格校验。"""
    contents_dir = app_path / "Contents"

    # 移除任何 AppleDouble 隐藏文件，防止 codesign 校验或执行异常
    for apple_double in app_path.rglob("._*"):
        apple_double.unlink(missing_ok=True)

    # 移除可能混入的 App Store 描述文件；仅在持有匹配 Developer ID 描述文件时再嵌入
    embedded_dest = contents_dir / "embedded.provisionprofile"
    if embedded_dest.exists():
        embedded_dest.unlink()

    macos_dir = contents_dir / "MacOS"
    if macos_dir.exists():
        for exe in macos_dir.iterdir():
            if exe.is_file() and not exe.is_symlink():
                exe.chmod(exe.stat().st_mode | 0o755)

    identity = get_developer_id_identity()
    profile = find_developer_id_profile() if identity else None
    team_id = None
    if identity:
        team_match = re.search(r'\(([A-Z0-9]+)\)\s*$', identity)
        team_id = team_match.group(1) if team_match else None

    if identity and profile and profile.exists():
        shutil.copy2(profile, embedded_dest)
        print(f"已嵌入 Developer ID 描述文件 -> {embedded_dest} (来源: {profile.name})")

    sign_target = identity if identity else "-"
    use_runtime = identity is not None
    allow_icloud = bool(identity and profile and team_id)

    if identity:
        print(f"正在使用 Developer ID 对 macOS 应用包体执行全量签名 [{identity}]...")
    else:
        print("[NOTE] 未检测到 Developer ID Application 证书（Apple Distribution 仅限 App Store）。"
              "将使用纯净 Ad-Hoc 签名并剥离受限权限与 App Store 描述文件，确保 DMG 安装包可正常启动。")

    with tempfile.TemporaryDirectory() as tmp_dir:
        resolved_entitlements = Path(tmp_dir) / "resolved.entitlements"
        _build_resolved_entitlements(app_path, resolved_entitlements, allow_icloud, team_id)

        nested_targets = _collect_nested_sign_targets(contents_dir)
        for target in nested_targets:
            cmd = ["codesign", "--force", "--sign", sign_target]
            if use_runtime:
                cmd.extend(["--options", "runtime", "--timestamp"])
            cmd.append(str(target))
            subprocess.run(cmd, check=True)

        app_cmd = [
            "codesign", "--force",
            "--sign", sign_target,
            "--entitlements", str(resolved_entitlements),
        ]
        if use_runtime:
            app_cmd.extend(["--options", "runtime", "--timestamp"])
        app_cmd.append(str(app_path))
        subprocess.run(app_cmd, check=True)

    run(["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app_path)])
    print(f"macOS 应用签名校验通过: {app_path}")


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
        verify_flutter_directory(
            dest_app / 'Contents' / 'Frameworks' / 'App.framework' / 'Resources' / 'flutter_assets' / 'assets' / 'sources'
        )

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
        run(['hdiutil', 'verify', str(dmg_target)])

        # 仅在配置了 Developer ID Application 证书时对 DMG 镜像进行代码签名
        try:
            identity = get_developer_id_identity()
            if identity:
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

    with prepared_official_source(root):
        sync_project_version(root, "1.0.0")
        build(options, variant, flutter, xcodebuild)


def build(options, variant, flutter, xcodebuild):
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

    # 未持有 Developer ID Application 与配套描述文件时，编译阶段剥离受限 iCloud Entitlement 并禁止绑定 App Store 描述文件
    entitlements_path = root / "macos" / "Runner" / "Release.entitlements"
    orig_entitlements = entitlements_path.read_text()
    stripped_entitlements = re.sub(
        r'\s*<key>com\.apple\.developer\.ubiquity-kvstore-identifier</key>\s*<string>[^<]+</string>',
        '',
        orig_entitlements
    )
    dev_id = get_developer_id_identity()
    dev_profile = find_developer_id_profile() if dev_id else None
    has_dev_signing = bool(dev_id and dev_profile)
    if not has_dev_signing and stripped_entitlements != orig_entitlements:
        entitlements_path.write_text(stripped_entitlements)

    try:
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
            if not has_dev_signing:
                archive_cmd.extend([
                    "CODE_SIGN_IDENTITY=-",
                    "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGNING_ALLOWED=NO",
                    "PROVISIONING_PROFILE_SPECIFIER=",
                ])
            if options.clean:
                archive_cmd.insert(archive_cmd.index("archive") + 1, "clean")
            print(f"开始归档 macOS 工程 -> {archive_path}...")
            run(archive_cmd)

            app_dir = archive_path / "Products" / "Applications"
            app_candidates = list(app_dir.glob("*.app"))
            if not app_candidates:
                raise SystemExit("归档产物中未找到 .app 目录。")
            target_app = app_candidates[0]

            sign_and_prepare_app(target_app)
            dmg_target = output_dir / f"{variant.slug}-{version}-macos.dmg"
            create_dmg(target_app, dmg_target)
            artifacts.append(dmg_target)
        else:
            if not has_dev_signing:
                # 兜底确保本地无 App Store 描述文件时 flutter build macos 也可由下方 xcodebuild/ad-hoc 顺利完成
                archive_path = root / "build" / "macos" / "Runner.xcarchive"
                if archive_path.exists():
                    shutil.rmtree(archive_path)
                archive_path.parent.mkdir(parents=True, exist_ok=True)
                run([
                    flutter, "build", "macos", "--config-only", "--release",
                    "--no-pub", "--build-name=1.0.0", f"--build-number={beijing_build}",
                    *variant.flutter_arguments,
                ])
                run([
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
                    "CODE_SIGN_IDENTITY=-",
                    "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGNING_ALLOWED=NO",
                    "PROVISIONING_PROFILE_SPECIFIER=",
                ])
                app_candidates = list((archive_path / "Products" / "Applications").glob("*.app"))
                if not app_candidates:
                    raise SystemExit("未找到归档生成的 macOS .app 产物")
                app_path = app_candidates[0]
            else:
                run([flutter, "build", "macos", "--release", "--no-pub", "--build-name=1.0.0", f"--build-number={beijing_build}", *variant.flutter_arguments])
                app_path = root / "build" / "macos" / "Build" / "Products" / "Release" / "THLRedLook.app"
                if not app_path.exists():
                    candidates = list((root / "build" / "macos" / "Build" / "Products" / "Release").glob("*.app"))
                    if candidates:
                        app_path = candidates[0]
                    else:
                        raise SystemExit("未找到编译生成的 macOS .app 产物")

            sign_and_prepare_app(app_path)
            dmg_target = output_dir / f"{variant.slug}-{version}-macos.dmg"
            create_dmg(app_path, dmg_target)
            artifacts.append(dmg_target)
    finally:
        if entitlements_path.read_text() != orig_entitlements:
            entitlements_path.write_text(orig_entitlements)

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
