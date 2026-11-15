import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.github' / 'ci'))

from app_build import BuildVariant, add_variant_argument, get_beijing_build_number
from prepare_official_source import prepared_official_source, load_configuration, prepare_source, TOKENS


def sync_harmonyos_version(root: Path, base_version: str = "1.0.0", build_num: str = None) -> str:
    if not build_num:
        build_num = get_beijing_build_number()
    app_json_path = root / 'harmonyos' / 'AppScope' / 'app.json5'
    if app_json_path.exists():
        text = app_json_path.read_text(encoding='utf-8')
        text = re.sub(r'"versionCode":\s*\d+', f'"versionCode": {build_num}', text)
        text = re.sub(r'"versionName":\s*"[^"]*"', f'"versionName": "{base_version}"', text)
        app_json_path.write_text(text, encoding='utf-8')
        print(f"[INFO] 注入 HarmonyOS app.json5 版本信息: versionName={base_version}, versionCode={build_num}", flush=True)

    constants_path = root / 'harmonyos' / 'entry' / 'src' / 'main' / 'ets' / 'common' / 'Constants.ets'
    if constants_path.exists():
        text = constants_path.read_text(encoding='utf-8')
        text = re.sub(r"APP_VERSION:\s*string\s*=\s*'[^']*'", f"APP_VERSION: string = '{base_version}'", text)
        text = re.sub(r"APP_BUILD_NUMBER:\s*string\s*=\s*'[^']*'", f"APP_BUILD_NUMBER: string = '{build_num}'", text)
        constants_path.write_text(text, encoding='utf-8')

    return build_num


def sync_official_js(root: Path):
    source_template = root / 'assets' / 'sources' / 'hongguo.js'
    target_rawfile = root / 'harmonyos' / 'entry' / 'src' / 'main' / 'resources' / 'rawfile' / 'sources' / 'hongguo.js'
    target_ets = root / 'harmonyos' / 'entry' / 'src' / 'main' / 'ets' / 'core' / 'js' / 'sources' / 'hongguo.js'

    raw_text = source_template.read_text(encoding='utf-8')
    try:
        config = load_configuration(root)
        prepared = prepare_source(raw_text, config)
        print("[INFO] 成功从本地/环境注入官方数据源真实签名", flush=True)
    except Exception as e:
        print(f"[WARN] 无法注入官方签名配置 ({e})，使用模板源码构建", flush=True)
        prepared = raw_text

    target_rawfile.parent.mkdir(parents=True, exist_ok=True)
    target_rawfile.write_text(prepared, encoding='utf-8', newline='\n')
    target_ets.parent.mkdir(parents=True, exist_ok=True)
    target_ets.write_text(prepared, encoding='utf-8', newline='\n')
    print(f"[INFO] 已同步 hongguo.js 至 rawfile 与 ets 目录", flush=True)


def find_hvigor_command(harmony_dir: Path):
    # 1. 优先检查环境变量与 PATH
    which_hvigorw = shutil.which('hvigorw')
    if which_hvigorw:
        return [which_hvigorw]

    which_hvigor = shutil.which('hvigor')
    if which_hvigor:
        return [which_hvigor]

    # 2. 检查本地 Windows DevEco Studio 路径
    if os.name == 'nt':
        deveco_node = Path(r"D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe")
        deveco_hvigorw = Path(r"D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js")
        if deveco_node.is_file() and deveco_hvigorw.is_file():
            return [str(deveco_node), str(deveco_hvigorw)]

    # 3. 检查 Linux CI / setup-ohos 路径
    if os.name != 'nt':
        sdk_home = os.environ.get('HOS_SDK_HOME') or os.environ.get('DEVECO_SDK_HOME')
        if sdk_home:
            candidate = Path(sdk_home).parent / 'bin' / 'hvigorw'
            if candidate.is_file():
                return [str(candidate)]
        home_cli = Path.home() / 'ohos-sdk' / 'command-line-tools' / 'bin' / 'hvigorw'
        if home_cli.is_file():
            return [str(home_cli)]

    # 4. 检查项目自带的 hvigorw 脚本
    local_script = harmony_dir / ('hvigorw.bat' if os.name == 'nt' else 'hvigorw')
    if local_script.is_file():
        return [str(local_script)]

    # 兜底直接使用 hvigorw 命令
    return ['hvigorw']


def main():
    root = ROOT
    harmony_dir = root / 'harmonyos'
    os.environ["TZ"] = "Asia/Shanghai"

    parser = argparse.ArgumentParser(description='Build HarmonyOS NEXT HAP')
    add_variant_argument(parser)
    options = parser.parse_args()
    variant = BuildVariant(options.all_sources)

    print("========================================", flush=True)
    print("  开始执行 HarmonyOS NEXT HAP 自动化构建", flush=True)
    print("========================================", flush=True)

    # 1. 同步版本号与北京时间构建号
    beijing_build = get_beijing_build_number()
    sync_harmonyos_version(root, "1.0.0", beijing_build)

    # 2. 准备官方 JS 站源并注入签名
    sync_official_js(root)

    # 3. 配置环境变量
    env = os.environ.copy()
    env['TZ'] = 'Asia/Shanghai'
    if os.name == 'nt':
        deveco_jbr = Path(r"D:\Program Files\Huawei\DevEco Studio\jbr")
        if deveco_jbr.is_dir():
            env['JAVA_HOME'] = str(deveco_jbr)
            env['PATH'] = str(deveco_jbr / 'bin') + os.pathsep + env.get('PATH', '')
        deveco_node = Path(r"D:\Program Files\Huawei\DevEco Studio\tools\node")
        if deveco_node.is_dir():
            env['PATH'] = str(deveco_node) + os.pathsep + env.get('PATH', '')
        deveco_sdk = Path(r"D:\Program Files\Huawei\DevEco Studio\sdk")
        if deveco_sdk.is_dir():
            env['DEVECO_SDK_HOME'] = str(deveco_sdk)
    else:
        # Linux CI 下适配 setup-ohos 的 SDK 路径
        sdk_home = env.get('HOS_SDK_HOME') or env.get('DEVECO_SDK_HOME') or env.get('OHOS_BASE_SDK_HOME')
        if not sdk_home:
            candidate_sdk = Path.home() / 'ohos-sdk' / 'command-line-tools' / 'sdk'
            if candidate_sdk.is_dir():
                sdk_home = str(candidate_sdk)
        if sdk_home:
            env['DEVECO_SDK_HOME'] = sdk_home
            env['HOS_SDK_HOME'] = sdk_home
            local_props = harmony_dir / 'local.properties'
            if not local_props.exists():
                local_props.write_text(f"hwsdk.dir={sdk_home}\nsdk.dir={sdk_home}\n", encoding='utf-8')
                print(f"[INFO] 自动写入 local.properties: hwsdk.dir={sdk_home}", flush=True)

    # 检查签名文件是否存在；若不存在则自动降级为免签名构建以保证 CI 打包顺利生成 HAP
    store_file = harmony_dir / 'thl.p12'
    profile_path = harmony_dir / 'build-profile.json5'
    if profile_path.is_file() and not store_file.is_file():
        print("[WARN] 未检测到本地签名证书 thl.p12，自动调整 build-profile.json5 为免签名模式以完成 CI 构建", flush=True)
        raw_profile = profile_path.read_text(encoding='utf-8')
        cleaned_profile = re.sub(r'"signingConfig":\s*"[^"]*",?\s*', '', raw_profile)
        profile_path.write_text(cleaned_profile, encoding='utf-8')

    # 4. 执行 hvigorw assembleHap
    hvigor_cmd = find_hvigor_command(harmony_dir)
    build_args = [
        *hvigor_cmd,
        '--mode', 'module',
        '-p', 'module=entry@default',
        '-p', 'product=default',
        'assembleHap',
        '--no-daemon'
    ]

    print(f"[EXEC] {' '.join(build_args)}", flush=True)
    subprocess.run(build_args, cwd=harmony_dir, env=env, check=True)

    # 5. 提取 HAP 产物并打包归档
    output_dir = root / 'dist' / 'harmonyos'
    output_dir.mkdir(parents=True, exist_ok=True)

    hap_search_paths = [
        harmony_dir / 'entry' / 'build' / 'default' / 'outputs' / 'default' / 'entry-default-signed.hap',
        harmony_dir / 'entry' / 'build' / 'default' / 'outputs' / 'default' / 'entry-default-unsigned.hap'
    ]

    target_hap = None
    for p in hap_search_paths:
        if p.is_file():
            target_hap = p
            break

    if not target_hap:
        all_haps = list(harmony_dir.glob('**/*.hap'))
        if all_haps:
            target_hap = all_haps[0]

    if not target_hap:
        raise SystemExit("错误：未在构建输出目录找到生成的 .hap 文件！")

    dest_hap = output_dir / f'{variant.slug}-1.0.0-{beijing_build}.hap'
    shutil.copy2(target_hap, dest_hap)
    print(f"[SUCCESS] HAP 产物已导出至: {dest_hap}", flush=True)

    dest_fixed_hap = output_dir / f'{variant.slug}-1.0.0-harmonyos-signed.hap'
    shutil.copy2(target_hap, dest_fixed_hap)
    print(f"[SUCCESS] HAP 固定命名产物已导出至: {dest_fixed_hap}", flush=True)

    dest_generic_hap = output_dir / f'{variant.slug}-1.0.0-harmonyos.hap'
    shutil.copy2(target_hap, dest_generic_hap)
    print(f"[SUCCESS] HAP 通用命名产物已导出至: {dest_generic_hap}", flush=True)

    # 计算 SHA256 校验和
    checksum_file = output_dir / 'SHA256SUMS.txt'
    lines = []
    for f in [dest_hap, dest_fixed_hap, dest_generic_hap]:
        digest = hashlib.sha256(f.read_bytes()).hexdigest()
        lines.append(f"{digest}  {f.name}\n")
        print(f"[SHA256] {digest}  {f.name}", flush=True)
    checksum_file.write_text(''.join(lines), encoding='ascii')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
