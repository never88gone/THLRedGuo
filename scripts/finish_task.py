import argparse
import datetime
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path

from typing import Optional

from sync_source import source_files, synchronize


@dataclass(frozen=True)
class TaskSnapshot:
    files: int
    total_bytes: int
    archive: Optional[Path] = None


def create_source_archive(destination, names):
    timestamp = datetime.datetime.now().astimezone().strftime('%Y%m%d%H%M')
    archive = destination.parent / f'真果·鉴-{timestamp}.zip'
    suffix = 2
    while archive.exists():
        archive = destination.parent / f'真果·鉴-{timestamp}-{suffix}.zip'
        suffix += 1
    with tempfile.NamedTemporaryFile(prefix='.source-archive-', suffix='.zip',
                                     dir=destination.parent, delete=False) as stream:
        temporary = Path(stream.name)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as package:
            for name in names:
                source = destination / name
                if not source.is_file():
                    raise ValueError('压缩包缺少源码文件：' + name)
                package.write(source, (Path(destination.name) / name).as_posix())
        temporary.replace(archive)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return archive


def finish_task(source, destination, message, make_archive=False):
    if destination.is_symlink():
        raise ValueError('同步目标不能是符号链接')
    source, destination = source.resolve(), destination.resolve()
    selected = source_files(source)
    if not message.strip():
        raise ValueError('请填写本次完成的变更说明')
    if source != destination:
        synchronize(source, destination)
        if synchronize(source, destination, check=True).changed:
            raise ValueError('源码同步校验未通过')
    names = sorted(path.as_posix() for path in selected)
    if source != destination and synchronize(source, destination, check=True).changed:
        raise ValueError('源码同步后校验未通过')
    archive = create_source_archive(destination, names) if make_archive else None
    return TaskSnapshot(
        files=len(names),
        total_bytes=sum((destination / name).stat().st_size for name in names),
        archive=archive,
    )


def main():
    source = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description='同步干净源码到镜像目录，不默认生成压缩包。'
    )
    parser.add_argument('--message', required=True, help='本次实际完成的变更')
    parser.add_argument('--destination', type=Path, default=source.parent / 'guoapp')
    parser.add_argument('--archive', action='store_true', default=False, help='是否生成源码压缩包（默认不生成）')
    options = parser.parse_args()
    try:
        result = finish_task(source, options.destination.expanduser(), options.message, make_archive=options.archive)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f'已同步源码：{result.files} 个文件，{result.total_bytes / 1024:.1f} KB')
    print('源码目录：' + str(options.destination.resolve()))
    if result.archive:
        print('源码压缩包：' + str(result.archive.resolve()))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
