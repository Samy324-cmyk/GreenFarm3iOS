import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    vm.registerExternalClass('Ljava/lang/Object;', superclass: null);
    vm.registerExternalClass('Ljava/lang/Throwable;');
    vm.registerExternalClass(
      'Ljava/lang/Exception;',
      superclass: 'Ljava/lang/Throwable;',
    );
    vm.registerExternalClass(
      'Ljava/lang/RuntimeException;',
      superclass: 'Ljava/lang/Exception;',
    );
    for (final type in [
      'NullPointerException',
      'ArrayStoreException',
      'ArrayIndexOutOfBoundsException',
      'ClassCastException',
      'IllegalMonitorStateException',
    ]) {
      vm.registerExternalClass(
        'Ljava/lang/$type;',
        superclass: 'Ljava/lang/RuntimeException;',
      );
    }
    vm.registerClass(
      DalvikClass(
        'LA;',
        superclass: 'Ljava/lang/Object;',
        staticFields: {'LA;->counter:I': 0},
        instanceFields: {'LA;->value:I': 'I'},
      ),
    );
    vm.registerClass(
      DalvikClass(
        'LB;',
        superclass: 'LA;',
        instanceFields: {'LB;->value:I': 'I'},
      ),
    );
  });

  test('initializers execute superclass first and only once', () {
    final order = <String>[];
    vm.registerMethod(
      DalvikMethod('LA;-><clinit>()V', 8, (vm, a) {
        order.add('A');
        vm.putStatic('LA;', 'LA;->counter:I', 17);
        return null;
      }),
    );
    vm.registerMethod(
      DalvikMethod('LB;-><clinit>()V', 8, (vm, a) {
        order.add('B');
        expect(vm.getStatic('LA;', 'LA;->counter:I'), 17);
        return null;
      }),
    );
    vm.allocate('LB;');
    vm.initialize('LB;');
    expect(order, ['A', 'B']);
  });

  test('inherited static access initializes declaring class only', () {
    final order = <String>[];
    vm.registerMethod(
      DalvikMethod('LA;-><clinit>()V', 8, (_, a) {
        order.add('A');
        return null;
      }),
    );
    vm.registerMethod(
      DalvikMethod('LB;-><clinit>()V', 8, (_, a) {
        order.add('B');
        return null;
      }),
    );
    vm.putStatic('LB;', 'LB;->counter:I', 29);
    expect(vm.getStatic('LA;', 'LA;->counter:I'), 29);
    expect(order, ['A']);
  });

  test('instance field hiding retains separate storage', () {
    final value = vm.allocate('LB;');
    vm.putField(value, 'LA;->value:I', 11);
    vm.putField(value, 'LB;->value:I', 22);
    expect(vm.getField(value, 'LA;->value:I'), 11);
    expect(vm.getField(value, 'LB;->value:I'), 22);
  });

  test('virtual, super, direct and inherited static dispatch', () {
    vm.registerMethod(DalvikMethod('LA;->value()I', 1, (_, a) => 10));
    vm.registerMethod(DalvikMethod('LB;->value()I', 1, (_, a) => 20));
    vm.registerMethod(DalvikMethod('LA;->staticValue()I', 8, (_, a) => 30));
    final b = vm.allocate('LB;');
    expect(vm.call('LA;->value()I', [b], kind: 'virtual'), 20);
    expect(vm.call('LA;->value()I', [b], kind: 'super', caller: 'LB;'), 10);
    expect(vm.call('LA;->value()I', [b], kind: 'direct'), 10);
    expect(vm.call('LB;->staticValue()I', [], kind: 'static'), 30);
  });

  test('array covariance and primitive arrays follow JVM type rules', () {
    final values = vm.array('[LA;', 2);
    vm.arrayPut(values, 0, vm.allocate('LB;'));
    expect(vm.instanceOf(values, '[Ljava/lang/Object;'), isTrue);
    expect(vm.instanceOf(vm.array('[I', 2), '[Ljava/lang/Object;'), isFalse);
    expect(vm.instanceOf(vm.array('[[I', 2), '[Ljava/lang/Object;'), isTrue);
    expect(
      () => vm.arrayPut(values, 1, vm.newString('x')),
      throwsA(isA<MissingDalvikBridge>()),
    );
    vm.registerExternalClass('Ljava/lang/String;');
    expect(
      () => vm.arrayPut(values, 1, vm.newString('x')),
      throwsA(isA<DalvikThrown>()),
    );
  });

  test('integer zero is null only in reference contexts', () {
    expect(vm.registerEquals(0, null), isTrue);
    expect(vm.registerEquals(2, 2), isTrue);
    expect(vm.registerEquals(vm.newString('a'), vm.newString('a')), isFalse);
    expect(vm.registerEquals(vm.intern('a'), vm.intern('a')), isTrue);
    expect(() => vm.object(0), throwsA(isA<DalvikThrown>()));
  });

  test('monitor ownership is reentrant and detects unmatched exits', () {
    final lock = vm.allocate('LA;');
    vm.monitorEnter(lock);
    vm.monitorEnter(lock);
    vm.monitorExit(lock);
    vm.monitorExit(lock);
    expect(() => vm.monitorExit(lock), throwsA(isA<DalvikThrown>()));
  });

  test('missing native bridges cannot be swallowed as Java exceptions', () {
    final failure = MissingDalvikBridge('test');
    expect(vm.javaException(failure), isNull);
    expect(
      () => vm.call('LA;->missing()I', [], kind: 'static'),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });
}
