import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0372.dart';

void main() {
  const game = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/cGame;';
  const gllib = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GLLib;';
  for (final interrupted in [false, true]) {
    test(
      'original am resumes native sleep and original catch table ($interrupted)',
      () async {
        final vm = DalvikRuntime();
        registerJavaCore(vm);
        registerClass372(vm);
        // Isolate one original game method; no unrelated platform startup runs.
        vm.classes[game]!.initialization = 2;
        vm.registerExternalClass(gllib);
        vm.registerExternalClass('Ljava/lang/Thread;');
        final events = <String>[];
        final pending = Completer<Object?>();
        vm.registerNative('$game->nz(I)V', (_, a) {
          events.add('nz:${a[0]}');
          return null;
        });
        vm.registerNative('Ljava/lang/Thread;->sleep(J)V', (_, a) {
          events.add('sleep:${a[0]}');
          vm.suspendUntil(pending.future);
        });
        vm.registerNative('$gllib->j6(Ljava/lang/String;)Z', (_, a) {
          events.add(vm.string(a[0]));
          return 1;
        });
        final execution = DalvikExecutor().run(
          () => vm.call('$game->am()V', [], kind: 'static'),
        );
        expect(events, ['nz:60', 'sleep:1000']);
        if (interrupted) {
          pending.completeError(
            DalvikThrown(DalvikObject('Ljava/lang/InterruptedException;')),
          );
        } else {
          pending.complete(null);
        }
        await execution;
        expect(events, [
          'nz:60',
          'sleep:1000',
          'http://www.gameloft.com/customer-support-contacts/',
        ]);
      },
    );
  }

  test(
    'suspended class initialization resumes field access and waiting threads',
    () async {
      final vm = DalvikRuntime();
      registerJavaCore(vm);
      vm.currentThreadHook = () => Zone.current[#thread] ?? 'main';
      vm.registerClass(
        DalvikClass(
          'LInit;',
          superclass: 'Ljava/lang/Object;',
          staticFields: {'LInit;->n:I': 0},
        ),
      );
      final gate = Completer<Object?>();
      var initialized = 0;
      vm.registerMethod(
        DalvikMethod('LInit;-><clinit>()V', 8, (vm, a) {
          initialized++;
          return dalvikThen(() => vm.suspendUntil(gate.future), (_) {
            vm.putStatic('LInit;', 'LInit;->n:I', 42);
            return null;
          });
        }),
      );
      final first = runZoned(
        () => DalvikExecutor().run(() => vm.getStatic('LInit;', 'LInit;->n:I')),
        zoneValues: {#thread: 'first'},
      );
      final second = runZoned(
        () => DalvikExecutor().run(() => vm.getStatic('LInit;', 'LInit;->n:I')),
        zoneValues: {#thread: 'second'},
      );
      expect(vm.classes['LInit;']!.initialization, 1);
      gate.complete(null);
      expect(await first, 42);
      expect(await second, 42);
      expect(initialized, 1);
      expect(vm.classes['LInit;']!.initialization, 2);
    },
  );

  test(
    'synchronized method keeps its monitor across suspended native work',
    () async {
      final vm = DalvikRuntime();
      registerJavaCore(vm);
      vm.registerClass(DalvikClass('LSync;', superclass: 'Ljava/lang/Object;'));
      final gate = Completer<Object?>();
      final events = <String>[];
      vm.monitorEnterHook = (_) => events.add('enter');
      vm.monitorExitHook = (_) => events.add('exit');
      vm.registerMethod(
        DalvikMethod(
          'LSync;->run()I',
          0x21,
          (vm, a) => vm.suspendUntil(gate.future),
        ),
      );
      final object = vm.allocate('LSync;');
      final result = DalvikExecutor().run(
        () => vm.call('LSync;->run()I', [object], kind: 'virtual'),
      );
      expect(events, ['enter']);
      gate.complete(27);
      expect(await result, 27);
      expect(events, ['enter', 'exit']);
    },
  );
}
