import 'package:flutter/gestures.dart';

import '../compat/java_numbers.dart';
import 'numbers.dart';
import 'runtime.dart';

const _motion = 'Landroid/view/MotionEvent;';
const _key = 'Landroid/view/KeyEvent;';

class AndroidPointerData {
  const AndroidPointerData(this.id, this.x, this.y, {this.axes = const {}});
  final int id;
  final double x, y;
  final Map<int, double> axes;
  double axis(int axis) => switch (axis) {
    0 => x,
    1 => y,
    _ => axes[axis] ?? 0,
  };
}

class AndroidMotionState {
  AndroidMotionState({
    required this.action,
    required List<AndroidPointerData> pointers,
    required this.downTimeMillis,
    required this.eventTimeMillis,
    this.metaState = 0,
  }) : pointers = List.unmodifiable(pointers) {
    if (pointers.isEmpty ||
        pointers.length > 32 ||
        pointers.map((p) => p.id).toSet().length != pointers.length ||
        pointers.any((p) => p.id < 0 || p.id > 31) ||
        actionIndex >= pointers.length) {
      throw ArgumentError('Invalid Android motion pointer snapshot');
    }
  }
  final int action, downTimeMillis, eventTimeMillis, metaState;
  final List<AndroidPointerData> pointers;
  int get actionMasked => action & 255;
  int get actionIndex => (action >> 8) & 255;
  DalvikObject asObject() => DalvikObject(_motion, nativeValue: this);
}

class AndroidKeyState {
  AndroidKeyState({
    required this.action,
    required this.keyCode,
    this.repeatCount = 0,
    this.device,
  });
  final int action, keyCode, repeatCount;
  final DalvikObject? device;
  bool trackingRequested = false;
  DalvikObject asObject() => DalvikObject(_key, nativeValue: this);
}

/// Flutter pointer identifiers continually increase. Android uses stable small
/// IDs within a gesture; release snapshots still include the departing pointer.
class AndroidPointerMapper {
  final Map<int, AndroidPointerData> _active = {};
  int _downTime = 0;
  int get activeCount => _active.length;

  AndroidMotionState? mapEvent(
    PointerEvent event, {
    required double scaleX,
    required double scaleY,
  }) {
    final down = event is PointerDownEvent;
    final up = event is PointerUpEvent;
    final cancel = event is PointerCancelEvent;
    if (!down && !up && !cancel && event is! PointerMoveEvent) return null;
    if (scaleX <= 0 || scaleY <= 0 || !scaleX.isFinite || !scaleY.isFinite) {
      throw ArgumentError('Positive finite display scales are required');
    }
    var pointer = _active[event.pointer];
    if (down) {
      if (pointer != null) throw StateError('Duplicate pointer down');
      if (_active.length == 32) return null;
      final used = _active.values.map((p) => p.id).toSet();
      var id = 0;
      while (used.contains(id)) {
        id++;
      }
      pointer = AndroidPointerData(id, 0, 0);
      if (_active.isEmpty) _downTime = event.timeStamp.inMilliseconds;
    }
    if (pointer == null) return null;
    _active[event.pointer] = AndroidPointerData(
      pointer.id,
      event.localPosition.dx * scaleX,
      event.localPosition.dy * scaleY,
      axes: {
        2: event.pressure,
        3: event.size,
        4: event.radiusMajor * 2,
        5: event.radiusMinor * 2,
        8: event.orientation,
      },
    );
    final index = _active.keys.toList().indexOf(event.pointer);
    final action = cancel
        ? 3
        : down
        ? (_active.length == 1 ? 0 : 5 | (index << 8))
        : up
        ? (_active.length == 1 ? 1 : 6 | (index << 8))
        : 2;
    final result = AndroidMotionState(
      action: action,
      pointers: _active.values.toList(),
      downTimeMillis: _downTime,
      eventTimeMillis: event.timeStamp.inMilliseconds,
    );
    if (cancel) {
      _active.clear();
    } else if (up) {
      _active.remove(event.pointer);
    }
    return result;
  }
}

void registerAndroidInput(DalvikRuntime vm) {
  vm.registerExternalClass(_motion);
  vm.registerExternalClass(_key);
  vm.registerExternalClass('Landroid/view/InputDevice;');
  void motion(String member, DalvikBody body) =>
      vm.registerNative('$_motion->$member', body);
  AndroidMotionState state(Object? object) =>
      vm.object(object).nativeValue as AndroidMotionState;
  AndroidPointerData pointer(Object? object, int index) {
    final value = state(object);
    if (index < 0 || index >= value.pointers.length) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'pointerIndex out of range',
      );
    }
    return value.pointers[index];
  }

  motion('getAction()I', (_, a) => state(a[0]).action);
  motion('getActionMasked()I', (_, a) => state(a[0]).actionMasked);
  motion('getActionIndex()I', (_, a) => state(a[0]).actionIndex);
  motion('getPointerCount()I', (_, a) => state(a[0]).pointers.length);
  motion('getPointerId(I)I', (_, a) => pointer(a[0], a[1] as int).id);
  for (final axis in ['X', 'Y']) {
    final number = axis == 'X' ? 0 : 1;
    motion(
      'get$axis()F',
      (_, a) => JavaNumbers.floatBits(pointer(a[0], 0).axis(number)),
    );
    motion(
      'get$axis(I)F',
      (_, a) => JavaNumbers.floatBits(pointer(a[0], a[1] as int).axis(number)),
    );
  }
  motion(
    'getAxisValue(I)F',
    (_, a) => JavaNumbers.floatBits(pointer(a[0], 0).axis(a[1] as int)),
  );
  motion(
    'obtain(JJIFFI)Landroid/view/MotionEvent;',
    (_, a) => AndroidMotionState(
      action: a[4] as int,
      pointers: [
        AndroidPointerData(
          0,
          JBits.float(a, 5),
          JBits.float(a, 6),
          axes: const {2: 1, 3: 1},
        ),
      ],
      downTimeMillis: JBits.wide(a, 0),
      eventTimeMillis: JBits.wide(a, 2),
      metaState: a[7] as int,
    ).asObject(),
  );
  void key(String member, DalvikBody body) =>
      vm.registerNative('$_key->$member', body);
  AndroidKeyState keyState(Object? object) =>
      vm.object(object).nativeValue as AndroidKeyState;
  key('<init>(II)V', (_, a) {
    vm.object(a[0]).nativeValue = AndroidKeyState(
      action: a[1] as int,
      keyCode: a[2] as int,
    );
    return null;
  });
  key('getAction()I', (_, a) => keyState(a[0]).action);
  key('getKeyCode()I', (_, a) => keyState(a[0]).keyCode);
  key('getRepeatCount()I', (_, a) => keyState(a[0]).repeatCount);
  key('getDevice()Landroid/view/InputDevice;', (_, a) => keyState(a[0]).device);
  key('startTracking()V', (_, a) {
    final value = keyState(a[0]);
    if (value.action != 0) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Can only start tracking a down event',
      );
    }
    value.trackingRequested = true;
    return null;
  });
}
