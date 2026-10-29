import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';

void main() {
  test(
    'nested frames preserve registers and invoke native operation only once',
    () async {
      final pending = Completer<Object?>();
      var nativeCalls = 0, before = 0, after = 0;
      Object? inner() {
        final r = <Object?>[40];
        var pc = 0;
        Object? run([DalvikCompletion? completion]) {
          while (true) {
            try {
              switch (pc) {
                case 0:
                  before++;
                  pc = 1;
                case 1:
                  final done = completion;
                  completion = null;
                  if (done != null) {
                    r.add(done.unwrap());
                  } else {
                    nativeCalls++;
                    throw DalvikPause(pending.future);
                  }
                  pc = 2;
                case 2:
                  after++;
                  return (r[0] as int) + (r[1] as int);
                default:
                  throw StateError('bad pc');
              }
            } on DalvikPause catch (pause) {
              pause.addFrame(
                DalvikResumeFrame(
                  methodKey: 'inner',
                  pc: pc,
                  resume: (done) => run(done),
                ),
              );
              rethrow;
            }
          }
        }

        return run();
      }

      final result = DalvikExecutor().run(
        () => dalvikThen(
          inner,
          (value) => (value as int) + 1,
          methodKey: 'outer',
        ),
      );
      expect(before, 1);
      expect(after, 0);
      expect(nativeCalls, 1);
      pending.complete(1);
      expect(await result, 42);
      expect([before, after, nativeCalls], [1, 1, 1]);
    },
  );
  test(
    'a second native pause keeps untouched outer frames and cleanup pending',
    () async {
      final first = Completer<Object?>(), second = Completer<Object?>();
      final events = <String>[];
      Object? work() => dalvikThen(
        () {
          events.add('first');
          throw DalvikPause(first.future);
        },
        (value) {
          events.add('second');
          return dalvikThen(
            () => throw DalvikPause(second.future),
            (other) => (value as int) + (other as int),
          );
        },
      );
      final result = DalvikExecutor().run(
        () => dalvikThen(
          () => dalvikFinally(work, () => events.add('cleanup')),
          (value) {
            events.add('outer');
            return value;
          },
        ),
      );
      first.complete(10);
      await Future<void>.delayed(Duration.zero);
      expect(events, ['first', 'second']);
      second.complete(20);
      expect(await result, 30);
      expect(events, ['first', 'second', 'cleanup', 'outer']);
    },
  );
  test(
    'async failure reaches original continuation catch and terminal cleanup',
    () async {
      final pending = Completer<Object?>();
      final events = <String>[];
      final result = DalvikExecutor().run(
        () => dalvikFinally(() {
          try {
            throw DalvikPause(pending.future);
          } on DalvikPause catch (pause) {
            pause.addFrame(
              DalvikResumeFrame(
                methodKey: 'catcher',
                pc: 7,
                resume: (done) {
                  try {
                    return done.unwrap();
                  } on FormatException {
                    events.add('caught at pc7');
                    return 9;
                  }
                },
              ),
            );
            rethrow;
          }
        }, () => events.add('cleanup')),
      );
      pending.completeError(const FormatException('original error'));
      expect(await result, 9);
      expect(events, ['caught at pc7', 'cleanup']);
    },
  );
  test(
    'unhandled failures preserve identity and cleanup exactly once',
    () async {
      final error = StateError('terminal');
      var cleanups = 0;
      final result = DalvikExecutor().run(
        () => dalvikFinally(
          () => throw DalvikPause(Future<Object?>.error(error)),
          () => cleanups++,
        ),
      );
      await expectLater(result, throwsA(same(error)));
      expect(cleanups, 1);
    },
  );
  test('dalvikThen does not catch and replay a pause from then', () async {
    var calls = 0;
    final result = await DalvikExecutor().run(
      () => dalvikThen(() => 3, (value) {
        calls++;
        throw DalvikPause(Future<Object?>.value(4));
      }),
    );
    expect(result, 4);
    expect(calls, 1);
  });
  test(
    'synchronous fast path stays synchronous until caller requests executor',
    () {
      var cleanup = 0;
      expect(
        dalvikFinally(
          () => dalvikThen(() => 2, (v) => (v as int) * 3),
          () => cleanup++,
        ),
        6,
      );
      expect(cleanup, 1);
    },
  );
}
