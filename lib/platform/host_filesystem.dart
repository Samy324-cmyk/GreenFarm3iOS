import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../engine/dalvik/android_context.dart';
import 'windows_filesystem.dart';

abstract class HostFileSystem {
  static HostFileSystem open() {
    if (Platform.isIOS) return _IosFileSystem();
    if (Platform.isWindows) return _WindowsFileSystem();
    throw UnsupportedError(
      'Filesystem statistics are not implemented for ${Platform.operatingSystem}',
    );
  }

  AndroidFileSystemStats stats(String absolutePath);
  void dispose();
}

class _WindowsFileSystem extends HostFileSystem {
  final WindowsFileSystem _host = WindowsFileSystem.open();
  @override
  AndroidFileSystemStats stats(String absolutePath) =>
      _host.stats(absolutePath);
  @override
  void dispose() => _host.dispose();
}

class _IosFileSystem extends HostFileSystem {
  _IosFileSystem() {
    final library = DynamicLibrary.process();
    _stat = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Uint64>),
          int Function(Pointer<Uint8>, Pointer<Uint64>)
        >('gf3_statfs');
    _allocate = library
        .lookupFunction<
          Pointer<Void> Function(UintPtr, UintPtr),
          Pointer<Void> Function(int, int)
        >('calloc');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    _values = _allocate(4, sizeOf<Uint64>()).cast();
    if (_values == nullptr) {
      throw StateError('Cannot allocate filesystem statistics');
    }
  }

  late final int Function(Pointer<Uint8>, Pointer<Uint64>) _stat;
  late final Pointer<Void> Function(int, int) _allocate;
  late final void Function(Pointer<Void>) _free;
  late final Pointer<Uint64> _values;
  bool _disposed = false;

  @override
  AndroidFileSystemStats stats(String absolutePath) {
    if (_disposed) throw StateError('Filesystem statistics have been disposed');
    if (!absolutePath.startsWith('/') || absolutePath.contains('\u0000')) {
      throw ArgumentError.value(absolutePath, 'absolutePath');
    }
    final bytes = utf8.encode(absolutePath);
    final path = _allocate(bytes.length + 1, 1).cast<Uint8>();
    if (path == nullptr) throw StateError('Cannot allocate filesystem path');
    try {
      path.asTypedList(bytes.length).setAll(0, bytes);
      final error = _stat(path, _values);
      if (error != 0) {
        throw FileSystemException(
          'statfs failed',
          absolutePath,
          OSError('Darwin errno', error),
        );
      }
      return AndroidFileSystemStats(
        blockSize: _values[0],
        blockCount: _values[1],
        availableBlocks: _values[2],
        freeBlocks: _values[3],
      );
    } finally {
      _free(path.cast());
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _free(_values.cast());
      _disposed = true;
    }
  }
}
