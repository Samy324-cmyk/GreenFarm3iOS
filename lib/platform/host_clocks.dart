import 'dart:ffi';
import 'dart:io';

/// Separate real clocks preserve the original distinction between Android
/// elapsedRealtime (includes suspend), Linux monotonic (excludes suspend),
/// and the process CPU clock used by the recovered nativeU implementation.
abstract class HostClocks {
  static HostClocks open() {
    if (Platform.isIOS || Platform.isMacOS) return _DarwinClocks();
    if (Platform.isWindows) return _WindowsClocks();
    if (Platform.isLinux) return _LinuxClocks();
    throw UnsupportedError(
      'Host clocks are not implemented for ${Platform.operatingSystem}',
    );
  }

  int elapsedRealtimeMillis();
  int monotonicNanos();
  int processCpuClockTicks();
  void dispose() {}
}

final class _Timespec extends Struct {
  @Long()
  external int seconds;
  @Long()
  external int nanoseconds;
}

class _LinuxClocks extends HostClocks {
  _LinuxClocks() {
    final library = DynamicLibrary.process();
    _gettime = library
        .lookupFunction<
          Int32 Function(Int32, Pointer<_Timespec>),
          int Function(int, Pointer<_Timespec>)
        >('clock_gettime');
    _cpu = library.lookupFunction<Long Function(), int Function()>('clock');
    final calloc = library
        .lookupFunction<
          Pointer<Void> Function(UintPtr, UintPtr),
          Pointer<Void> Function(int, int)
        >('calloc');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    _value = calloc(1, sizeOf<_Timespec>()).cast();
    if (_value == nullptr)
      throw StateError('Cannot allocate native clock storage');
  }
  late final int Function(int, Pointer<_Timespec>) _gettime;
  late final int Function() _cpu;
  late final void Function(Pointer<Void>) _free;
  late final Pointer<_Timespec> _value;
  bool _disposed = false;
  int _nanos(int clock) {
    if (_disposed) throw StateError('Clock storage has been disposed');
    if (_gettime(clock, _value) != 0)
      throw StateError('clock_gettime($clock) failed');
    return _value.ref.seconds * 1000000000 + _value.ref.nanoseconds;
  }

  @override
  int elapsedRealtimeMillis() => _nanos(7) ~/ 1000000;
  @override
  int monotonicNanos() => _nanos(1);
  @override
  int processCpuClockTicks() => _cpu();
  @override
  void dispose() {
    if (!_disposed) {
      _free(_value.cast());
      _disposed = true;
    }
  }
}

class _DarwinClocks extends HostClocks {
  _DarwinClocks() {
    final library = DynamicLibrary.process();
    _nanos = library.lookupFunction<Uint64 Function(Int32), int Function(int)>(
      'clock_gettime_nsec_np',
    );
    _cpu = library.lookupFunction<UnsignedLong Function(), int Function()>(
      'clock',
    );
  }
  late final int Function(int) _nanos;
  late final int Function() _cpu;
  // Darwin Libc _time.h: MONOTONIC_RAW=4, UPTIME_RAW=8.
  // https://github.com/apple-oss-distributions/Libc/blob/main/include/_time.h
  @override
  int elapsedRealtimeMillis() => _nanos(4) ~/ 1000000;
  @override
  int monotonicNanos() => _nanos(8);
  @override
  int processCpuClockTicks() => _cpu();
}

class _WindowsClocks extends HostClocks {
  _WindowsClocks() {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final crt = DynamicLibrary.open('ucrtbase.dll');
    _elapsed = kernel.lookupFunction<Uint64 Function(), int Function()>(
      'GetTickCount64',
    );
    _unbiased = DynamicLibrary.open('kernelbase.dll')
        .lookupFunction<
          Void Function(Pointer<Uint64>),
          void Function(Pointer<Uint64>)
        >('QueryUnbiasedInterruptTimePrecise');
    _process = kernel
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetCurrentProcess',
        )();
    _times = kernel
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetProcessTimes');
    final calloc = crt
        .lookupFunction<
          Pointer<Void> Function(UintPtr, UintPtr),
          Pointer<Void> Function(int, int)
        >('calloc');
    _free = crt
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    _data = calloc(5, 8).cast<Uint64>();
    if (_data == nullptr)
      throw StateError('Cannot allocate native clock storage');
  }
  late final int Function() _elapsed;
  late final void Function(Pointer<Uint64>) _unbiased;
  late final Pointer<Void> _process;
  late final int Function(
    Pointer<Void>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
  )
  _times;
  late final void Function(Pointer<Void>) _free;
  late final Pointer<Uint64> _data;
  bool _disposed = false;
  void _check() {
    if (_disposed) throw StateError('Clock storage has been disposed');
  }

  @override
  int elapsedRealtimeMillis() {
    _check();
    return _elapsed();
  }

  @override
  int monotonicNanos() {
    _check();
    _unbiased(_data);
    return _data.value * 100;
  }

  @override
  int processCpuClockTicks() {
    _check();
    if (_times(_process, _data + 1, _data + 2, _data + 3, _data + 4) == 0)
      throw StateError('GetProcessTimes failed');
    return (_data[3] + _data[4]) ~/ 10;
  }

  @override
  void dispose() {
    if (!_disposed) {
      _free(_data.cast());
      _disposed = true;
    }
  }
}
