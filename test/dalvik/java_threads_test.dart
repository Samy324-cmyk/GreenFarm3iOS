import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_threads.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  late JavaThreadScheduler scheduler;
  var next = 0;
  setUp(() {
    vm = DalvikRuntime()
      ..wallClockMillis = () => DateTime.now().millisecondsSinceEpoch;
    registerJavaCore(vm);
    scheduler = registerJavaThreads(vm);
  });
  Object? call(
    Object? receiver,
    String member, [
    List<Object?> args = const [],
  ]) => vm.call('Ljava/lang/Object;->$member', [
    receiver,
    ...args,
  ], kind: 'virtual');
  Object? staticCall(
    String owner,
    String member, [
    List<Object?> args = const [],
  ]) => vm.call('$owner->$member', args, kind: 'static');
  DalvikObject runnable(Object? Function() action, {bool callable = false}) {
    final name = 'Ltest/Action${next++};';
    vm.registerExternalClass(
      name,
      interfaces: [
        callable ? 'Ljava/util/concurrent/Callable;' : 'Ljava/lang/Runnable;',
      ],
    );
    vm.registerNative(
      '$name->${callable ? 'call()Ljava/lang/Object;' : 'run()V'}',
      (v, a) => action(),
    );
    return vm.allocate(name);
  }

  DalvikObject thread(Object? Function() action) {
    final value = vm.allocate('Ljava/lang/Thread;');
    vm.call('Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V', [
      value,
      runnable(action),
    ], kind: 'direct');
    return value;
  }

  DalvikObject timerTask(Object? Function() action) {
    final name = 'Ltest/Task${next++};';
    vm.registerExternalClass(name, superclass: 'Ljava/util/TimerTask;');
    vm.registerNative('$name->run()V', (v, a) => action());
    final value = vm.allocate(name);
    vm.call('Ljava/util/TimerTask;-><init>()V', [value], kind: 'direct');
    return value;
  }

  Object? sleep(int millis) => staticCall('Ljava/lang/Thread;', 'sleep(J)V', [
    millis.toSigned(32),
    millis >> 32,
  ]);
  Object? locked(Object lock, Object? Function() body) => dalvikThen(() {
    scheduler.monitorEnter(lock);
    return null;
  }, (_) => dalvikFinally(body, () => scheduler.monitorExit(lock)));
  Object? catchJava(
    Object? Function() action,
    Object? Function(DalvikThrown) handler,
  ) {
    try {
      return action();
    } on DalvikPause catch (pause) {
      pause.addFrame(
        DalvikResumeFrame(
          methodKey: 'test catch',
          pc: 0,
          resume: (done) {
            try {
              return done.unwrap();
            } on DalvikThrown catch (error) {
              return handler(error);
            }
          },
        ),
      );
      rethrow;
    } on DalvikThrown catch (error) {
      return handler(error);
    }
  }

  Matcher javaError(String name) => throwsA(
    isA<DalvikThrown>().having((e) => e.object.className, 'type', name),
  );

  test(
    'original thread, timer and executor references all have concrete bridges',
    () {
      final methods = jsonDecode(
        File('test/fixtures/dalvik/threads_api.json').readAsStringSync(),
      ) as List;
      for (final key in methods) {
        expect(
          vm.nativeMethods.containsKey(key),
          isTrue,
          reason: key as String,
        );
      }
    },
  );
  test('start/sleep/join preserve identity and effects without blocking event loop', () async {
    final events = <String>[];
    late DalvikObject worker;
    worker = thread(() {
      expect(scheduler.currentThread, same(worker));
      events.add('before');
      return dalvikThen(() => sleep(1), (_) {
        events.add('after');
        return null;
      });
    });
    final result = scheduler.runMain(() {
      call(worker, 'start()V');
      events.add('started');
      return dalvikThen(() => call(worker, 'join()V'), (_) {
        events.add('joined');
        return 42;
      });
    });
    expect(await result, 42);
    expect(events, ['started', 'before', 'after', 'joined']);
    expect(call(worker, 'isAlive()Z'), 0);
    expect(scheduler.activeCount, 1);
    expect(scheduler.failures, isEmpty);
    expect(
      () => call(worker, 'start()V'),
      javaError('Ljava/lang/IllegalThreadStateException;'),
    );
  });
  test(
    'interrupt wakes real sleep and clears status at InterruptedException',
    () async {
      final started = Completer<void>(), events = <String>[];
      final worker = thread(() {
        started.complete();
        return catchJava(() => sleep(60000), (error) {
          expect(error.object.className, 'Ljava/lang/InterruptedException;');
          events.add('interrupted');
          expect(staticCall('Ljava/lang/Thread;', 'interrupted()Z'), 0);
          return null;
        });
      });
      call(worker, 'start()V');
      await started.future;
      call(worker, 'interrupt()V');
      await scheduler.runMain(() => call(worker, 'join()V'));
      expect(events, ['interrupted']);
      expect(scheduler.failures, isEmpty);
    },
  );
  test(
    'sleep retains monitor; contended enter resumes only after terminal exit',
    () async {
      final lock = vm.allocate('Ljava/lang/Object;'),
          entered = Completer<void>(),
          release = Completer<Object?>(),
          events = <String>[];
      final first = thread(
        () => locked(lock, () {
          entered.complete();
          events.add('owner');
          return dalvikThen(() => throw DalvikPause(release.future), (_) {
            events.add('owner-end');
            return null;
          });
        }),
      );
      final second = thread(
        () => locked(lock, () {
          events.add('contender');
          return null;
        }),
      );
      call(first, 'start()V');
      await entered.future;
      call(second, 'start()V');
      await Future<void>.delayed(Duration.zero);
      expect(events, ['owner']);
      release.complete(null);
      await scheduler.runMain(
        () => dalvikThen(
          () => call(first, 'join()V'),
          (_) => call(second, 'join()V'),
        ),
      );
      expect(events, ['owner', 'owner-end', 'contender']);
      expect(scheduler.failures, isEmpty);
    },
  );
  test('wait releases all recursion depth, notify retains ownership, reacquire restores depth', () async {
    final lock = vm.allocate('Ljava/lang/Object;'),
        waiting = Completer<void>(),
        events = <String>[];
    final waiter = thread(
      () => locked(
        lock,
        () => locked(lock, () {
          waiting.complete();
          events.add('wait');
          return dalvikThen(() => call(lock, 'wait()V'), (_) {
            expect(scheduler.holdsMonitor(lock), isTrue);
            events.add('resumed');
            return null;
          });
        }),
      ),
    );
    final notifier = thread(
      () => locked(lock, () {
        call(lock, 'notify()V');
        events.add('notified-held');
        return dalvikThen(() => sleep(1), (_) {
          events.add('release');
          return null;
        });
      }),
    );
    call(waiter, 'start()V');
    await waiting.future;
    call(notifier, 'start()V');
    await scheduler.runMain(
      () => dalvikThen(
        () => call(waiter, 'join()V'),
        (_) => call(notifier, 'join()V'),
      ),
    );
    expect(events, ['wait', 'notified-held', 'release', 'resumed']);
    expect(scheduler.holdsMonitor(lock), isFalse);
    expect(scheduler.failures, isEmpty);
  });
  test(
    'interrupted wait reacquires monitor before exception is delivered',
    () async {
      final lock = vm.allocate('Ljava/lang/Object;'),
          waiting = Completer<void>(),
          held = Completer<void>(),
          release = Completer<Object?>(),
          events = <String>[];
      final waiter = thread(
        () => locked(lock, () {
          waiting.complete();
          return catchJava(() => call(lock, 'wait()V'), (error) {
            expect(scheduler.holdsMonitor(lock), isTrue);
            events.add(error.object.className);
            return null;
          });
        }),
      );
      final holder = thread(
        () => locked(lock, () {
          held.complete();
          return throw DalvikPause(release.future);
        }),
      );
      call(waiter, 'start()V');
      await waiting.future;
      call(holder, 'start()V');
      await held.future;
      call(waiter, 'interrupt()V');
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      release.complete(null);
      await scheduler.runMain(
        () => dalvikThen(
          () => call(waiter, 'join()V'),
          (_) => call(holder, 'join()V'),
        ),
      );
      expect(events, ['Ljava/lang/InterruptedException;']);
      expect(scheduler.failures, isEmpty);
    },
  );
  test('wait timeout is real and invalid monitor operations throw', () async {
    final lock = vm.allocate('Ljava/lang/Object;');
    expect(
      () => call(lock, 'notifyAll()V'),
      javaError('Ljava/lang/IllegalMonitorStateException;'),
    );
    expect(
      () => call(lock, 'wait()V'),
      javaError('Ljava/lang/IllegalMonitorStateException;'),
    );
    await scheduler.runMain(
      () => locked(lock, () => call(lock, 'wait(J)V', [1, 0])),
    );
    expect(() => sleep(-1), javaError('Ljava/lang/IllegalArgumentException;'));
  });
  test('Timer runs tasks serially across pauses and cancel rejects later scheduling', () async {
    final timer = vm.allocate('Ljava/util/Timer;');
    vm.call('Ljava/util/Timer;-><init>()V', [timer], kind: 'direct');
    final events = <String>[], finished = Completer<void>();
    final first = timerTask(() {
      events.add('first');
      return dalvikThen(() => sleep(1), (_) {
        events.add('first-end');
        return null;
      });
    });
    final second = timerTask(() {
      events.add('second');
      finished.complete();
      return null;
    });
    call(timer, 'schedule(Ljava/util/TimerTask;J)V', [first, 0, 0]);
    call(timer, 'schedule(Ljava/util/TimerTask;J)V', [second, 0, 0]);
    expect(
      () => call(timer, 'schedule(Ljava/util/TimerTask;J)V', [first, 0, 0]),
      javaError('Ljava/lang/IllegalStateException;'),
    );
    await finished.future;
    call(timer, 'cancel()V');
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first', 'first-end', 'second']);
    expect(scheduler.activeCount, 1);
    expect(
      () => call(timer, 'schedule(Ljava/util/TimerTask;J)V', [
        timerTask(() => null),
        0,
        0,
      ]),
      javaError('Ljava/lang/IllegalStateException;'),
    );
  });
  test(
    'single executor queues tasks and shutdown drains accepted work',
    () async {
      final service = staticCall(
            'Ljava/util/concurrent/Executors;',
            'newSingleThreadExecutor()Ljava/util/concurrent/ExecutorService;',
          ),
          gate = Completer<Object?>(),
          events = <String>[];
      DalvikObject? identity;
      final first = runnable(() {
        identity = scheduler.currentThread;
        events.add('first');
        return dalvikThen(() => throw DalvikPause(gate.future), (_) {
          events.add('first-end');
          return null;
        });
      });
      final second = runnable(() {
        expect(scheduler.currentThread, same(identity));
        events.add('second');
        return vm.newString('done');
      }, callable: true);
      call(
        service,
        'submit(Ljava/lang/Runnable;)Ljava/util/concurrent/Future;',
        [first],
      );
      final future = call(
        service,
        'submit(Ljava/util/concurrent/Callable;)Ljava/util/concurrent/Future;',
        [second],
      );
      call(service, 'shutdown()V');
      expect(
        () => call(
          service,
          'submit(Ljava/lang/Runnable;)Ljava/util/concurrent/Future;',
          [first],
        ),
        javaError('Ljava/util/concurrent/RejectedExecutionException;'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['first']);
      gate.complete(null);
      expect(
        vm.string(
          await scheduler.runMain(
            () => call(future, 'get()Ljava/lang/Object;'),
          ),
        ),
        'done',
      );
      expect(events, ['first', 'first-end', 'second']);
      expect(call(future, 'isDone()Z'), 1);
      expect(scheduler.failures, isEmpty);
    },
  );
  test(
    'uncaught background integration errors remain visible to host',
    () async {
      final worker = thread(
        () => throw MissingDalvikBridge('visible test failure'),
      );
      call(worker, 'start()V');
      await scheduler.runMain(() => call(worker, 'join()V'));
      expect(scheduler.failures.single.error, isA<MissingDalvikBridge>());
      expect(vm.diagnostics.single, contains('visible test failure'));
    },
  );
}
