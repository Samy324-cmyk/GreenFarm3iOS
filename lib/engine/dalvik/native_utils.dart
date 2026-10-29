import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'cooperative.dart';
import 'numbers.dart';
import 'runtime.dart';

/// Host facts consumed by the recovered libnativeU implementation. Clock
/// origins and units are explicit: Android CLOCK_MONOTONIC nanoseconds and
/// POSIX clock() ticks at CLOCKS_PER_SEC=1,000,000, respectively.
class NativeUtilsEnvironment {
  NativeUtilsEnvironment({
    this.monotonicNanos,
    this.processCpuClockTicks,
    this.canOpenRead,
    this.statExists,
  });
  final int Function()? monotonicNanos, processCpuClockTicks;
  final bool Function(String path)? canOpenRead, statExists;
  bool nativeULoaded = false;
  NativeUFileProbes? _files;
  NativeUFileProbes get files => _files ??= NativeUFileProbes();
}

typedef _AllocateNative = Pointer<Void> Function(IntPtr size);
typedef _Allocate = Pointer<Void> Function(int size);
typedef _FreeNative = Void Function(Pointer<Void> pointer);
typedef _Free = void Function(Pointer<Void> pointer);
typedef _OpenNative = Pointer<Void> Function(
  Pointer<Uint8> path,
  Pointer<Uint8> mode,
);
typedef _Open = Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _CloseNative = Int32 Function(Pointer<Void> file);
typedef _Close = int Function(Pointer<Void> file);
typedef _StatNative = Int32 Function(Pointer<Uint8> path, Pointer<Void> buffer);
typedef _Stat = int Function(Pointer<Uint8> path, Pointer<Void> buffer);

/// Calls only the current host's standard C runtime. No APK ELF is loaded.
/// stat's result is inspected without interpreting its platform-specific data.
class NativeUFileProbes {
  NativeUFileProbes() {
    final library = Platform.isWindows
        ? DynamicLibrary.open('ucrtbase.dll')
        : DynamicLibrary.process();
    _allocate = library.lookupFunction<_AllocateNative, _Allocate>('malloc');
    _free = library.lookupFunction<_FreeNative, _Free>('free');
    _open = library.lookupFunction<_OpenNative, _Open>('fopen');
    _close = library.lookupFunction<_CloseNative, _Close>('fclose');
    _stat = library.lookupFunction<_StatNative, _Stat>(
      Platform.isWindows ? '_stat64' : 'stat',
    );
  }
  late final _Allocate _allocate;
  late final _Free _free;
  late final _Open _open;
  late final _Close _close;
  late final _Stat _stat;

  Pointer<Uint8> _text(String value) {
    final encoded = utf8.encode(value);
    final pointer = _allocate(encoded.length + 1).cast<Uint8>();
    if (pointer == nullptr) throw StateError('C runtime allocation failed');
    pointer.asTypedList(encoded.length + 1)
      ..setRange(0, encoded.length, encoded)
      ..[encoded.length] = 0;
    return pointer;
  }

  bool canOpenRead(String path) {
    final pathPointer = _text(path);
    final mode = _text('rb');
    try {
      final handle = _open(pathPointer, mode);
      if (handle == nullptr) return false;
      _close(handle);
      return true;
    } finally {
      _free(pathPointer.cast<Void>());
      _free(mode.cast<Void>());
    }
  }

  bool statExists(String path) {
    final pathPointer = _text(path);
    // Darwin/Bionic/glibc/Windows stat structures fit within 512 bytes. malloc
    // supplies their required alignment; the structure's fields are not read.
    final buffer = _allocate(512);
    if (buffer == nullptr) {
      _free(pathPointer.cast<Void>());
      throw StateError('C runtime allocation failed');
    }
    try {
      return _stat(pathPointer, buffer) != -1;
    } finally {
      _free(pathPointer.cast<Void>());
      _free(buffer);
    }
  }
}

/// Direct semantic port of the supplied x86_64 and ARM64 libnativeU.so.
/// See game_source/native_utils_semantics.json for addresses and evidence.
/// Original NativeUtils/Jb class metadata and Java delegates remain generated.
void registerNativeUtils(
  DalvikRuntime vm, {
  required NativeUtilsEnvironment environment,
}) {
  const owner = 'Lcom/gameloft/android/wrapper/NativeUtils;';
  const delegate = 'Lcom/gameloft/android/wrapper/Jb;';
  void native(String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);

  // Acknowledges only the installed, recovered implementation. Unknown native
  // libraries remain explicit missing integrations instead of silently loading.
  vm.registerNative('Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V', (
    _,
    arguments,
  ) {
    final name = vm.string(arguments[0]);
    if (name != 'nativeU') {
      throw MissingDalvikBridge('native library $name');
    }
    environment.nativeULoaded = true;
    return null;
  });

  native('CheckRoot()Z', (_, arguments) {
    final open = environment.canOpenRead ?? environment.files.canOpenRead;
    if (open('/system/app/Superuser.apk')) return 1;
    final stat = environment.statExists ?? environment.files.statExists;
    if (stat('/system/bin/su')) return 1;
    return stat('/system/xbin/su') ? 1 : 0;
  });

  int nanos() {
    final source = environment.monotonicNanos;
    if (source == null) {
      throw MissingDalvikBridge('NativeUtils CLOCK_MONOTONIC nanoseconds');
    }
    return source();
  }

  native('getClockNano()J', (_, arguments) => nanos());
  native('getClockMillis()J', (_, arguments) => nanos() ~/ 1000000);
  native('tm()J', (_, arguments) => nanos() ~/ 1000000);
  native('getClock()F', (_, arguments) {
    final source = environment.processCpuClockTicks;
    if (source == null) {
      throw MissingDalvikBridge('NativeUtils POSIX process CPU clock');
    }
    final registers = <Object?>[0, 0];
    JBits.setWide(registers, 0, source());
    JBits.unary(0x85, registers, 0, 0); // int64 -> float32, one rounding.
    JBits.setFloat(registers, 0, JBits.float(registers, 0) / 1000000.0);
    return registers[0];
  });
  native(
    'sp(J)V',
    (_, arguments) => vm.call('$delegate->sp(J)V', arguments, kind: 'static'),
  );
  native(
    'sd()J',
    (_, arguments) => dalvikThen(
      () => vm.call('$delegate->kz()Ljava/lang/String;', [], kind: 'static'),
      (path) {
        const zipType = 'Ljava/util/zip/ZipFile;';
        final zip = vm.allocate(zipType);
        return dalvikThen(
          () => vm.call('$zipType-><init>(Ljava/lang/String;)V', [
            zip,
            path,
          ], kind: 'direct'),
          (_) => dalvikThen(
            () => vm.call(
              '$zipType->getEntry(Ljava/lang/String;)Ljava/util/zip/ZipEntry;',
              [zip, vm.newString('classes.dex')],
              kind: 'virtual',
            ),
            (entry) => vm.call('Ljava/util/zip/ZipEntry;->getSize()J', [
              entry,
            ], kind: 'virtual'),
            methodKey: '$owner->sd <entry>',
          ),
          methodKey: '$owner->sd <archive>',
        );
      },
      methodKey: '$owner->sd <source path>',
    ),
  );
  native('checkPlatformService(J)Z', (_, arguments) {
    final expected = JBits.wide(arguments, 0) ^ 0x226bc;
    return dalvikThen(
      () => vm.call('$owner->sd()J', [], kind: 'static'),
      (size) => size == expected ? 1 : 0,
      methodKey: '$owner->checkPlatformService <size>',
    );
  });
}
