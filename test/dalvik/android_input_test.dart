import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/compat/java_numbers.dart';
import 'package:green_farm_port/engine/dalvik/android_input.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  test('multi-touch preserves pointer indexes and reuses released IDs', () {
    final mapper = AndroidPointerMapper();
    AndroidMotionState send(PointerEvent event) =>
        mapper.mapEvent(event, scaleX: 2, scaleY: 3)!;
    final first = send(
      const PointerDownEvent(
        pointer: 81,
        position: Offset(1, 2),
        timeStamp: Duration(milliseconds: 50),
      ),
    );
    expect(first.action, 0);
    expect(first.pointers.single.id, 0);
    expect((first.pointers.single.x, first.pointers.single.y), (2, 6));
    final second = send(
      const PointerDownEvent(pointer: 99, position: Offset(4, 5)),
    );
    expect(second.action, 5 | 256);
    expect(second.pointers.map((p) => p.id), [0, 1]);
    final release = send(
      const PointerUpEvent(pointer: 81, position: Offset(7, 8)),
    );
    expect(release.action, 6);
    expect(release.pointers.length, 2);
    expect(mapper.activeCount, 1);
    final third = send(
      const PointerDownEvent(pointer: 123, position: Offset(9, 10)),
    );
    expect(third.actionIndex, 1);
    expect(third.pointers.map((p) => p.id), [1, 0]);
    expect(third.downTimeMillis, 50);
    final move = send(
      const PointerMoveEvent(pointer: 99, position: Offset(11, 12)),
    );
    expect(move.action, 2);
    expect(move.pointers.first.x, 22);
    expect(
      second.pointers.first.x,
      2,
      reason: 'earlier event snapshots remain unchanged',
    );
  });

  test('cancel clears the gesture and ignores orphan events', () {
    final mapper = AndroidPointerMapper();
    AndroidMotionState? send(PointerEvent event) =>
        mapper.mapEvent(event, scaleX: 1, scaleY: 1);
    send(const PointerDownEvent(pointer: 1));
    send(const PointerDownEvent(pointer: 2));
    final cancel = send(const PointerCancelEvent(pointer: 2))!;
    expect(cancel.action, 3);
    expect(cancel.pointers.length, 2);
    expect(mapper.activeCount, 0);
    expect(send(const PointerMoveEvent(pointer: 1)), isNull);
    expect(send(const PointerHoverEvent(pointer: 3)), isNull);
    expect(send(const PointerDownEvent(pointer: 4))!.pointers.single.id, 0);
  });

  test(
    'native motion bridge preserves float registers and wide timestamps',
    () {
      final vm = DalvikRuntime();
      registerJavaCore(vm);
      registerAndroidInput(vm);
      final object = vm.call(
        'Landroid/view/MotionEvent;->obtain(JJIFFI)Landroid/view/MotionEvent;',
        [
          2,
          1,
          3,
          1,
          0,
          JavaNumbers.floatBits(2.75),
          JavaNumbers.floatBits(-1.25),
          7,
        ],
        kind: 'static',
      );
      final state = vm.object(object).nativeValue as AndroidMotionState;
      expect(state.downTimeMillis, 0x100000002);
      expect(state.eventTimeMillis, 0x100000003);
      expect(state.metaState, 7);
      expect(
        vm.call('Landroid/view/MotionEvent;->getX()F', [
          object,
        ], kind: 'virtual'),
        JavaNumbers.floatBits(2.75),
      );
      expect(
        vm.call('Landroid/view/MotionEvent;->getAxisValue(I)F', [
          object,
          1,
        ], kind: 'virtual'),
        JavaNumbers.floatBits(-1.25),
      );
      expect(
        () => vm.call('Landroid/view/MotionEvent;->getPointerId(I)I', [
          object,
          1,
        ], kind: 'virtual'),
        throwsA(
          isA<DalvikThrown>().having(
            (e) => e.object.className,
            'type',
            'Ljava/lang/IllegalArgumentException;',
          ),
        ),
      );
    },
  );

  test('key repeat and tracking follow event action', () {
    final vm = DalvikRuntime();
    registerJavaCore(vm);
    registerAndroidInput(vm);
    final down = AndroidKeyState(action: 0, keyCode: 4, repeatCount: 3);
    expect(
      vm.call('Landroid/view/KeyEvent;->getRepeatCount()I', [
        down.asObject(),
      ], kind: 'virtual'),
      3,
    );
    vm.call('Landroid/view/KeyEvent;->startTracking()V', [
      down.asObject(),
    ], kind: 'virtual');
    expect(down.trackingRequested, isTrue);
    final up = AndroidKeyState(action: 1, keyCode: 4);
    expect(
      () => vm.call('Landroid/view/KeyEvent;->startTracking()V', [
        up.asObject(),
      ], kind: 'virtual'),
      throwsA(isA<DalvikThrown>()),
    );
  });
}
