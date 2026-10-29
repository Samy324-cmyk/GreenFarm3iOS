import 'dart:ffi';
import 'dart:io';

import '../engine/dalvik/android_context.dart' show AndroidFileSystemStats;

/// Actual Windows volume allocation statistics, including per-user availability.
class WindowsFileSystem {
  WindowsFileSystem.open() {
    if (!Platform.isWindows) throw UnsupportedError('Windows filesystem host');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final crt = DynamicLibrary.open('ucrtbase.dll');
    _malloc = crt
        .lookupFunction<
          Pointer<Void> Function(UintPtr),
          Pointer<Void> Function(int)
        >('malloc');
    _free = crt
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    _volume = kernel
        .lookupFunction<
          Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
          int Function(Pointer<Uint16>, Pointer<Uint16>, int)
        >('GetVolumePathNameW');
    _disk = kernel
        .lookupFunction<
          Int32 Function(
            Pointer<Uint16>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          ),
          int Function(
            Pointer<Uint16>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          )
        >('GetDiskFreeSpaceW');
    _bytes = kernel
        .lookupFunction<
          Int32 Function(
            Pointer<Uint16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Uint16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetDiskFreeSpaceExW');
    _error = kernel.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
  }
  late final Pointer<Void> Function(int) _malloc;
  late final void Function(Pointer<Void>) _free;
  late final int Function(Pointer<Uint16>, Pointer<Uint16>, int) _volume;
  late final int Function(
    Pointer<Uint16>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  _disk;
  late final int Function(
    Pointer<Uint16>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
  )
  _bytes;
  late final int Function() _error;
  bool _disposed = false;
  void dispose() {
    _disposed = true;
  }

  AndroidFileSystemStats stats(String absolutePath) {
    if (_disposed) throw StateError('Filesystem host is disposed');
    if (!Directory(absolutePath).isAbsolute) {
      throw ArgumentError.value(absolutePath, 'absolutePath');
    }
    final allocations = <Pointer<Void>>[];
    Pointer<Void> allocate(int size) {
      final result = _malloc(size);
      if (result == nullptr) {
        throw StateError('Cannot allocate volume-stat storage');
      }
      allocations.add(result);
      return result;
    }

    void check(int success) {
      if (success == 0) {
        throw FileSystemException(
          'Windows volume query failed',
          absolutePath,
          OSError('Win32 error', _error()),
        );
      }
    }

    try {
      final path = allocate((absolutePath.length + 1) * 2).cast<Uint16>();
      path.asTypedList(absolutePath.length + 1)
        ..setRange(0, absolutePath.length, absolutePath.codeUnits)
        ..[absolutePath.length] = 0;
      final root = allocate(32768 * 2).cast<Uint16>();
      check(_volume(path, root, 32768));
      final words = allocate(16).cast<Uint32>();
      check(_disk(root, words, words + 1, words + 2, words + 3));
      final blockSize = words[0] * words[1];
      if (blockSize <= 0) {
        throw FileSystemException('Invalid allocation-unit size', absolutePath);
      }
      final bytes = allocate(24).cast<Uint64>();
      check(_bytes(path, bytes, bytes + 1, bytes + 2));
      return AndroidFileSystemStats(
        blockSize: blockSize,
        blockCount: bytes[1] ~/ blockSize,
        availableBlocks: bytes[0] ~/ blockSize,
        freeBlocks: bytes[2] ~/ blockSize,
      );
    } finally {
      for (final allocation in allocations.reversed) {
        _free(allocation);
      }
    }
  }
}
