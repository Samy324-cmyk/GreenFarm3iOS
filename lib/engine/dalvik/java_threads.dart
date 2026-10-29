import 'dart:async';
import 'dart:collection';

import 'cooperative.dart';
import 'numbers.dart';
import 'runtime.dart';

const _threadClass = 'Ljava/lang/Thread;';
const _executorClass = 'Ljava/util/concurrent/ThreadPoolExecutor;';
const _futureClass = 'Ljava/util/concurrent/FutureTask;';

class JavaThreadFailure {
  JavaThreadFailure(this.thread, this.error, this.stackTrace);
  final DalvikObject thread;
  final Object error;
  final StackTrace stackTrace;
}

class _Thread {
  _Thread(this.object, this.id, this.name, {this.target});
  final DalvikObject object;
  final int id;
  String name;
  Object? target;
  bool started = false, alive = false, interrupted = false;
  void Function()? interruptWait;
  final Completer<void> done = Completer<void>();
}

class _Monitor {
  _Thread? owner;
  int depth = 0;
  final Queue<_MonitorRequest> entrants = Queue();
  final List<_MonitorRequest> waiters = [];
}

class _MonitorRequest {
  _MonitorRequest(this.thread, this.depth);
  final _Thread thread;
  final int depth;
  final Completer<Object?> completion = Completer<Object?>();
  void Function()? cancelTimeout;
  bool waiting = false;
  bool granted = false;
  Object? error;
}

class _Job {
  _Job(this.action, {this.future});
  final Object? Function() action;
  final _FutureResult? future;
  final Completer<DalvikCompletion> completion = Completer<DalvikCompletion>();
}

class _Worker {
  _Worker(this.scheduler, this.thread, {this.stopOnFailure = false});
  final JavaThreadScheduler scheduler;
  final _Thread thread;
  final bool stopOnFailure;
  final Queue<_Job> jobs = Queue();
  bool busy = false, shutdown = false;
  void Function()? onFailure;
  Future<DalvikCompletion> enqueue(_Job job) {
    if (shutdown) {
      scheduler.vm.throwJava(
        'Ljava/util/concurrent/RejectedExecutionException;',
      );
    }
    jobs.add(job);
    if (!busy) {
      busy = true;
      scheduleMicrotask(
        () => runZoned(_drain, zoneValues: {scheduler._zoneKey: thread}),
      );
    }
    return job.completion.future;
  }

  Future<void> _drain() async {
    while (jobs.isNotEmpty) {
      final job = jobs.removeFirst();
      if (job.future?.cancelled ?? false) {
        job.completion.complete(const DalvikCompletion.success(null));
        continue;
      }
      job.future?.runner = thread;
      DalvikCompletion outcome;
      try {
        outcome = DalvikCompletion.success(
          await scheduler.executor.run(job.action),
        );
      } catch (error, stack) {
        outcome = DalvikCompletion.failure(error, stack);
      }
      job.future?.runner = null;
      job.future?.finish(outcome);
      job.completion.complete(outcome);
      if (outcome.error != null &&
          outcome.error is! DalvikThrown &&
          !stopOnFailure) {
        scheduler._recordFailure(thread, outcome.error!, outcome.stackTrace!);
      }
      if (outcome.error != null && stopOnFailure) {
        scheduler._recordFailure(thread, outcome.error!, outcome.stackTrace!);
        onFailure?.call();
        shutdown = true;
        jobs.clear();
        break;
      }
    }
    busy = false;
    if (shutdown) scheduler._terminate(thread);
  }

  void close({bool discard = false}) {
    shutdown = true;
    if (discard) {
      while (jobs.isNotEmpty) {
        final job = jobs.removeFirst();
        job.completion.complete(const DalvikCompletion.success(null));
      }
    }
    if (!busy) scheduler._terminate(thread);
  }
}

class _FutureResult {
  final Completer<DalvikCompletion> completion = Completer<DalvikCompletion>();
  DalvikCompletion? result;
  _Thread? runner;
  bool cancelled = false;
  void finish(DalvikCompletion value) {
    if (result == null) {
      result = value;
      completion.complete(value);
    }
  }
}

class _TimerTask {
  int state = 0;
}

class _JavaTimer {
  _JavaTimer(this.worker);
  final _Worker worker;
  final List<void Function()> cancellations = [];
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    for (final cancel in cancellations) {
      cancel();
    }
    cancellations.clear();
    worker.close(discard: true);
  }
}

/// One Java thread is one Zone plus a resumable synchronous Dalvik stack.
/// Cooperative scheduling does not start host OS threads or block Flutter's
/// event loop. It requires the generated pause frames and VM monitor hooks.
class JavaThreadScheduler {
  JavaThreadScheduler(this.vm) {
    final object = DalvikObject(_threadClass);
    _main = _newThread(object, 'main')
      ..started = true
      ..alive = true;
    _mainWorker = _Worker(this, _main);
  }
  final DalvikRuntime vm;
  final DalvikExecutor executor = DalvikExecutor();
  final Object _zoneKey = Object();
  final List<_Thread> _threads = [];
  final Map<DalvikObject, _Monitor> _monitors = Map.identity();
  final List<JavaThreadFailure> failures = [];
  late final _Thread _main;
  late final _Worker _mainWorker;
  int _nextId = 1;
  int _workerNumber = 0;
  _Thread get _current => Zone.current[_zoneKey] as _Thread? ?? _main;
  DalvikObject get currentThread => _current.object;
  int get activeCount => _threads.where((thread) => thread.alive).length;
  Future<Object?> runMain(Object? Function() entry) async =>
      (await _mainWorker.enqueue(_Job(entry))).unwrap();
  _Thread _newThread(DalvikObject object, String name, {Object? target}) {
    final state = _Thread(object, _nextId++, name, target: target);
    object.nativeValue = state;
    _threads.add(state);
    return state;
  }

  _Thread _state(Object? object) => vm.object(object).nativeValue as _Thread;
  void _recordFailure(_Thread thread, Object error, StackTrace stack) {
    failures.add(JavaThreadFailure(thread.object, error, stack));
    vm.logDiagnostic('Uncaught failure in Java thread ${thread.name}: $error');
  }

  void _terminate(_Thread thread) {
    thread.alive = false;
    thread.interruptWait = null;
    if (!thread.done.isCompleted) thread.done.complete();
  }

  void _start(_Thread thread) {
    if (thread.started) vm.throwJava('Ljava/lang/IllegalThreadStateException;');
    thread.started = true;
    thread.alive = true;
    scheduleMicrotask(
      () => runZoned(() async {
        try {
          await executor.run(
            () => vm.call('$_threadClass->run()V', [
              thread.object,
            ], kind: 'virtual'),
          );
        } catch (error, stack) {
          _recordFailure(thread, error, stack);
        } finally {
          _terminate(thread);
        }
      }, zoneValues: {_zoneKey: thread}),
    );
  }

  DalvikThrown _interrupted() =>
      DalvikThrown(DalvikObject('Ljava/lang/InterruptedException;'));
  void _checkInterrupted() {
    if (_current.interrupted) {
      _current.interrupted = false;
      vm.throwJava('Ljava/lang/InterruptedException;');
    }
  }

  void _interrupt(_Thread thread) {
    if (thread.started && !thread.alive) return;
    thread.interrupted = true;
    thread.interruptWait?.call();
  }

  Never _awaitInterruptibly(Future<Object?> future, {void Function()? cancel}) {
    _checkInterrupted();
    final thread = _current, completion = Completer<Object?>();
    void clear() {
      thread.interruptWait = null;
    }

    thread.interruptWait = () {
      if (!completion.isCompleted) {
        thread.interrupted = false;
        clear();
        cancel?.call();
        completion.completeError(_interrupted());
      }
    };
    future.then(
      (value) {
        if (!completion.isCompleted) {
          clear();
          completion.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completion.isCompleted) {
          clear();
          completion.completeError(error, stack);
        }
      },
    );
    throw DalvikPause(completion.future);
  }

  // Chunk very large Java long delays to avoid Duration's microsecond overflow.
  void Function() _delay(int millis, void Function() callback) {
    var remaining = millis, cancelled = false;
    Timer? timer;
    void next() {
      if (cancelled) return;
      final chunk = remaining > 2147483647 ? 2147483647 : remaining;
      remaining -= chunk;
      timer = Timer(Duration(milliseconds: chunk), () {
        if (remaining > 0) {
          next();
        } else if (!cancelled) {
          callback();
        }
      });
    }

    next();
    return () {
      cancelled = true;
      timer?.cancel();
    };
  }

  Never sleep(int millis) {
    if (millis < 0) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'timeout value is negative',
      );
    }
    _checkInterrupted();
    final completion = Completer<Object?>();
    final cancel = _delay(millis, () => completion.complete(null));
    _awaitInterruptibly(completion.future, cancel: cancel);
  }

  Object? join(Object? value) {
    final target = _state(value);
    if (!target.alive) return null;
    _awaitInterruptibly(target.done.future.then<Object?>((_) => null));
  }

  _Monitor _monitor(Object? object) =>
      _monitors.putIfAbsent(vm.object(object), _Monitor.new);
  bool holdsMonitor(Object? object) =>
      identical(_monitor(object).owner, _current);
  void monitorEnter(Object? object) {
    final monitor = _monitor(object);
    if (monitor.owner == null) {
      monitor.owner = _current;
      monitor.depth = 1;
      return;
    }
    if (identical(monitor.owner, _current)) {
      monitor.depth++;
      return;
    }
    final request = _MonitorRequest(_current, 1);
    monitor.entrants.add(request);
    throw DalvikPause(request.completion.future);
  }

  void monitorExit(Object? object) {
    final monitor = _monitor(object);
    if (!identical(monitor.owner, _current)) {
      vm.throwJava('Ljava/lang/IllegalMonitorStateException;');
    }
    monitor.depth--;
    if (monitor.depth == 0) {
      monitor.owner = null;
      _grant(monitor);
    }
  }

  void _grant(_Monitor monitor) {
    if (monitor.owner != null || monitor.entrants.isEmpty) return;
    final request = monitor.entrants.removeFirst();
    monitor.owner = request.thread;
    monitor.depth = request.depth;
    request.granted = true;
    request.cancelTimeout?.call();
    if (request.waiting) {
      request.thread.interruptWait = null;
    }
    if (request.error != null) {
      request.thread.interrupted = false;
      request.completion.completeError(request.error!);
    } else {
      request.completion.complete(null);
    }
  }

  void _wake(_Monitor monitor, _MonitorRequest request, {Object? error}) {
    if (request.granted) return;
    if (error != null) request.error = error;
    if (monitor.waiters.remove(request)) {
      request.cancelTimeout?.call();
      monitor.entrants.add(request);
      _grant(monitor);
    }
  }

  Never wait(Object? object, int timeout) {
    if (timeout < 0) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'timeout value is negative',
      );
    }
    final monitor = _monitor(object);
    if (!identical(monitor.owner, _current)) {
      vm.throwJava('Ljava/lang/IllegalMonitorStateException;');
    }
    _checkInterrupted();
    final request = _MonitorRequest(_current, monitor.depth)..waiting = true;
    monitor.waiters.add(request);
    _current.interruptWait = () =>
        _wake(monitor, request, error: _interrupted());
    if (timeout > 0) {
      request.cancelTimeout = _delay(timeout, () => _wake(monitor, request));
    }
    monitor.owner = null;
    monitor.depth = 0;
    _grant(monitor);
    throw DalvikPause(request.completion.future);
  }

  void notify(Object? object, {bool all = false}) {
    final monitor = _monitor(object);
    if (!identical(monitor.owner, _current)) {
      vm.throwJava('Ljava/lang/IllegalMonitorStateException;');
    }
    final targets = all
        ? List.of(monitor.waiters)
        : monitor.waiters.take(1).toList();
    for (final request in targets) {
      _wake(monitor, request);
    }
  }

  _Worker _worker(String prefix, {bool stopOnFailure = false}) {
    final thread =
        _newThread(DalvikObject(_threadClass), '$prefix-${++_workerNumber}')
          ..started = true
          ..alive = true;
    return _Worker(this, thread, stopOnFailure: stopOnFailure);
  }
}

JavaThreadScheduler registerJavaThreads(DalvikRuntime vm) {
  vm.registerExternalClass(_threadClass, interfaces: ['Ljava/lang/Runnable;']);
  vm.registerExternalClass(
    'Ljava/lang/IllegalThreadStateException;',
    superclass: 'Ljava/lang/IllegalArgumentException;',
  );
  vm.registerExternalClass('Ljava/util/Timer;');
  vm.registerExternalClass(
    'Ljava/util/TimerTask;',
    interfaces: ['Ljava/lang/Runnable;'],
  );
  for (final name in [
    'Executor',
    'ExecutorService',
    'Executors',
    'Callable',
    'Future',
  ]) {
    vm.registerExternalClass('Ljava/util/concurrent/$name;');
  }
  vm.registerExternalClass(
    _executorClass,
    interfaces: [
      'Ljava/util/concurrent/ExecutorService;',
      'Ljava/util/concurrent/Executor;',
    ],
  );
  vm.registerExternalClass(
    _futureClass,
    interfaces: ['Ljava/util/concurrent/Future;'],
  );
  for (final name in ['RejectedExecutionException', 'CancellationException']) {
    vm.registerExternalClass(
      'Ljava/util/concurrent/$name;',
      superclass: 'Ljava/lang/RuntimeException;',
    );
  }
  vm.registerExternalClass(
    'Ljava/util/concurrent/ExecutionException;',
    superclass: 'Ljava/lang/Exception;',
  );
  final scheduler = JavaThreadScheduler(vm);
  void bind(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  for (final signature in [
    '()V',
    '(Ljava/lang/Runnable;)V',
    '(Ljava/lang/Runnable;Ljava/lang/String;)V',
    '(Ljava/lang/String;)V',
  ]) {
    bind(_threadClass, '<init>$signature', (v, a) {
      final runnable = signature.contains('Runnable')
          ? (v.isNull(a[1]) ? null : v.object(a[1]))
          : null;
      final name = signature.contains('String')
          ? v.string(a.last)
          : 'Thread-${scheduler._threads.length - 1}';
      scheduler._newThread(v.object(a[0]), name, target: runnable);
      return null;
    });
  }
  bind(_threadClass, 'start()V', (v, a) {
    scheduler._start(scheduler._state(a[0]));
    return null;
  });
  bind(_threadClass, 'run()V', (v, a) {
    final target = scheduler._state(a[0]).target;
    return target == null
        ? null
        : v.call('Ljava/lang/Runnable;->run()V', [target], kind: 'interface');
  });
  bind(_threadClass, 'sleep(J)V', (v, a) => scheduler.sleep(JBits.wide(a, 0)));
  bind(
    _threadClass,
    'yield()V',
    (v, a) => throw DalvikPause(Future<Object?>.delayed(Duration.zero)),
  );
  bind(_threadClass, 'join()V', (v, a) => scheduler.join(a[0]));
  bind(_threadClass, 'interrupt()V', (v, a) {
    scheduler._interrupt(scheduler._state(a[0]));
    return null;
  });
  bind(
    _threadClass,
    'isInterrupted()Z',
    (v, a) => scheduler._state(a[0]).interrupted ? 1 : 0,
  );
  bind(_threadClass, 'interrupted()Z', (v, a) {
    final thread = scheduler._current, result = thread.interrupted;
    thread.interrupted = false;
    return result ? 1 : 0;
  });
  bind(
    _threadClass,
    'isAlive()Z',
    (v, a) => scheduler._state(a[0]).alive ? 1 : 0,
  );
  bind(
    _threadClass,
    'currentThread()Ljava/lang/Thread;',
    (v, a) => scheduler.currentThread,
  );
  bind(_threadClass, 'getId()J', (v, a) => scheduler._state(a[0]).id);
  bind(_threadClass, 'setName(Ljava/lang/String;)V', (v, a) {
    scheduler._state(a[0]).name = v.string(a[1]);
    return null;
  });
  bind(
    _threadClass,
    'getName()Ljava/lang/String;',
    (v, a) => v.newString(scheduler._state(a[0]).name),
  );
  bind(_threadClass, 'activeCount()I', (v, a) => scheduler.activeCount);
  bind(
    _threadClass,
    'holdsLock(Ljava/lang/Object;)Z',
    (v, a) => scheduler.holdsMonitor(a[0]) ? 1 : 0,
  );
  bind('Ljava/lang/Object;', 'wait()V', (v, a) => scheduler.wait(a[0], 0));
  bind(
    'Ljava/lang/Object;',
    'wait(J)V',
    (v, a) => scheduler.wait(a[0], JBits.wide(a, 1)),
  );
  bind('Ljava/lang/Object;', 'notify()V', (v, a) {
    scheduler.notify(a[0]);
    return null;
  });
  bind('Ljava/lang/Object;', 'notifyAll()V', (v, a) {
    scheduler.notify(a[0], all: true);
    return null;
  });

  bind('Ljava/util/TimerTask;', '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = _TimerTask();
    return null;
  });
  bind('Ljava/util/TimerTask;', 'cancel()Z', (v, a) {
    final task = v.object(a[0]).nativeValue as _TimerTask;
    final scheduled = task.state == 1;
    task.state = 3;
    return scheduled ? 1 : 0;
  });
  bind('Ljava/util/Timer;', '<init>()V', (v, a) {
    final worker = scheduler._worker('Timer', stopOnFailure: true);
    final actual = _JavaTimer(worker);
    worker.onFailure = actual.cancel;
    v.object(a[0]).nativeValue = actual;
    return null;
  });
  bind('Ljava/util/Timer;', 'cancel()V', (v, a) {
    (v.object(a[0]).nativeValue as _JavaTimer).cancel();
    return null;
  });
  bind('Ljava/util/Timer;', 'schedule(Ljava/util/TimerTask;J)V', (v, a) {
    final timer = v.object(a[0]).nativeValue as _JavaTimer,
        task = v.object(a[1]),
        delay = JBits.wide(a, 2),
        state = task.nativeValue as _TimerTask;
    if (delay < 0) {
      v.throwJava('Ljava/lang/IllegalArgumentException;', 'Negative delay.');
    }
    final clock = v.wallClockMillis;
    if (clock == null) throw MissingDalvikBridge('Timer wall clock');
    if ((clock() + delay).toSigned(64) < 0) {
      v.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Illegal execution time.',
      );
    }
    if (timer.cancelled || timer.worker.shutdown) {
      v.throwJava(
        'Ljava/lang/IllegalStateException;',
        'Timer already cancelled.',
      );
    }
    if (state.state != 0) {
      v.throwJava(
        'Ljava/lang/IllegalStateException;',
        'Task already scheduled or cancelled.',
      );
    }
    state.state = 1;
    timer.cancellations.add(
      scheduler._delay(delay, () {
        if (timer.cancelled || state.state != 1) return;
        timer.worker.enqueue(
          _Job(() {
            if (state.state != 1) return null;
            state.state = 2;
            return v.call('Ljava/util/TimerTask;->run()V', [
              task,
            ], kind: 'virtual');
          }),
        );
      }),
    );
    return null;
  });

  bind(
    'Ljava/util/concurrent/Executors;',
    'newSingleThreadExecutor()Ljava/util/concurrent/ExecutorService;',
    (v, a) =>
        DalvikObject(_executorClass, nativeValue: scheduler._worker('pool')),
  );
  for (final owner in [
    _executorClass,
    'Ljava/util/concurrent/ExecutorService;',
  ]) {
    bind(owner, 'shutdown()V', (v, a) {
      (v.object(a[0]).nativeValue as _Worker).close();
      return null;
    });
    bind(
      owner,
      'isShutdown()Z',
      (v, a) => (v.object(a[0]).nativeValue as _Worker).shutdown ? 1 : 0,
    );
    for (final callable in [false, true]) {
      final type = callable
          ? 'Ljava/util/concurrent/Callable;'
          : 'Ljava/lang/Runnable;';
      bind(owner, 'submit($type)Ljava/util/concurrent/Future;', (v, a) {
        final task = v.object(a[1]),
            worker = v.object(a[0]).nativeValue as _Worker,
            result = _FutureResult();
        worker.enqueue(
          _Job(
            () => v.call(
              '$type->${callable ? 'call()Ljava/lang/Object;' : 'run()V'}',
              [task],
              kind: 'interface',
            ),
            future: result,
          ),
        );
        return DalvikObject(_futureClass, nativeValue: result);
      });
    }
  }
  Object? futureValue(_FutureResult future, DalvikCompletion result) {
    if (future.cancelled) {
      vm.throwJava('Ljava/util/concurrent/CancellationException;');
    }
    if (result.error != null) {
      if (result.error is MissingDalvikBridge) {
        Error.throwWithStackTrace(result.error!, result.stackTrace!);
      }
      vm.throwJava(
        'Ljava/util/concurrent/ExecutionException;',
        result.error.toString(),
      );
    }
    return result.value;
  }

  for (final owner in [_futureClass, 'Ljava/util/concurrent/Future;']) {
    bind(
      owner,
      'isDone()Z',
      (v, a) =>
          (v.object(a[0]).nativeValue as _FutureResult).result != null ? 1 : 0,
    );
    bind(
      owner,
      'isCancelled()Z',
      (v, a) => (v.object(a[0]).nativeValue as _FutureResult).cancelled ? 1 : 0,
    );
    bind(owner, 'get()Ljava/lang/Object;', (v, a) {
      final future = v.object(a[0]).nativeValue as _FutureResult;
      if (future.result != null) return futureValue(future, future.result!);
      scheduler._awaitInterruptibly(
        future.completion.future.then((result) => futureValue(future, result)),
      );
    });
    bind(owner, 'cancel(Z)Z', (v, a) {
      final future = v.object(a[0]).nativeValue as _FutureResult;
      if (future.result != null) return 0;
      future.cancelled = true;
      future.finish(const DalvikCompletion.success(null));
      if (a[1] != 0 && future.runner != null) {
        scheduler._interrupt(future.runner!);
      }
      return 1;
    });
  }
  return scheduler;
}
