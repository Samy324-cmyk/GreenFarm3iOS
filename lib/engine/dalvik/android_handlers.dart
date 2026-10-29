import 'dart:async';

import 'cooperative.dart';
import 'java_threads.dart';
import 'numbers.dart';
import 'runtime.dart';

const _handler = 'Landroid/os/Handler;';
const _looper = 'Landroid/os/Looper;';
const _message = 'Landroid/os/Message;';

class _Handler {
  _Handler(this.callback);
  final Object? callback;
}

class _Message {
  Object? target, callback;
  int when = 0;
  bool inUse = false;
}

class _Queued {
  _Queued(this.handler, this.message, this.state);
  final DalvikObject handler, message;
  final _Message state;
  bool running = false, cancelled = false;
}

/// The Android main Looper's queue, backed by actual Dart timers and the same
/// Java main-thread worker used by Activity callbacks. Time is uptime (which
/// excludes device sleep), not Android elapsedRealtime or the wall clock.
class AndroidHandlerEnvironment {
  AndroidHandlerEnvironment({
    required this.vm,
    required this.scheduler,
    required this.uptimeMillis,
    this.onError,
  }) : mainThread = scheduler.currentThread;
  final DalvikRuntime vm;
  final JavaThreadScheduler scheduler;
  final int Function() uptimeMillis;
  final void Function(Object error, StackTrace stack)? onError;
  final DalvikObject mainThread;
  final DalvikObject mainLooper = DalvikObject(_looper);
  final List<_Queued> _queue = [];
  Timer? _timer;
  _Queued? _selected;
  bool _draining = false, _disposed = false;
  int get pendingCount => _queue.length + (_selected == null ? 0 : 1);

  int enqueue(DalvikObject handler, DalvikObject message, int when) {
    final state = message.nativeValue as _Message;
    if (state.inUse) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'This message is already in use',
      );
    }
    state.target = handler;
    state.when = when;
    state.inUse = true;
    if (_disposed) {
      _recycle(message);
      return 0;
    }
    final entry = _Queued(handler, message, state);
    // MessageQueue treats when==0 as insertion at the front; otherwise equal
    // timestamps retain enqueue order across every Handler on this Looper.
    var index = 0;
    if (when != 0) {
      while (index < _queue.length &&
          (_queue[index].state.when == 0 || _queue[index].state.when <= when)) {
        index++;
      }
    }
    _queue.insert(index, entry);
    _arm();
    return 1;
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || _draining || _queue.isEmpty) return;
    final delay = _queue.first.state.when - uptimeMillis();
    _timer = Timer(Duration(milliseconds: delay > 0 ? delay : 0), _pump);
  }

  Future<void> _pump() async {
    _timer = null;
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (!_disposed &&
          _queue.isNotEmpty &&
          _queue.first.state.when <= uptimeMillis()) {
        final entry = _queue.removeAt(0);
        _selected = entry;
        try {
          await scheduler.runMain(() {
            if (entry.cancelled || _disposed) return null;
            entry.running = true;
            return vm.call(
              '$_handler->dispatchMessage(Landroid/os/Message;)V',
              [entry.handler, entry.message],
              kind: 'virtual',
            );
          });
        } finally {
          _recycle(entry.message);
          _selected = null;
        }
      }
    } catch (error, stack) {
      dispose();
      vm.logDiagnostic('Uncaught main Looper callback: $error');
      if (onError != null) {
        onError!(error, stack);
      } else {
        Zone.current.handleUncaughtError(error, stack);
      }
    } finally {
      _draining = false;
      _arm();
    }
  }

  Iterable<_Queued> get _pending sync* {
    yield* _queue;
    final selected = _selected;
    if (selected != null && !selected.running && !selected.cancelled) {
      yield selected;
    }
  }

  bool _has(DalvikObject handler, bool Function(_Queued) predicate) => _pending
      .any((entry) => identical(entry.handler, handler) && predicate(entry));
  void _remove(DalvikObject handler, bool Function(_Queued) predicate) {
    for (final entry in _pending.toList()) {
      if (identical(entry.handler, handler) && predicate(entry)) {
        entry.cancelled = true;
        if (_queue.remove(entry)) _recycle(entry.message);
      }
    }
    _arm();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final entry in _queue) {
      entry.cancelled = true;
      _recycle(entry.message);
    }
    _queue.clear();
    if (_selected != null && !_selected!.running) _selected!.cancelled = true;
  }
}

void _recycle(DalvikObject object) {
  final state = object.nativeValue as _Message;
  state.inUse = true;
  state.target = null;
  state.callback = null;
  state.when = 0;
  for (final name in ['what', 'arg1', 'arg2']) {
    object.fields['$_message->$name:I'] = 0;
  }
  object.fields['$_message->obj:Ljava/lang/Object;'] = null;
}

/// Host callbacks that supply Android Messages use this real queue object.
DalvikObject androidMessage(
  DalvikRuntime vm, {
  Object? target,
  Object? callback,
  int what = 0,
  int arg1 = 0,
  int arg2 = 0,
  Object? object,
}) {
  final result = vm.allocate(_message);
  result.nativeValue = _Message()
    ..target = target
    ..callback = callback;
  result.fields.addAll({
    '$_message->what:I': what,
    '$_message->arg1:I': arg1,
    '$_message->arg2:I': arg2,
    '$_message->obj:Ljava/lang/Object;': object,
  });
  return result;
}

void registerAndroidHandlers(
  DalvikRuntime vm, {
  required AndroidHandlerEnvironment environment,
}) {
  final env = environment;
  vm.registerExternalClass('Landroid/os/SystemClock;');
  for (final type in [
    _handler,
    _looper,
    _message,
    'Landroid/os/Handler\$Callback;',
  ]) {
    vm.registerExternalClass(type);
  }
  vm.classes[_message]!.instanceFields.addAll({
    '$_message->what:I': 'I',
    '$_message->arg1:I': 'I',
    '$_message->arg2:I': 'I',
    '$_message->obj:Ljava/lang/Object;': 'Ljava/lang/Object;',
  });
  _Handler handler(Object? value) => vm.object(value).nativeValue as _Handler;
  _Message message(Object? value) => vm.object(value).nativeValue as _Message;
  Object? looperForCurrentThread() =>
      identical(env.scheduler.currentThread, env.mainThread)
      ? env.mainLooper
      : null;
  void requireLooper(Object? value) {
    if (vm.isNull(value)) {
      vm.throwJava(
        'Ljava/lang/RuntimeException;',
        "Can't create Handler inside thread that has not called Looper.prepare()",
      );
    }
    if (!identical(value, env.mainLooper)) {
      throw MissingDalvikBridge('Handler on a custom Java Looper thread');
    }
  }

  int delayed(Object? h, DalvikObject m, int delay) => env.enqueue(
    vm.object(h),
    m,
    env.uptimeMillis() + (delay < 0 ? 0 : delay),
  );
  DalvikObject postMessage(Object? runnable, [Object? token]) {
    vm.object(runnable);
    return androidMessage(vm, callback: runnable, object: token);
  }

  vm.registerNative(
    'Landroid/os/SystemClock;->uptimeMillis()J',
    (_, a) => env.uptimeMillis(),
  );
  vm.registerNative(
    '$_looper->getMainLooper()Landroid/os/Looper;',
    (_, a) => env.mainLooper,
  );
  vm.registerNative(
    '$_looper->myLooper()Landroid/os/Looper;',
    (_, a) => looperForCurrentThread(),
  );
  vm.registerNative('$_looper->getThread()Ljava/lang/Thread;', (_, a) {
    requireLooper(a[0]);
    return env.mainThread;
  });
  vm.registerNative('$_looper->prepare()V', (_, a) {
    if (looperForCurrentThread() != null) {
      vm.throwJava(
        'Ljava/lang/RuntimeException;',
        'Only one Looper may be created per thread',
      );
    }
    throw MissingDalvikBridge('Looper.prepare on a custom Java thread');
  });
  vm.registerNative(
    '$_looper->loop()V',
    (_, a) => throw MissingDalvikBridge(
      'Nested/custom Looper.loop; Flutter hosts the original main Looper',
    ),
  );
  for (final method in ['quit()V', 'quitSafely()V']) {
    vm.registerNative('$_looper->$method', (_, a) {
      requireLooper(a[0]);
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'Main thread not allowed to quit',
      );
    });
  }
  for (final signature in [
    '()V',
    '(Landroid/os/Looper;)V',
    '(Landroid/os/Handler\$Callback;)V',
    '(Landroid/os/Looper;Landroid/os/Handler\$Callback;)V',
  ]) {
    vm.registerNative('$_handler-><init>$signature', (_, a) {
      final explicit = signature.contains('Looper;');
      requireLooper(explicit ? a[1] : looperForCurrentThread());
      vm.object(a[0]).nativeValue = _Handler(
        signature.contains('Callback;') ? a[explicit ? 2 : 1] : null,
      );
      return null;
    });
  }
  vm.registerNative('$_handler->getLooper()Landroid/os/Looper;', (_, a) {
    handler(a[0]);
    return env.mainLooper;
  });
  vm.registerNative(
    '$_handler->handleMessage(Landroid/os/Message;)V',
    (_, a) => null,
  ); // Android base hook is empty.
  vm.registerNative('$_handler->dispatchMessage(Landroid/os/Message;)V', (
    _,
    a,
  ) {
    final m = message(a[1]), h = handler(a[0]);
    if (!vm.isNull(m.callback)) {
      return vm.call('Ljava/lang/Runnable;->run()V', [
        m.callback,
      ], kind: 'interface');
    }
    Object? fallback() => vm.call(
      '$_handler->handleMessage(Landroid/os/Message;)V',
      a,
      kind: 'virtual',
    );
    if (vm.isNull(h.callback)) return fallback();
    return dalvikThen(
      () => vm.call(
        'Landroid/os/Handler\$Callback;->handleMessage(Landroid/os/Message;)Z',
        [h.callback, a[1]],
        kind: 'interface',
      ),
      (handled) => handled == 0 ? fallback() : null,
      methodKey: '$_handler->dispatchMessage(Landroid/os/Message;)V',
    );
  });
  vm.registerNative(
    '$_handler->post(Ljava/lang/Runnable;)Z',
    (_, a) => delayed(a[0], postMessage(a[1]), 0),
  );
  vm.registerNative(
    '$_handler->postDelayed(Ljava/lang/Runnable;J)Z',
    (_, a) => delayed(a[0], postMessage(a[1]), JBits.wide(a, 2)),
  );
  vm.registerNative(
    '$_handler->postAtTime(Ljava/lang/Runnable;J)Z',
    (_, a) => env.enqueue(vm.object(a[0]), postMessage(a[1]), JBits.wide(a, 2)),
  );
  vm.registerNative(
    '$_handler->postAtTime(Ljava/lang/Runnable;Ljava/lang/Object;J)Z',
    (_, a) =>
        env.enqueue(vm.object(a[0]), postMessage(a[1], a[2]), JBits.wide(a, 3)),
  );
  vm.registerNative(
    '$_handler->postAtFrontOfQueue(Ljava/lang/Runnable;)Z',
    (_, a) => env.enqueue(vm.object(a[0]), postMessage(a[1]), 0),
  );
  for (final token in [false, true]) {
    vm.registerNative(
      '$_handler->removeCallbacks(Ljava/lang/Runnable;${token ? 'Ljava/lang/Object;' : ''})V',
      (_, a) {
        if (vm.isNull(a[1])) return null;
        env._remove(
          vm.object(a[0]),
          (e) =>
              identical(e.state.callback, a[1]) &&
              (!token ||
                  vm.isNull(a[2]) ||
                  identical(
                    e.message.fields['$_message->obj:Ljava/lang/Object;'],
                    a[2],
                  )),
        );
        return null;
      },
    );
  }
  vm.registerNative(
    '$_handler->hasCallbacks(Ljava/lang/Runnable;)Z',
    (_, a) =>
        !vm.isNull(a[1]) &&
            env._has(vm.object(a[0]), (e) => identical(e.state.callback, a[1]))
        ? 1
        : 0,
  );
  vm.registerNative(
    '$_handler->removeCallbacksAndMessages(Ljava/lang/Object;)V',
    (_, a) {
      env._remove(
        vm.object(a[0]),
        (e) =>
            vm.isNull(a[1]) ||
            identical(
              e.message.fields['$_message->obj:Ljava/lang/Object;'],
              a[1],
            ),
      );
      return null;
    },
  );
  for (final token in [false, true]) {
    bool matches(_Queued e, List<Object?> a) =>
        e.message.fields['$_message->what:I'] == a[1] &&
        (!token ||
            vm.isNull(a[2]) ||
            identical(
              e.message.fields['$_message->obj:Ljava/lang/Object;'],
              a[2],
            ));
    vm.registerNative(
      '$_handler->hasMessages(I${token ? 'Ljava/lang/Object;' : ''})Z',
      (_, a) => env._has(vm.object(a[0]), (e) => matches(e, a)) ? 1 : 0,
    );
    vm.registerNative(
      '$_handler->removeMessages(I${token ? 'Ljava/lang/Object;' : ''})V',
      (_, a) {
        env._remove(vm.object(a[0]), (e) => matches(e, a));
        return null;
      },
    );
  }
  vm.registerNative(
    '$_handler->sendMessage(Landroid/os/Message;)Z',
    (_, a) => delayed(a[0], vm.object(a[1]), 0),
  );
  vm.registerNative(
    '$_handler->sendMessageDelayed(Landroid/os/Message;J)Z',
    (_, a) => delayed(a[0], vm.object(a[1]), JBits.wide(a, 2)),
  );
  vm.registerNative(
    '$_handler->sendMessageAtTime(Landroid/os/Message;J)Z',
    (_, a) => env.enqueue(vm.object(a[0]), vm.object(a[1]), JBits.wide(a, 2)),
  );
  vm.registerNative(
    '$_handler->sendMessageAtFrontOfQueue(Landroid/os/Message;)Z',
    (_, a) => env.enqueue(vm.object(a[0]), vm.object(a[1]), 0),
  );
  vm.registerNative(
    '$_handler->sendEmptyMessage(I)Z',
    (_, a) => delayed(a[0], androidMessage(vm, what: a[1] as int), 0),
  );
  vm.registerNative(
    '$_handler->sendEmptyMessageDelayed(IJ)Z',
    (_, a) =>
        delayed(a[0], androidMessage(vm, what: a[1] as int), JBits.wide(a, 2)),
  );

  vm.registerNative('$_message-><init>()V', (_, a) {
    vm.object(a[0]).nativeValue = _Message();
    return null;
  });
  vm.registerNative(
    '$_message->obtain()Landroid/os/Message;',
    (_, a) => androidMessage(vm),
  );
  for (final signature in [
    '',
    'I',
    'ILjava/lang/Object;',
    'III',
    'IIILjava/lang/Object;',
  ]) {
    DalvikObject obtain(List<Object?> a) => androidMessage(
      vm,
      target: a[0],
      what: signature.isEmpty ? 0 : a[1] as int,
      arg1: signature.startsWith('III') ? a[2] as int : 0,
      arg2: signature.startsWith('III') ? a[3] as int : 0,
      object: signature.contains('Object;') ? a.last : null,
    );
    vm.registerNative(
      '$_message->obtain(Landroid/os/Handler;$signature)Landroid/os/Message;',
      (_, a) => obtain(a),
    );
    vm.registerNative(
      '$_handler->obtainMessage($signature)Landroid/os/Message;',
      (_, a) => obtain(a),
    );
  }
  vm.registerNative(
    '$_message->obtain(Landroid/os/Handler;Ljava/lang/Runnable;)Landroid/os/Message;',
    (_, a) => androidMessage(vm, target: a[0], callback: a[1]),
  );
  vm.registerNative(
    '$_message->getTarget()Landroid/os/Handler;',
    (_, a) => message(a[0]).target,
  );
  vm.registerNative('$_message->setTarget(Landroid/os/Handler;)V', (_, a) {
    message(a[0]).target = a[1];
    return null;
  });
  vm.registerNative(
    '$_message->getCallback()Ljava/lang/Runnable;',
    (_, a) => message(a[0]).callback,
  );
  vm.registerNative('$_message->getWhen()J', (_, a) => message(a[0]).when);
  vm.registerNative('$_message->sendToTarget()V', (_, a) {
    final target = vm.object(message(a[0]).target);
    delayed(target, vm.object(a[0]), 0);
    return null;
  });
  vm.registerNative('$_message->recycle()V', (_, a) {
    if (message(a[0]).inUse) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'This message cannot be recycled because it is still in use',
      );
    }
    _recycle(vm.object(a[0]));
    return null;
  });
}
