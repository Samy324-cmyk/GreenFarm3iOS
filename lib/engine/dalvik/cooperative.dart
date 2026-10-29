import 'dart:collection';

/// Result of one suspended operation. Failure remains an error until the
/// original instruction unwraps it, so its original catch table can handle it.
class DalvikCompletion {
  const DalvikCompletion.success(this.value) : error = null, stackTrace = null;
  const DalvikCompletion.failure(this.error, this.stackTrace) : value = null;
  final Object? value;
  final Object? error;
  final StackTrace? stackTrace;
  Object? unwrap() {
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, stackTrace ?? StackTrace.current);
    }
    return value;
  }
}

class DalvikResumeFrame {
  DalvikResumeFrame({
    required this.methodKey,
    required this.pc,
    required this.resume,
  });
  final String methodKey;
  final int pc;
  final Object? Function(DalvikCompletion completion) resume;
  bool _consumed = false;
  Object? invoke(DalvikCompletion completion) {
    if (_consumed) {
      throw StateError('Continuation already resumed: $methodKey:$pc');
    }
    _consumed = true;
    return resume(completion);
  }
}

/// Deliberately is not a Java exception. Captured frames are ordered from the
/// suspended inner method to its outer callers during synchronous unwinding.
class DalvikPause extends Error {
  DalvikPause(this.pending);
  final Future<Object?> pending;
  final List<DalvikResumeFrame> _frames = [];
  bool _consumed = false;
  List<DalvikResumeFrame> get frames => List.unmodifiable(_frames);
  void addFrame(DalvikResumeFrame frame) {
    if (_consumed) throw StateError('Cannot capture an already consumed pause');
    _frames.add(frame);
  }

  List<DalvikResumeFrame> _takeFrames() {
    if (_consumed) throw StateError('Pause already consumed');
    _consumed = true;
    return _frames;
  }

  @override
  String toString() =>
      'Dalvik execution suspended (${_frames.length} captured frames)';
}

/// Executes each native future and each captured continuation exactly once.
/// A continuation that pauses again supplies new inner frames; untouched outer
/// frames wait behind them. No generated method must become async.
class DalvikExecutor {
  Future<Object?> run(Object? Function() entry) async {
    final remaining = Queue<DalvikResumeFrame>();
    Object step = _capture(entry);
    while (true) {
      if (step is DalvikPause) {
        final frames = step._takeFrames();
        for (final frame in frames.reversed) {
          remaining.addFirst(frame);
        }
        try {
          step = DalvikCompletion.success(await step.pending);
        } catch (error, stack) {
          step = DalvikCompletion.failure(error, stack);
        }
      }
      final completion = step as DalvikCompletion;
      if (remaining.isEmpty) return completion.unwrap();
      final frame = remaining.removeFirst();
      step = _capture(() => frame.invoke(completion));
    }
  }

  Object _capture(Object? Function() action) {
    try {
      return DalvikCompletion.success(action());
    } on DalvikPause catch (pause) {
      return pause;
    } catch (error, stack) {
      return DalvikCompletion.failure(error, stack);
    }
  }
}

/// Only catches suspension from [first]. If [then] can itself suspend and has
/// work after that operation, it must capture its own continuation as usual.
Object? dalvikThen(
  Object? Function() first,
  Object? Function(Object? value) then, {
  String methodKey = '<runtime>',
  int pc = -1,
}) {
  Object? value;
  try {
    value = first();
  } on DalvikPause catch (pause) {
    pause.addFrame(
      DalvikResumeFrame(
        methodKey: methodKey,
        pc: pc,
        resume: (completion) => then(completion.unwrap()),
      ),
    );
    rethrow;
  }
  return then(value);
}

/// A synchronized method's monitor cleanup belongs here: it runs after real
/// completion or failure, including after any number of intermediate pauses.
Object? dalvikFinally(
  Object? Function() action,
  void Function() cleanup, {
  String methodKey = '<runtime cleanup>',
  int pc = -1,
}) {
  var paused = false;
  try {
    return action();
  } on DalvikPause catch (pause) {
    paused = true;
    pause.addFrame(
      DalvikResumeFrame(
        methodKey: methodKey,
        pc: pc,
        resume: (completion) {
          try {
            return completion.unwrap();
          } finally {
            cleanup();
          }
        },
      ),
    );
    rethrow;
  } finally {
    if (!paused) cleanup();
  }
}
