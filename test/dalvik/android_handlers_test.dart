import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/android_handlers.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_reflection.dart';
import 'package:green_farm_port/engine/dalvik/java_threads.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0090.dart';
import 'package:green_farm_port/generated/c0091.dart';
import 'package:green_farm_port/generated/c0093.dart';
import 'package:green_farm_port/generated/c0094.dart';

const handlerClass = 'Landroid/os/Handler;';
const messageClass = 'Landroid/os/Message;';

void main() {
  late DalvikRuntime vm;
  late JavaThreadScheduler scheduler;
  late AndroidHandlerEnvironment env;
  late int uptime;
  final failures = <Object>[];
  var runnableId = 0;
  DalvikObject make(
    String owner, [
    String signature = '()V',
    List<Object?> args = const [],
  ]) {
    final object = vm.allocate(owner);
    vm.call('$owner-><init>$signature', [object, ...args], kind: 'direct');
    return object;
  }

  Object? call(
    DalvikObject object,
    String method, [
    List<Object?> args = const [],
  ]) => vm.call('${object.className}->$method', [
    object,
    ...args,
  ], kind: 'virtual');
  DalvikObject runnable(Object? Function() action) {
    final name = 'Ltest/Runnable${runnableId++};';
    vm.registerExternalClass(name, interfaces: ['Ljava/lang/Runnable;']);
    vm.registerNative('$name->run()V', (_, a) => action());
    return DalvikObject(name);
  }

  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaReflection(vm);
    scheduler = registerJavaThreads(vm);
    uptime = 100;
    failures.clear();
    env = AndroidHandlerEnvironment(
      vm: vm,
      scheduler: scheduler,
      uptimeMillis: () => uptime,
      onError: (e, s) => failures.add(e),
    );
    registerAndroidHandlers(vm, environment: env);
  });
  tearDown(() => env.dispose());
  Future<void> advance(WidgetTester tester, int ms) async {
    uptime += ms;
    await tester.pump(Duration(milliseconds: ms));
  }

  testWidgets(
    'main queue orders handlers, equal deadlines and front-of-queue posts',
    (tester) async {
      final a = make(handlerClass), b = make(handlerClass), seen = <String>[];
      DalvikObject r(String value) => runnable(() {
        seen.add(value);
        return null;
      });
      call(a, 'postDelayed(Ljava/lang/Runnable;J)Z', [r('a10'), 10, 0]);
      call(b, 'postDelayed(Ljava/lang/Runnable;J)Z', [r('b5'), 5, 0]);
      call(b, 'postDelayed(Ljava/lang/Runnable;J)Z', [r('b10'), 10, 0]);
      call(a, 'post(Ljava/lang/Runnable;)Z', [r('now')]);
      call(a, 'postAtFrontOfQueue(Ljava/lang/Runnable;)Z', [r('front1')]);
      call(b, 'postAtFrontOfQueue(Ljava/lang/Runnable;)Z', [r('front2')]);
      await tester.pump(Duration.zero);
      expect(seen, ['front2', 'front1', 'now']);
      await advance(tester, 5);
      expect(seen.last, 'b5');
      await advance(tester, 5);
      expect(seen, ['front2', 'front1', 'now', 'b5', 'a10', 'b10']);
      expect(env.pendingCount, 0);
      expect(failures, isEmpty);
      final looper = call(a, 'getLooper()Landroid/os/Looper;') as DalvikObject;
      expect(looper, same(call(b, 'getLooper()Landroid/os/Looper;')));
      expect(
        call(looper, 'getThread()Ljava/lang/Thread;'),
        same(scheduler.currentThread),
      );
    },
  );

  testWidgets(
    'cancellation uses runnable/token identity and never cancels other handlers',
    (tester) async {
      final a = make(handlerClass), b = make(handlerClass), seen = <String>[];
      final r = runnable(() {
            seen.add('r');
            return null;
          }),
          token1 = DalvikObject('Ljava/lang/Object;'),
          token2 = DalvikObject('Ljava/lang/Object;');
      call(a, 'postAtTime(Ljava/lang/Runnable;Ljava/lang/Object;J)Z', [
        r,
        token1,
        120,
        0,
      ]);
      call(a, 'postAtTime(Ljava/lang/Runnable;Ljava/lang/Object;J)Z', [
        r,
        token2,
        120,
        0,
      ]);
      call(b, 'postDelayed(Ljava/lang/Runnable;J)Z', [r, 20, 0]);
      call(a, 'removeCallbacks(Ljava/lang/Runnable;Ljava/lang/Object;)V', [
        r,
        token1,
      ]);
      expect(call(a, 'hasCallbacks(Ljava/lang/Runnable;)Z', [r]), 1);
      call(a, 'removeCallbacksAndMessages(Ljava/lang/Object;)V', [token2]);
      expect(call(a, 'hasCallbacks(Ljava/lang/Runnable;)Z', [r]), 0);
      await advance(tester, 20);
      expect(seen, ['r']);
    },
  );

  testWidgets(
    'due time is rechecked against uptime after a simulated device sleep',
    (tester) async {
      final a = make(handlerClass);
      var count = 0;
      call(a, 'postDelayed(Ljava/lang/Runnable;J)Z', [
        runnable(() {
          count++;
          return null;
        }),
        40,
        0,
      ]);
      await tester.pump(
        const Duration(milliseconds: 40),
      ); // Timer elapsed; uptime deliberately unchanged.
      expect(count, 0);
      await advance(tester, 40);
      expect(count, 1);
    },
  );

  testWidgets(
    'a paused callback serializes later messages and preserves cancellation',
    (tester) async {
      final a = make(handlerClass),
          gate = Completer<Object?>(),
          seen = <String>[];
      final slow = runnable(() {
        seen.add('begin');
        vm.suspendUntil(
          gate.future.then((_) {
            seen.add('end');
            return null;
          }),
        );
      });
      final removed = runnable(() {
        seen.add('removed');
        return null;
      });
      call(a, 'post(Ljava/lang/Runnable;)Z', [slow]);
      call(a, 'post(Ljava/lang/Runnable;)Z', [removed]);
      call(a, 'post(Ljava/lang/Runnable;)Z', [
        runnable(() {
          seen.add('last');
          return null;
        }),
      ]);
      await tester.pump(Duration.zero);
      expect(seen, ['begin']);
      call(a, 'removeCallbacks(Ljava/lang/Runnable;)V', [
        slow,
      ]); // Already running: cannot cancel.
      call(a, 'removeCallbacks(Ljava/lang/Runnable;)V', [removed]);
      gate.complete(null);
      await tester.pump(Duration.zero);
      expect(seen, ['begin', 'end', 'last']);
    },
  );

  testWidgets('a message selected while main is occupied remains cancellable', (
    tester,
  ) async {
    final gate = Completer<Object?>();
    final busy = scheduler.runMain(() => vm.suspendUntil(gate.future));
    final a = make(handlerClass);
    var ran = false;
    final r = runnable(() {
      ran = true;
      return null;
    });
    call(a, 'post(Ljava/lang/Runnable;)Z', [r]);
    await tester.pump(Duration.zero);
    call(a, 'removeCallbacks(Ljava/lang/Runnable;)V', [r]);
    gate.complete(null);
    await tester.pump(Duration.zero);
    await busy;
    expect(ran, false);
    expect(env.pendingCount, 0);
  });

  testWidgets(
    'messages dispatch through subclass, prevent reuse and recycle after completion',
    (tester) async {
      const child = 'Ltest/Handler;';
      vm.registerExternalClass(child, superclass: handlerClass);
      final seen = <Object?>[];
      vm.registerNative('$child->handleMessage(Landroid/os/Message;)V', (_, a) {
        seen.add(vm.getField(a[1], '$messageClass->what:I'));
        return null;
      });
      final h = vm.allocate(child);
      vm.call('$handlerClass-><init>()V', [h], kind: 'direct');
      final m = call(h, 'obtainMessage(III)Landroid/os/Message;', [
        27,
        3,
        4,
      ]) as DalvikObject;
      call(m, 'sendToTarget()V');
      expect(call(h, 'hasMessages(I)Z', [27]), 1);
      expect(
        () => call(h, 'sendMessage(Landroid/os/Message;)Z', [m]),
        throwsA(isA<DalvikThrown>()),
      );
      expect(() => call(m, 'recycle()V'), throwsA(isA<DalvikThrown>()));
      await tester.pump(Duration.zero);
      expect(seen, [27]);
      expect(vm.getField(m, '$messageClass->what:I'), 0);
      expect(call(m, 'getTarget()Landroid/os/Handler;'), isNull);
      expect(call(h, 'hasMessages(I)Z', [27]), 0);
      env.dispose();
      expect(call(h, 'post(Ljava/lang/Runnable;)Z', [runnable(() => null)]), 0);
    },
  );

  testWidgets(
    'Handler.Callback may suspend and then fall through to handleMessage',
    (tester) async {
      final gate = Completer<Object?>();
      const callback = 'Ltest/HandlerCallback;',
          child = 'Ltest/CallbackHandler;';
      vm.registerExternalClass(
        callback,
        interfaces: ['Landroid/os/Handler\$Callback;'],
      );
      vm.registerNative(
        '$callback->handleMessage(Landroid/os/Message;)Z',
        (_, a) => vm.suspendUntil(gate.future),
      );
      vm.registerExternalClass(child, superclass: handlerClass);
      var fallthrough = 0;
      vm.registerNative('$child->handleMessage(Landroid/os/Message;)V', (_, a) {
        fallthrough++;
        return null;
      });
      final h = vm.allocate(child);
      vm.call('$handlerClass-><init>(Landroid/os/Handler\$Callback;)V', [
        h,
        DalvikObject(callback),
      ], kind: 'direct');
      call(h, 'sendEmptyMessage(I)Z', [1]);
      await tester.pump(Duration.zero);
      expect(fallthrough, 0);
      gate.complete(0);
      await tester.pump(Duration.zero);
      expect(fallthrough, 1);
      expect(failures, isEmpty);
    },
  );

  testWidgets(
    'original LowProfileListener posts its real delayed runnable once',
    (tester) async {
      registerClass90(vm);
      registerClass91(vm);
      registerClass93(vm);
      registerClass94(vm);
      const activity = 'Landroid/app/Activity;',
          window = 'Landroid/view/Window;',
          view = 'Landroid/view/View;',
          config = 'Lc/c/a/b/d;',
          version = 'Landroid/os/Build\$VERSION;';
      for (final type in [activity, window, view, config, version]) {
        vm.registerExternalClass(type);
      }
      vm.classes[config]!.staticFields['$config->H:Z'] = 0;
      vm.classes[version]!.staticFields['$version->SDK_INT:I'] = 22;
      final w = DalvikObject(window), v = DalvikObject(view), flags = <int>[];
      Object? listener;
      vm.registerNative(
        '$activity->getWindow()Landroid/view/Window;',
        (_, a) => w,
      );
      vm.registerNative(
        '$window->getDecorView()Landroid/view/View;',
        (_, a) => v,
      );
      vm.registerNative('$view->setSystemUiVisibility(I)V', (_, a) {
        flags.add(a[1] as int);
        return null;
      });
      vm.registerNative(
        '$view->setOnSystemUiVisibilityChangeListener(Landroid/view/View\$OnSystemUiVisibilityChangeListener;)V',
        (_, a) {
          listener = a[1];
          return null;
        },
      );
      final r = make('Lc/c/a/b/h\$a;', '(Landroid/app/Activity;)V', [
        DalvikObject(activity),
      ]);
      final started = scheduler.runMain(() => call(r, 'run()V'));
      await tester.pump(Duration.zero);
      await started;
      expect(flags, [5894]);
      expect(listener, isA<DalvikObject>());
      expect(env.pendingCount, 1);
      await advance(tester, 2999);
      expect(flags, [5894]);
      await advance(tester, 1);
      expect(flags, [5894, 5894]);
      expect(env.pendingCount, 0);
      expect(failures, isEmpty);
    },
  );

  testWidgets('uncaught callback failure is surfaced and stops queued work', (
    tester,
  ) async {
    final a = make(handlerClass);
    var later = false;
    call(a, 'post(Ljava/lang/Runnable;)Z', [
      runnable(() => throw StateError('failed callback')),
    ]);
    call(a, 'post(Ljava/lang/Runnable;)Z', [
      runnable(() {
        later = true;
        return null;
      }),
    ]);
    await tester.pump(Duration.zero);
    expect(failures.single, isA<StateError>());
    expect(later, false);
    expect(env.pendingCount, 0);
  });
  testWidgets(
    'main Looper identity is stable and custom loopers fail explicitly',
    (tester) async {
      const looper = 'Landroid/os/Looper;';
      expect(
        vm.call('$looper->myLooper()Landroid/os/Looper;', [], kind: 'static'),
        same(env.mainLooper),
      );
      expect(
        () => vm.call('$looper->prepare()V', [], kind: 'static'),
        throwsA(isA<DalvikThrown>()),
      );
      var reached = false;
      final job = runnable(() {
        expectSync(
          vm.call('$looper->myLooper()Landroid/os/Looper;', [], kind: 'static'),
          isNull,
        );
        expectSync(
          vm.call(
            '$looper->getMainLooper()Landroid/os/Looper;',
            [],
            kind: 'static',
          ),
          same(env.mainLooper),
        );
        expectSync(() => make(handlerClass), throwsA(isA<DalvikThrown>()));
        expectSync(
          () => vm.call('$looper->prepare()V', [], kind: 'static'),
          throwsA(isA<MissingDalvikBridge>()),
        );
        reached = true;
        return null;
      });
      final thread = make('Ljava/lang/Thread;', '(Ljava/lang/Runnable;)V', [
        job,
      ]);
      call(thread, 'start()V');
      await tester.pump(Duration.zero);
      expect(
        scheduler.failures.map((e) => e.error.toString()).toList(),
        isEmpty,
      );
      expect(reached, true);
      expect(failures, isEmpty);
      expect(
        vm.call(
          'Landroid/os/SystemClock;->uptimeMillis()J',
          [],
          kind: 'static',
        ),
        uptime,
      );
    },
  );
}
