import base64
from dataclasses import dataclass
import sys

if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass


@dataclass(frozen=True)
class BuildVariant:
    all_sources: bool = False

    @property
    def name(self):
        return '糖葫芦Haw'

    @property
    def slug(self):
        return 'THLRedLook'

    @property
    def arguments(self):
        return ['--all-sources'] if self.all_sources else []

    @property
    def flutter_arguments(self):
        return ['--dart-define=ALL_SOURCES=' + str(self.all_sources).lower()]

    @property
    def linker_flags(self):
        return '-s -w'

    @classmethod
    def from_dart_defines(cls, encoded):
        values = {}
        for item in encoded.split(','):
            if not item:
                continue
            key, separator, value = base64.b64decode(item, validate=True).decode('utf-8').partition('=')
            if separator:
                values[key] = value
        return cls(values.get('ALL_SOURCES') == 'true')


from datetime import datetime, timezone, timedelta
from pathlib import Path
import re


def get_beijing_build_number() -> str:
    tz_bj = timezone(timedelta(hours=8))
    now = datetime.now(tz_bj)
    # 格式：年份后2位(2位) + 今年第几天(3位补零) + 时分(4位补零)
    # 例如：2026年第287天17:35 -> 262871735 (9位纯数字整数，最大值 263662359，远低于 Android 21.47 亿上限且单调递增)
    year_part = now.strftime('%y')
    day_of_year = now.strftime('%j')
    time_part = now.strftime('%H%M')
    return f"{year_part}{day_of_year}{time_part}"


def sync_project_version(root: Path, base_version: str = "1.0.0") -> str:
    build_num = get_beijing_build_number()
    full_version = f"{base_version}+{build_num}"
    pubspec = root / "pubspec.yaml"
    if pubspec.exists():
        text = pubspec.read_text(encoding="utf-8")
        updated = re.sub(r'^version:\s*.*$', f'version: {full_version}', text, flags=re.MULTILINE)
        pubspec.write_text(updated, encoding="utf-8")
        print(f"[INFO] 动态注入基于北京时间生成的构建版本号: {full_version}", flush=True)
    return full_version


def add_variant_argument(parser):
    parser.add_argument('--all-sources', action='store_true',
                        help='构建包含全部站源的版本；默认构建仅官方规范数据源版本')
