import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/android_intents.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  const intent = 'Landroid/content/Intent;', bundle = 'Landroid/os/Bundle;';
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerAndroidIntents(vm);
  });
  Object? call(String owner, String member, List<Object?> args) => vm.call(
    '$owner->$member',
    args,
    kind: member.startsWith('<init>') ? 'direct' : 'virtual',
  );
  DalvikObject make(String owner) {
    final object = vm.allocate(owner);
    call(owner, '<init>()V', [object]);
    return object;
  }

  test(
    'Intent extras retain long bits, null presence and typed default behavior',
    () {
      final object = make(intent);
      expect(call(intent, 'getExtras()$bundle', [object]), null);
      final wide = <Object?>[object, vm.newString('long'), 0, 0];
      JBits.setWide(wide, 2, 0x7fffffffffffffff);
      expect(
        call(intent, 'putExtra(Ljava/lang/String;J)$intent', wide),
        same(object),
      );
      expect(
        call(intent, 'getLongExtra(Ljava/lang/String;J)J', [
          object,
          vm.newString('long'),
          0,
          0,
        ]),
        0x7fffffffffffffff,
      );
      expect(
        call(intent, 'getIntExtra(Ljava/lang/String;I)I', [
          object,
          vm.newString('long'),
          42,
        ]),
        42,
      );
      call(intent, 'putExtra(Ljava/lang/String;Ljava/lang/String;)$intent', [
        object,
        vm.newString('empty'),
        null,
      ]);
      expect(
        call(intent, 'hasExtra(Ljava/lang/String;)Z', [
          object,
          vm.newString('empty'),
        ]),
        1,
      );
      expect(
        call(intent, 'getStringExtra(Ljava/lang/String;)Ljava/lang/String;', [
          object,
          vm.newString('empty'),
        ]),
        null,
      );
    },
  );
  test('Bundle copy shares referenced objects but isolates map changes', () {
    final object = make(intent),
        child = make(bundle),
        bytes = vm.array('[B', 2)..values.setAll(0, [1, 2]);
    call(intent, 'putExtra(Ljava/lang/String;Landroid/os/Parcelable;)$intent', [
      object,
      vm.newString('child'),
      child,
    ]);
    expect(
      call(intent, 'getBundleExtra(Ljava/lang/String;)$bundle', [
        object,
        vm.newString('child'),
      ]),
      same(child),
    );
    call(intent, 'putExtra(Ljava/lang/String;[B)$intent', [
      object,
      vm.newString('bytes'),
      bytes,
    ]);
    final copy = call(intent, 'getExtras()$bundle', [object]) as DalvikObject;
    expect(
      call(bundle, 'getByteArray(Ljava/lang/String;)[B', [
        copy,
        vm.newString('bytes'),
      ]),
      same(bytes),
    );
    call(bundle, 'remove(Ljava/lang/String;)V', [copy, vm.newString('bytes')]);
    expect(
      call(intent, 'hasExtra(Ljava/lang/String;)Z', [
        object,
        vm.newString('bytes'),
      ]),
      1,
    );
    call(bundle, 'putInt(Ljava/lang/String;I)V', [
      child,
      vm.newString('value'),
      7,
    ]);
    expect(
      (androidIntent(vm, object).extras!.values['child']!.value as DalvikObject)
          .nativeValue,
      same(child.nativeValue),
    );
  });
  test('Bundle generic get boxes primitives using Java wrappers', () {
    final value = make(bundle);
    call(bundle, 'putInt(Ljava/lang/String;I)V', [
      value,
      vm.newString('i'),
      123,
    ]);
    final boxed = call(bundle, 'get(Ljava/lang/String;)Ljava/lang/Object;', [
      value,
      vm.newString('i'),
    ]);
    expect(
      vm.call('Ljava/lang/Integer;->intValue()I', [boxed], kind: 'virtual'),
      123,
    );
  });
  test(
    'launch target, flags and action stay inspectable for host navigation',
    () {
      final value = make(intent);
      call(
        intent,
        'setClassName(Ljava/lang/String;Ljava/lang/String;)$intent',
        [
          value,
          vm.newString('com.original'),
          vm.newString('com.original.Game'),
        ],
      );
      call(intent, 'setAction(Ljava/lang/String;)$intent', [
        value,
        vm.newString('android.intent.action.MAIN'),
      ]);
      call(intent, 'setFlags(I)$intent', [value, 0x10000000]);
      call(intent, 'addFlags(I)$intent', [value, 0x20000]);
      final state = androidIntent(vm, value);
      expect(state.className, 'com.original.Game');
      expect(state.componentPackageName, 'com.original');
      expect(state.flags, 0x10020000);
      expect(
        vm.string(call(intent, 'getAction()Ljava/lang/String;', [value])),
        'android.intent.action.MAIN',
      );
      final other = make(intent);
      call(intent, 'putExtra(Ljava/lang/String;I)$intent', [
        other,
        vm.newString('number'),
        1,
      ]);
      call(intent, 'replaceExtras($intent)$intent', [value, other]);
      call(intent, 'putExtra(Ljava/lang/String;I)$intent', [
        other,
        vm.newString('number'),
        2,
      ]);
      expect(
        call(intent, 'getIntExtra(Ljava/lang/String;I)I', [
          value,
          vm.newString('number'),
          0,
        ]),
        1,
      );
    },
  );
}
