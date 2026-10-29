import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/java_zip.dart';
import 'package:green_farm_port/engine/dalvik/native_utils.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  const owner = 'Lcom/gameloft/android/wrapper/NativeUtils;';
  const delegate = 'Lcom/gameloft/android/wrapper/Jb;';
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    vm.registerExternalClass(owner);
    vm.registerExternalClass(delegate);
    vm.registerMethod(
      DalvikMethod('$owner-><clinit>()V', 8, (vm, arguments) {
        return vm.call('Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V', [
          vm.newString('nativeU'),
        ], kind: 'static');
      }),
    );
  });
  Object? call(String member, [List<Object?> args = const []]) =>
      vm.call('$owner->$member', args, kind: 'static');
  test('nativeU load acknowledges only the installed semantic port', () {
    final environment = NativeUtilsEnvironment(monotonicNanos: () => 123456789);
    registerNativeUtils(vm, environment: environment);
    expect(environment.nativeULoaded, false);
    expect(call('tm()J'), 123);
    expect(environment.nativeULoaded, true);
    expect(
      () => vm.call('Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V', [
        vm.newString('unknown'),
      ], kind: 'static'),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });
  test('root detection uses exact original paths and short circuit order', () {
    for (var match = 0; match < 4; match++) {
      final current = DalvikRuntime();
      registerJavaCore(current);
      current.registerExternalClass(owner);
      final visited = <String>[];
      registerNativeUtils(
        current,
        environment: NativeUtilsEnvironment(
          canOpenRead: (path) {
            visited.add('fopen:$path');
            return match == 0;
          },
          statExists: (path) {
            visited.add('stat:$path');
            return match == visited.length - 1;
          },
        ),
      );
      expect(
        current.call('$owner->CheckRoot()Z', [], kind: 'static'),
        match < 3 ? 1 : 0,
      );
      expect(visited, [
        'fopen:/system/app/Superuser.apk',
        if (match >= 1) 'stat:/system/bin/su',
        if (match >= 2) 'stat:/system/xbin/su',
      ]);
    }
  });
  test('host file probes execute actual libc open/stat on private fixtures', () {
    final directory = Directory.systemTemp.createTempSync(
      'green-farm-native-test-',
    );
    try {
      final file = File('${directory.path}/actual.bin')
        ..writeAsBytesSync([1, 2, 3]);
      final probes = NativeUFileProbes();
      expect(probes.canOpenRead(file.path), true);
      expect(probes.statExists(file.path), true);
      expect(probes.statExists(directory.path), true);
      expect(probes.canOpenRead('${directory.path}/absent'), false);
      expect(probes.statExists('${directory.path}/absent'), false);
    } finally {
      final expected =
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}green-farm-native-test-';
      if (!directory.absolute.path.startsWith(expected)) {
        throw StateError('Unexpected fixture directory');
      }
      directory.deleteSync(recursive: true);
    }
  });
  test(
    'monotonic clock keeps nanoseconds and truncates millis, requires provider',
    () {
      var now = 7654321987654321;
      registerNativeUtils(
        vm,
        environment: NativeUtilsEnvironment(monotonicNanos: () => now),
      );
      expect(call('getClockNano()J'), now);
      expect(call('getClockMillis()J'), 7654321987);
      now += 1000001;
      expect(call('tm()J'), 7654321988);
      expect(() => call('getClock()F'), throwsA(isA<MissingDalvikBridge>()));
    },
  );
  test(
    'CPU clock agrees with 1012 independent JVM float conversion vectors',
    () {
      var ticks = 0;
      registerNativeUtils(
        vm,
        environment: NativeUtilsEnvironment(processCpuClockTicks: () => ticks),
      );
      final rows = jsonDecode(
        File('test/oracles/fixtures/native_clock.json').readAsStringSync(),
      ) as List;
      expect(rows.length, 1012);
      for (final row in rows) {
        ticks = int.parse(row['ticks'] as String);
        expect(
          call('getClock()F'),
          row['float_bits'],
          reason: '$ticks CPU ticks',
        );
      }
    },
  );
  test(
    'sp preserves original delegate and cooperative suspension exactly once',
    () async {
      registerNativeUtils(vm, environment: NativeUtilsEnvironment());
      var calls = 0;
      final words = <Object?>[0, 0];
      JBits.setWide(words, 0, 0x12345678abcdef01);
      vm.registerNative('$delegate->sp(J)V', (vm, args) {
        calls++;
        expect(JBits.wide(args, 0), 0x12345678abcdef01);
        vm.suspendUntil(Future<Object?>.value(null));
      });
      await DalvikExecutor().run(() => call('sp(J)V', words));
      expect(calls, 1);
    },
  );
  test('native size check reads actual supplied APK through Java ZipFile', () {
    registerJavaCollections(vm);
    registerJavaIo(vm);
    registerJavaZip(vm);
    registerNativeUtils(vm, environment: NativeUtilsEnvironment());
    final source = File('assets/provenance/original.apk').absolute.path;
    vm.registerNative(
      '$delegate->kz()Ljava/lang/String;',
      (vm, arguments) => vm.newString(source),
    );
    expect(call('sd()J'), 9362740);
    final input = <Object?>[0, 0];
    JBits.setWide(input, 0, 9362740 ^ 0x226bc);
    expect(call('checkPlatformService(J)Z', input), 1);
    // Pt separately checks all .dex entries; sd examines only classes.dex.
    JBits.setWide(input, 0, 20421524);
    expect(call('checkPlatformService(J)Z', input), 0);
  });
  test(
    'sd preserves ZIP lookup and resumes each nested native operation once',
    () async {
      registerNativeUtils(vm, environment: NativeUtilsEnvironment());
      const zipType = 'Ljava/util/zip/ZipFile;',
          entryType = 'Ljava/util/zip/ZipEntry;';
      vm.registerExternalClass(zipType);
      vm.registerExternalClass(entryType);
      final calls = <String>[];
      vm.registerNative('$delegate->kz()Ljava/lang/String;', (vm, a) {
        calls.add('source');
        vm.suspendUntil(
          Future<Object?>.value(vm.newString('/fixture/original.apk')),
        );
      });
      vm.registerNative('$zipType-><init>(Ljava/lang/String;)V', (vm, a) {
        calls.add('open');
        expect(vm.string(a[1]), '/fixture/original.apk');
        vm.suspendUntil(Future<Object?>.value(null));
      });
      vm.registerNative('$zipType->getEntry(Ljava/lang/String;)$entryType', (
        vm,
        a,
      ) {
        calls.add('entry');
        expect(vm.string(a[1]), 'classes.dex');
        vm.suspendUntil(Future<Object?>.value(DalvikObject(entryType)));
      });
      vm.registerNative('$entryType->getSize()J', (vm, a) {
        calls.add('size');
        return 9362740;
      });
      expect(await DalvikExecutor().run(() => call('sd()J')), 9362740);
      expect(calls, ['source', 'open', 'entry', 'size']);
      calls.clear();
      final input = <Object?>[0, 0];
      JBits.setWide(input, 0, 9362740 ^ 0x226bc);
      expect(
        await DalvikExecutor().run(
          () => call('checkPlatformService(J)Z', input),
        ),
        1,
      );
      input[0] = (input[0] as int) ^ 1;
      expect(
        await DalvikExecutor().run(
          () => call('checkPlatformService(J)Z', input),
        ),
        0,
      );
    },
  );
}
