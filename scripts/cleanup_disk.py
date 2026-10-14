#!/usr/bin/env python3
import os
import shutil
import subprocess
from pathlib import Path
from datetime import datetime

def get_free_gb(path):
    try:
        stat = os.statvfs(path)
        return (stat.f_bavail * stat.f_frsize) / (1024 ** 3)
    except Exception:
        return 0.0

def clean_dir_contents(directory):
    if not directory.exists():
        return 0
    removed = 0
    for item in directory.iterdir():
        try:
            if item.is_dir() and not item.is_symlink():
                shutil.rmtree(item)
                removed += 1
            else:
                item.unlink(missing_ok=True)
                removed += 1
        except Exception:
            pass
    return removed

def main():
    target_vol = "/Volumes/MacintoshData"
    before_free = get_free_gb(target_vol)
    print(f"==================================================")
    print(f"磁盘清理开始 - 当前可用空间: {before_free:.2f} GB")
    print(f"==================================================")

    # 1. 清理 Xcode DerivedData 缓存 (安全无损，下一次构建自动重新编译)
    dd_path = Path("/Volumes/MacintoshData/Develop/Xcode/DerivedData")
    if dd_path.exists():
        print(f"1. 正在清理 Xcode DerivedData 编译缓存 ({dd_path})...")
        cnt = clean_dir_contents(dd_path)
        print(f"   -> 已清理 {cnt} 个编译临时缓存条目")

    # 2. 清理 Xcode 历史 Archives 归档 (仅保留今日最近 5 个)
    archives_root = Path(os.path.expanduser("~/Library/Developer/Xcode/Archives"))
    if archives_root.exists():
        print(f"2. 正在整理 Xcode Archives 打包归档...")
        today_str = datetime.now().strftime("%Y-%m-%d")
        for date_dir in archives_root.iterdir():
            if not date_dir.is_dir():
                continue
            if date_dir.name != today_str:
                print(f"   -> 清理历史过期日期归档: {date_dir.name}")
                shutil.rmtree(date_dir, ignore_errors=True)
            else:
                # 今天的归档按修改时间排序，保留最近 5 个
                archives = sorted(
                    [a for a in date_dir.iterdir() if a.suffix == ".xcarchive"],
                    key=lambda x: x.stat().st_mtime,
                    reverse=True
                )
                if len(archives) > 5:
                    to_remove = archives[5:]
                    print(f"   -> 今日归档共 {len(archives)} 个，正在清理旧的 {len(to_remove)} 个...")
                    for old_arc in to_remove:
                        shutil.rmtree(old_arc, ignore_errors=True)

    # 3. 清理 GitLab Runner 历史完成的临时 build 目录
    runner_builds = Path(os.path.expanduser("~/builds"))
    if runner_builds.exists():
        print(f"3. 正在清理 Runner 历史构建 build 产物...")
        # 查找所有的 build 目录 (非源码)
        for p in runner_builds.glob("**/MYIT/Product/THLRedLook/build"):
            try:
                print(f"   -> 清理已完成的 Runner build 目录: {p}")
                shutil.rmtree(p, ignore_errors=True)
            except Exception:
                pass

    after_free = get_free_gb(target_vol)
    freed = after_free - before_free
    print(f"==================================================")
    print(f"清理完成! 释放空间: {max(freed, 0.0):.2f} GB")
    print(f"当前磁盘可用空间: {after_free:.2f} GB")
    print(f"==================================================")

if __name__ == "__main__":
    main()
