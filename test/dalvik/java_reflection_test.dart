import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/cooperative.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_reflection.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0058.dart';
import 'package:green_farm_port/generated/c0368.dart';

const classClass = 'Ljava/lang/Class;';
const methodClass = 'Ljava/lang/reflect/Method;';
const fixture = 'Lfixture/Numbers;';
const wrappers = {
  'Z': 'Boolean',
  'B': 'Byte',
  'C': 'Character',
  'S': 'Short',
  'I': 'Integer',
  'J': 'Long',
  'F': 'Float',
  'D': 'Double',
};

void main() {
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaReflection(vm);
  });
  Object? call(
    DalvikObject receiver,
    String owner,
    String member, [
    List<Object?> arguments = const [],
  ]) => vm.call('$owner->$member', [receiver, ...arguments], kind: 'virtual');
  DalvikArray array(String type, List<Object?> values) {
    final result = vm.array(type, values.length)..values.setAll(0, values);
    return result;
  }

  DalvikObject reflect(
    String owner,
    String name, [
    List<String> parameters = const [],
    bool inherited = false,
  ]) => call(
    vm.typeObject(owner),
    classClass,
    '${inherited ? 'getMethod' : 'getDeclaredMethod'}(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;',
    [
      vm.intern(name),
      array('[Ljava/lang/Class;', parameters.map(vm.typeObject).toList()),
    ],
  ) as DalvikObject;
  Object? invoke(
    DalvikObject method,
    Object? receiver, [
    List<Object?> arguments = const [],
  ]) => call(
    method,
    methodClass,
    'invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;',
    [receiver, array('[Ljava/lang/Object;', arguments)],
  );
  DalvikObject boxed(String type, int raw) {
    final owner = 'Ljava/lang/${wrappers[type]};';
    final args = type == 'J' || type == 'D'
        ? <Object?>[raw.toSigned(32), (raw >> 32).toSigned(32)]
        : <Object?>[raw];
    return vm.call('$owner->valueOf($type)$owner', args, kind: 'static')
        as DalvikObject;
  }

  Matcher javaError(String type) => throwsA(
    isA<DalvikThrown>().having(
      (e) => e.object.className,
      'Java exception',
      'Ljava/lang/$type;',
    ),
  );
  void define(
    String name, {
    String superclass = 'Ljava/lang/Object;',
    int access = 1,
    Map<String, String> fields = const {},
  }) => vm.registerClass(
    DalvikClass(
      name,
      superclass: superclass,
      access: access,
      instanceFields: fields,
    ),
  );

  test('144 independent JDK primitive boxing and widening vectors', () {
    define(fixture);
    for (final type in wrappers.keys) {
      vm.registerMethod(
        DalvikMethod(
          '$fixture->as$type($type)$type',
          9,
          (_, a) => type == 'J' || type == 'D' ? JBits.wide(a, 0) : a[0],
        ),
      );
    }
    final vectors = jsonDecode(
      File('test/fixtures/dalvik/reflection_oracle.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(vectors.length, 144);
    for (final vector in vectors) {
      final source = vector['source'] as String,
          target = vector['target'] as String;
      final input = boxed(source, int.parse(vector['input'] as String));
      final member = reflect(fixture, 'as$target', [target]);
      final label = '$source ${vector['input']} -> $target';
      if (vector['error'] != '') {
        expect(
          () => invoke(member, null, [input]),
          javaError('IllegalArgumentException'),
          reason: label,
        );
      } else {
        final output = invoke(member, null, [input]) as DalvikObject;
        expect(
          output.className,
          'Ljava/lang/${wrappers[target]};',
          reason: label,
        );
        expect(output.nativeValue.toString(), vector['output'], reason: label);
      }
    }
  });

  test('overloads use exact requested descriptors, not widening lookup', () {
    define(fixture);
    vm.registerMethod(DalvikMethod('$fixture->pick(I)I', 9, (_, a) => 1));
    vm.registerMethod(DalvikMethod('$fixture->pick(J)I', 9, (_, a) => 2));
    expect(
      (invoke(reflect(fixture, 'pick', ['I']), null, [
        boxed('I', 4),
      ]) as DalvikObject).nativeValue,
      1,
    );
    expect(
      (invoke(reflect(fixture, 'pick', ['J']), null, [
        boxed('I', 4),
      ]) as DalvikObject).nativeValue,
      2,
    );
    expect(
      () => reflect(fixture, 'pick', ['S']),
      javaError('NoSuchMethodException'),
    );
    expect(
      () => reflect(fixture, 'missing'),
      javaError('NoSuchMethodException'),
    );
  });

  test(
    'virtual dispatch, inherited lookup, static receiver and private dispatch',
    () {
      const base = 'Lfixture/Base;', sub = 'Lfixture/Sub;';
      define(base);
      define(sub, superclass: base);
      vm.registerMethod(DalvikMethod('$base->value()I', 1, (_, a) => 1));
      vm.registerMethod(DalvikMethod('$sub->value()I', 1, (_, a) => 2));
      vm.registerMethod(DalvikMethod('$base->staticValue()I', 9, (_, a) => 3));
      vm.registerMethod(DalvikMethod('$base->secret()I', 2, (_, a) => 4));
      vm.registerMethod(DalvikMethod('$sub->secret()I', 2, (_, a) => 5));
      final receiver = vm.allocate(sub);
      expect(
        (invoke(reflect(base, 'value'), receiver) as DalvikObject).nativeValue,
        2,
      );
      expect(
        (invoke(
          reflect(sub, 'staticValue', [], true),
          vm.intern('ignored'),
        ) as DalvikObject).nativeValue,
        3,
      );
      expect(
        () => reflect(sub, 'staticValue'),
        javaError('NoSuchMethodException'),
      );
      final private = reflect(base, 'secret');
      expect(call(private, methodClass, 'isAccessible()Z'), 0);
      expect(
        () => invoke(private, receiver),
        javaError('IllegalAccessException'),
      );
      call(private, methodClass, 'setAccessible(Z)V', [1]);
      expect((invoke(private, receiver) as DalvikObject).nativeValue, 4);
      call(private, methodClass, 'setAccessible(Z)V', [0]);
      expect(
        () => invoke(private, receiver),
        javaError('IllegalAccessException'),
      );
    },
  );

  test('receiver, reference type, primitive null and arity checks are not target exceptions', () {
    define(fixture);
    vm.registerMethod(
      DalvikMethod('$fixture->accept(Ljava/lang/String;I)V', 1, (_, a) => null),
    );
    final member = reflect(fixture, 'accept', ['Ljava/lang/String;', 'I']);
    final receiver = vm.allocate(fixture);
    expect(
      () => invoke(member, null, [null, boxed('I', 1)]),
      javaError('NullPointerException'),
    );
    expect(
      () => invoke(member, vm.intern('wrong'), [null, boxed('I', 1)]),
      javaError('IllegalArgumentException'),
    );
    expect(
      () => invoke(member, receiver, [boxed('I', 2), boxed('I', 1)]),
      javaError('IllegalArgumentException'),
    );
    expect(
      () => invoke(member, receiver, [null, null]),
      javaError('IllegalArgumentException'),
    );
    expect(
      () => invoke(member, receiver),
      javaError('IllegalArgumentException'),
    );
    expect(invoke(member, receiver, [null, boxed('B', 1)]), isNull);
  });

  test(
    'target exceptions preserve identity through InvocationTargetException',
    () {
      define(fixture);
      final original = DalvikObject(
        'Ljava/lang/IllegalArgumentException;',
        nativeValue: 'target',
      );
      vm.registerMethod(
        DalvikMethod(
          '$fixture->fail()V',
          9,
          (_, a) => throw DalvikThrown(original),
        ),
      );
      try {
        invoke(reflect(fixture, 'fail'), null);
        fail('Expected target exception');
      } on DalvikThrown catch (error) {
        expect(
          error.object.className,
          'Ljava/lang/reflect/InvocationTargetException;',
        );
        expect(
          call(
            error.object,
            error.object.className,
            'getCause()Ljava/lang/Throwable;',
          ),
          same(original),
        );
        expect(
          call(
            error.object,
            'Ljava/lang/Throwable;',
            'getMessage()Ljava/lang/String;',
          ),
          isNull,
        );
      }
    },
  );

  test('unported target bodies remain fatal integration errors', () {
    define(fixture);
    vm.registerMethod(DalvikMethod('$fixture->unported()V', 0x109, null));
    expect(
      () => invoke(reflect(fixture, 'unported'), null),
      throwsA(isA<MissingDalvikBridge>()),
    );
  });

  test(
    'suspended reflected target returns one boxed result without replay',
    () async {
      define(fixture);
      var calls = 0;
      vm.registerMethod(
        DalvikMethod('$fixture->later()I', 9, (v, a) {
          calls++;
          v.suspendUntil(Future<Object?>.value(42));
        }),
      );
      final member = reflect(fixture, 'later');
      final value = await DalvikExecutor().run(
        () => invoke(member, null),
      ) as DalvikObject;
      expect(value.className, 'Ljava/lang/Integer;');
      expect(value.nativeValue, 42);
      expect(calls, 1);
    },
  );

  test('suspended target error is wrapped, initializer error is not', () async {
    define(fixture);
    final cause = DalvikObject(
      'Ljava/lang/IllegalStateException;',
      nativeValue: 'async target',
    );
    vm.registerMethod(
      DalvikMethod(
        '$fixture->later()I',
        9,
        (v, a) => v.suspendUntil(Future<Object?>.error(DalvikThrown(cause))),
      ),
    );
    try {
      await DalvikExecutor().run(() => invoke(reflect(fixture, 'later'), null));
      fail('Expected wrapped async failure');
    } on DalvikThrown catch (error) {
      expect(
        error.object.className,
        'Ljava/lang/reflect/InvocationTargetException;',
      );
      expect(
        call(
          error.object,
          error.object.className,
          'getTargetException()Ljava/lang/Throwable;',
        ),
        same(cause),
      );
    }
    const broken = 'Lfixture/Broken;';
    define(broken);
    vm.registerMethod(
      DalvikMethod(
        '$broken-><clinit>()V',
        8,
        (v, a) => v.throwJava('Ljava/lang/IllegalStateException;', 'init'),
      ),
    );
    vm.registerMethod(DalvikMethod('$broken->value()I', 9, (_, a) => 1));
    expect(
      () => invoke(reflect(broken, 'value'), null),
      javaError('ExceptionInInitializerError'),
    );
  });

  test(
    'Class.forName returns its Class after suspended initialization',
    () async {
      const lazy = 'Lfixture/Lazy;';
      define(lazy);
      var count = 0;
      vm.registerMethod(
        DalvikMethod('$lazy-><clinit>()V', 8, (v, a) {
          count++;
          v.suspendUntil(Future<Object?>.value(null));
        }),
      );
      final value = await DalvikExecutor().run(
        () => vm.call(
          '$classClass->forName(Ljava/lang/String;)Ljava/lang/Class;',
          [vm.intern('fixture.Lazy')],
          kind: 'static',
        ),
      );
      expect(value, same(vm.typeObject(lazy)));
      expect(count, 1);
      expect(vm.classes[lazy]!.initialization, 2);
    },
  );

  test(
    'nested suspension restores full caller chain and private access checks',
    () async {
      const outer = 'Lfixture/Outer;', child = 'Lfixture/Child;';
      const outerKey = '$outer->run()I', childKey = '$child->run()I';
      define(outer);
      define(child);
      vm.registerMethod(DalvikMethod('$outer->secret()I', 10, (_, a) => 11));
      vm.registerMethod(DalvikMethod('$child->secret()I', 10, (_, a) => 9));
      final outerSecret = reflect(outer, 'secret'),
          childSecret = reflect(child, 'secret');
      final first = Completer<Object?>(), second = Completer<Object?>();
      var starts = 0, resumes = 0;
      vm.registerMethod(
        DalvikMethod(childKey, 9, (v, a) {
          starts++;
          var phase = 0;
          Object? run([DalvikCompletion? done]) {
            try {
              if (phase == 0) {
                if (done == null) v.suspendUntil(first.future);
                done.unwrap();
                done = null;
                phase = 1;
              }
              if (phase == 1) {
                if (done == null) v.suspendUntil(second.future);
                done.unwrap();
                phase = 2;
              }
              resumes++;
              expect(v.callStack, [outerKey, childKey]);
              expect(
                () => invoke(outerSecret, null),
                javaError('IllegalAccessException'),
              );
              return (invoke(childSecret, null) as DalvikObject).nativeValue;
            } on DalvikPause catch (pause) {
              final saved = List<String>.of(v.callStack);
              pause.addFrame(
                DalvikResumeFrame(
                  methodKey: childKey,
                  pc: phase,
                  resume: (done) => v.withCallFrame(
                    childKey,
                    () => run(done),
                    restoredStack: saved,
                  ),
                ),
              );
              rethrow;
            }
          }

          return run();
        }),
      );
      vm.registerMethod(
        DalvikMethod(outerKey, 9, (v, a) {
          Object? finish(Object? value) {
            expect(v.callStack, [outerKey]);
            return (value as int) +
                ((invoke(outerSecret, null) as DalvikObject).nativeValue
                    as int);
          }

          try {
            return finish(v.call(childKey, [], kind: 'static'));
          } on DalvikPause catch (pause) {
            final saved = List<String>.of(v.callStack);
            pause.addFrame(
              DalvikResumeFrame(
                methodKey: outerKey,
                pc: 0,
                resume: (done) => v.withCallFrame(
                  outerKey,
                  () => finish(done.unwrap()),
                  restoredStack: saved,
                ),
              ),
            );
            rethrow;
          }
        }),
      );
      final result = DalvikExecutor().run(
        () => vm.call(outerKey, [], kind: 'static'),
      );
      expect(vm.callStack, isEmpty);
      first.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(vm.callStack, isEmpty);
      second.complete(null);
      expect(await result, 20);
      expect(starts, 1);
      expect(resumes, 1);
      expect(vm.callStack, isEmpty);
    },
  );

  test(
    'Class.newInstance allocates and invokes constructor across suspension',
    () async {
      const name = 'Lfixture/New;';
      define(name, fields: {'$name->value:I': 'I'});
      var count = 0;
      vm.registerMethod(
        DalvikMethod('$name-><init>()V', 1, (v, a) {
          count++;
          v.putField(a[0], '$name->value:I', 7);
          v.suspendUntil(Future<Object?>.value(null));
        }),
      );
      final object = await DalvikExecutor().run(
        () => call(
          vm.typeObject(name),
          classClass,
          'newInstance()Ljava/lang/Object;',
        ),
      );
      expect(vm.getField(object, '$name->value:I'), 7);
      expect(count, 1);
      const abstractClass = 'Lfixture/Abstract;';
      define(abstractClass, access: 0x401);
      expect(
        () => call(
          vm.typeObject(abstractClass),
          classClass,
          'newInstance()Ljava/lang/Object;',
        ),
        javaError('InstantiationException'),
      );
      const privateClass = 'Lfixture/Private;';
      define(privateClass);
      vm.registerMethod(
        DalvikMethod('$privateClass-><init>()V', 2, (_, a) => null),
      );
      expect(
        () => call(
          vm.typeObject(privateClass),
          classClass,
          'newInstance()Ljava/lang/Object;',
        ),
        javaError('IllegalAccessException'),
      );
    },
  );

  test('original pointer methods reflect and execute with an initialized-state fixture', () {
    registerClass58(vm);
    registerClass368(vm);
    const library = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GLLib;',
        config = 'Lc/c/a/a/a/w/p;';
    // This isolates reflection from Android startup; it does not claim to test
    // the GLLib class initializer or the complete game bootstrap.
    vm.classes[library]!.initialization = 2;
    vm.classes[config]!.initialization = 2;
    vm.putStatic(config, '$config->a3:I', 2);
    final get = reflect(library, 'Pointer_GetNumPointers'),
        set = reflect(library, 'Pointer_SetCurrentPointer', ['I']);
    call(get, methodClass, 'setAccessible(Z)V', [1]);
    call(set, methodClass, 'setAccessible(Z)V', [1]);
    expect(
      (invoke(
        get,
        vm.intern('ignored static receiver'),
      ) as DalvikObject).nativeValue,
      2,
    );
    expect(invoke(set, null, [boxed('I', 1)]), isNull);
    expect(vm.getStatic(library, '$library->d4:I'), 1);
    final package = call(
      vm.typeObject(library),
      classClass,
      'getPackage()Ljava/lang/Package;',
    ) as DalvikObject;
    expect(
      vm.string(
        call(package, 'Ljava/lang/Package;', 'getName()Ljava/lang/String;'),
      ),
      'com.gameloft.android.ANMP.GloftGF2F.S800x480',
    );
  });

  test(
    'package and simple name preserve primitive/array/default-package rules',
    () {
      define('Lfixture/Top;');
      define('LDefault;');
      expect(
        vm.string(
          call(
            vm.typeObject('[[I'),
            classClass,
            'getSimpleName()Ljava/lang/String;',
          ),
        ),
        'int[][]',
      );
      expect(
        vm.string(
          call(
            vm.typeObject('Lfixture/Top;'),
            classClass,
            'getSimpleName()Ljava/lang/String;',
          ),
        ),
        'Top',
      );
      expect(
        call(vm.typeObject('I'), classClass, 'getPackage()Ljava/lang/Package;'),
        isNull,
      );
      expect(
        call(
          vm.typeObject('LDefault;'),
          classClass,
          'getPackage()Ljava/lang/Package;',
        ),
        isNull,
      );
      expect(
        () => call(
          vm.typeObject('Lfixture/Outer\$Inner;'),
          classClass,
          'getSimpleName()Ljava/lang/String;',
        ),
        throwsA(isA<MissingDalvikBridge>()),
      );
    },
  );
}
