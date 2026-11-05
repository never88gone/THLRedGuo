import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

Future<int> directoryBytes(Directory directory) async {
  if (!await directory.exists()) return 0;
  var bytes = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) bytes += await entity.length();
  }
  return bytes;
}

int availableDiskBytes(String directory) {
  if (!Platform.isWindows) return -1;
  final nativePath = directory.toNativeUtf16();
  final available = calloc<Uint64>();
  final total = calloc<Uint64>();
  final free = calloc<Uint64>();
  try {
    final query = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetDiskFreeSpaceExW');
    return query(nativePath, available, total, free) != 0
        ? available.value
        : -1;
  } finally {
    calloc.free(nativePath);
    calloc.free(available);
    calloc.free(total);
    calloc.free(free);
  }
}

class AppCacheStorage {
  AppCacheStorage(this.applicationCache);
  final Directory applicationCache;

  Future<Directory?> _coverDirectory() async {
    if (!await applicationCache.exists()) return null;
    final root = await applicationCache.resolveSymbolicLinks();
    final expected = path.join(root, 'pure_core', 'covers');
    final directory = Directory(expected);
    if (!await directory.exists()) return null;
    if (!path.equals(expected, await directory.resolveSymbolicLinks())) {
      throw const FileSystemException('缓存目录不能指向应用缓存之外的位置');
    }
    return directory;
  }

  Future<int> size() async {
    final directory = await _coverDirectory();
    return directory == null ? 0 : directoryBytes(directory);
  }

  Future<int> clear() async {
    final directory = await _coverDirectory();
    if (directory == null) return 0;
    var freed = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final resolved = await entity.resolveSymbolicLinks();
      if (!path.isWithin(directory.path, resolved)) {
        throw const FileSystemException('缓存文件不在允许清理的目录中');
      }
      final size = await entity.length();
      await entity.delete();
      freed += size;
    }
    return freed;
  }
}
