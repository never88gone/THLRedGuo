import argparse
import os
import shutil
import subprocess
import sys
import traceback
from pathlib import Path

from build_mirrors import china_mirror_environment, mirrored_pub_lockfile
from app_build import BuildVariant, add_variant_argument, sync_project_version


def run_command(cmd, **kwargs):
    is_windows = os.name == 'nt'
    cmd_str = " ".join(cmd) if is_windows else cmd
    print(f"Executing: {' '.join(cmd) if isinstance(cmd, list) else cmd}", flush=True)
    return subprocess.run(cmd_str if is_windows else cmd, shell=is_windows, **kwargs)


def main():
    root = Path(__file__).resolve().parents[1]
    sync_project_version(root, "1.0.0")
    parser = argparse.ArgumentParser()
    parser.add_argument('--cn-mirrors', action='store_true', help='使用 Flutter 中国镜像')
    add_variant_argument(parser)
    options = parser.parse_args()
    variant = BuildVariant(options.all_sources)
    environment = os.environ.copy()
    flutter = 'flutter' if os.name == 'nt' else (shutil.which('flutter') or 'flutter')
    with china_mirror_environment(environment, options.cn_mirrors, gradle=False) as env:
        with mirrored_pub_lockfile(root, env):
            run_command([flutter, 'pub', 'get'], cwd=root, env=env, check=True)
            run_command([flutter, 'build', 'windows', '--release', '--no-pub', '-v', *variant.flutter_arguments], cwd=root, env=env, check=True)
            run_command([sys.executable, str(root / 'scripts' / 'package_release.py'), '--platform', 'windows', *variant.arguments],
                        cwd=root, env=env, check=True)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)

