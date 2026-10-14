#!/usr/bin/env python3
import functools
import http.server
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path

SIMULATOR_UDID = "2D47BBDE-A3DA-4DC8-9390-98B345792CAB"
BUNDLE_ID = "com.never88gone.redlook"
OUTPUT_PATH = Path("/tmp/tvos_screenshots/verify_rankings_source_isolation.png")
ARTIFACT_DIR = Path("/Users/never88gone/.gemini/antigravity/brain/dbf2b53c-5671-4a31-92a9-6fe0c48be0ed")

def main():
    print("=== 开始验证 tvOS 榜单数据源严格隔离与类型纯净化 ===", flush=True)

    sources_dir = Path(__file__).resolve().parents[1] / "assets" / "sources"
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(sources_dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 8991), handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    # 终止已有进程并重新以 rankings 页面启动
    subprocess.run(["xcrun", "simctl", "terminate", SIMULATOR_UDID, BUNDLE_ID], stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    cmd_launch = ["xcrun", "simctl", "launch", SIMULATOR_UDID, BUNDLE_ID, "-testPage", "rankings"]
    subprocess.run(cmd_launch, check=True)

    # 等待界面加载渲染
    time.sleep(4.0)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()

    subprocess.run(["xcrun", "simctl", "io", SIMULATOR_UDID, "screenshot", str(OUTPUT_PATH)], check=True)
    print(f"[✓] 截图成功保存: {OUTPUT_PATH} (大小: {OUTPUT_PATH.stat().st_size} bytes)")

    if ARTIFACT_DIR.exists():
        target = ARTIFACT_DIR / "verify_rankings_source_isolation.png"
        shutil.copy2(OUTPUT_PATH, target)
        print(f"[✓] 已同步工件: {target}")

    subprocess.run(["xcrun", "simctl", "terminate", SIMULATOR_UDID, BUNDLE_ID], stderr=subprocess.DEVNULL)
    print("=== 榜单数据源隔离验证完成 ===")

if __name__ == "__main__":
    main()
