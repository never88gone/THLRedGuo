#!/usr/bin/env python3
"""
自动为 App Store Connect / TestFlight 最新构建设置“更新说明 (What to Test / Beta Build Localizations)”。
"""
import argparse
import base64
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]

try:
    import certifi
    import jwt
except ImportError:
    import subprocess
    print("[INFO] 正在安装必要依赖 pyjwt, cryptography, certifi...", flush=True)
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "pyjwt", "cryptography", "certifi"], check=True)
    import certifi
    import jwt


def get_credentials():
    key_id = os.environ.get("APP_STORE_CONNECT_KEY_ID") or os.environ.get("KEY_ID")
    issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID") or os.environ.get("ISSUER_ID")
    private_key_raw = (
        os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY")
        or os.environ.get("PRIVATE_KEY_B64")
        or os.environ.get("API_KEY_P8")
    )

    fastlane_dir = root / "fastlane"
    if not key_id and (fastlane_dir / "APP_STORE_CONNECT_KEY_ID.txt").exists():
        key_id = (fastlane_dir / "APP_STORE_CONNECT_KEY_ID.txt").read_text().strip()

    if not issuer_id and (fastlane_dir / "APP_STORE_CONNECT_ISSUER_ID.txt").exists():
        issuer_id = (fastlane_dir / "APP_STORE_CONNECT_ISSUER_ID.txt").read_text().strip()

    if not private_key_raw:
        p8_path = fastlane_dir / "APP_STORE_CONNECT_PRIVATE_KEY.p8.txt"
        if p8_path.exists():
            private_key_raw = p8_path.read_text().strip()
        else:
            b64_path = fastlane_dir / "APP_STORE_CONNECT_PRIVATE_KEY_BASE64.txt"
            if b64_path.exists():
                private_key_raw = b64_path.read_text().strip()

    if not key_id or not issuer_id or not private_key_raw:
        print("[WARNING] 未找到完整的 App Store Connect API 凭据，跳过设置 TestFlight 更新说明。")
        return None, None, None

    # 处理私钥可能为 Base64 或原始 PEM
    private_key_str = private_key_raw.strip()
    if "BEGIN PRIVATE KEY" not in private_key_str:
        try:
            private_key_str = base64.b64decode(private_key_str).decode("utf-8")
        except Exception:
            pass

    return key_id.strip(), issuer_id.strip(), private_key_str


def make_jwt(key_id: str, issuer_id: str, private_key: str) -> str:
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def api_request(url: str, token: str, method: str = "GET", data: dict = None) -> dict:
    ctx = ssl.create_default_context(cafile=certifi.where())
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    encoded_data = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=encoded_data, headers=headers, method=method)
    with urllib.request.urlopen(req, context=ctx) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else {}


def main():
    parser = argparse.ArgumentParser(description="为 TestFlight 最新构建设置更新说明")
    parser.add_argument("--notes", type=str, help="更新说明文本")
    parser.add_argument("--notes-file", type=Path, help="包含更新说明的文件路径")
    parser.add_argument("--build-number", type=str, help="指定的目标构建号")
    parser.add_argument("--bundle-id", type=str, default="com.never88gone.redlook", help="App Bundle Identifier")
    parser.add_argument("--locale", type=str, default="zh-Hans", help="本地化语言代号")
    args = parser.parse_args()

    key_id, issuer_id, private_key = get_credentials()
    if not key_id:
        sys.exit(0)

    # 确定更新说明内容
    notes = args.notes
    if not notes and args.notes_file and args.notes_file.is_file():
        notes = args.notes_file.read_text(encoding="utf-8").strip()
    if not notes:
        default_file = root / "testflight_whatsnew.txt"
        if not default_file.is_file():
            default_file = root / "fastlane" / "testflight_notes.txt"
        if default_file.is_file():
            notes = default_file.read_text(encoding="utf-8").strip()

    if not notes:
        notes = "真果鉴版本更新：优化在线播放流畅度与稳定性，适配多端设备体验。"

    token = make_jwt(key_id, issuer_id, private_key)

    # 1. 查询 App ID
    app_url = f"https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={args.bundle_id}"
    app_data = api_request(app_url, token)
    if not app_data.get("data"):
        print(f"[ERROR] 未找到 Bundle ID 为 {args.bundle_id} 的应用。")
        sys.exit(1)
    app_id = app_data["data"][0]["id"]
    print(f"[INFO] 成功连接 App Store Connect，App ID: {app_id}")

    # 2. 查询目标构建包
    # 刚上传的构建在后台可能需几秒到十几秒才能在 API 中索引到，做适当轮询
    target_build = None
    for attempt in range(6):
        builds_url = f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5"
        builds_data = api_request(builds_url, token)
        build_list = builds_data.get("data", [])

        if args.build_number:
            for b in build_list:
                if b["attributes"].get("version") == args.build_number:
                    target_build = b
                    break
        elif build_list:
            target_build = build_list[0]

        if target_build:
            break

        print(f"[INFO] 正在等待最新构建包在 App Store Connect 中生成记录 (尝试 {attempt + 1}/6)...")
        time.sleep(5)

    if not target_build:
        print("[WARNING] 未找到对应的构建记录，无法同步 TestFlight 更新说明。")
        sys.exit(0)

    build_id = target_build["id"]
    build_version = target_build["attributes"].get("version", "未知")
    print(f"[INFO] 匹配到目标构建: ID={build_id}, 版本构建号={build_version}")

    # 3. 查询当前构建已有的 BetaBuildLocalizations
    loc_url = f"https://api.appstoreconnect.apple.com/v1/builds/{build_id}/betaBuildLocalizations"
    loc_data = api_request(loc_url, token)
    existing_loc = None
    for loc in loc_data.get("data", []):
        if loc["attributes"].get("locale") == args.locale:
            existing_loc = loc
            break

    # 4. 执行更新 (PATCH) 或创建 (POST)
    if existing_loc:
        patch_id = existing_loc["id"]
        patch_url = f"https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations/{patch_id}"
        payload = {
            "data": {
                "type": "betaBuildLocalizations",
                "id": patch_id,
                "attributes": {
                    "whatsNew": notes
                }
            }
        }
        api_request(patch_url, token, method="PATCH", data=payload)
        print(f"✅ 成功更新 TestFlight [{args.locale}] 更新说明 (构建 {build_version})！")
    else:
        post_url = "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations"
        payload = {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {
                    "locale": args.locale,
                    "whatsNew": notes
                },
                "relationships": {
                    "build": {
                        "data": {
                            "type": "builds",
                            "id": build_id
                        }
                    }
                }
            }
        }
        api_request(post_url, token, method="POST", data=payload)
        print(f"✅ 成功创建 TestFlight [{args.locale}] 更新说明 (构建 {build_version})！")

    print(f"更新说明内容:\n{notes}")


if __name__ == "__main__":
    main()
