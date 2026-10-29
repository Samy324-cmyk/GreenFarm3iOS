import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_json.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaCollections(vm);
    registerJavaJson(vm);
  });
  Object? call(
    Object? receiver,
    String member, [
    List<Object?> args = const [],
  ]) => vm.call('Ljava/lang/Object;->$member', [
    receiver,
    ...args,
  ], kind: 'virtual');
  DalvikObject create(
    String name, [
    String signature = '()V',
    List<Object?> args = const [],
  ]) {
    final object = vm.allocate('Lorg/json/$name;');
    vm.call('${object.className}-><init>$signature', [
      object,
      ...args,
    ], kind: 'direct');
    return object;
  }

  DalvikObject parse(String name, String input) =>
      create(name, '(Ljava/lang/String;)V', [vm.newString(input)]);
  Object? jsonNull() => vm.getStatic(
    'Lorg/json/JSONObject;',
    'Lorg/json/JSONObject;->NULL:Ljava/lang/Object;',
  );
  Matcher exception(String type) => throwsA(
    isA<DalvikThrown>().having((e) => e.object.className, 'type', type),
  );
  Object describe(Object? value) {
    if (vm.isNull(value)) return '<java-null>';
    if (identical(value, jsonNull())) return '<json-null>';
    final object = vm.object(value), type = vm.object(value).className;
    final result = <String, Object?>{
      'type': type.substring(1, type.length - 1).replaceAll('/', '.'),
    };
    if (type == 'Lorg/json/JSONObject;') {
      final keys = call(object, 'keys()Ljava/util/Iterator;'),
          pairs = <Object?>[];
      while (call(keys, 'hasNext()Z') == 1) {
        final key = call(keys, 'next()Ljava/lang/Object;');
        pairs.add([
          vm.string(key),
          describe(
            call(object, 'opt(Ljava/lang/String;)Ljava/lang/Object;', [key]),
          ),
        ]);
      }
      result['entries'] = pairs;
    } else if (type == 'Lorg/json/JSONArray;') {
      result['items'] = List.generate(
        call(object, 'length()I') as int,
        (i) => describe(call(object, 'opt(I)Ljava/lang/Object;', [i])),
      );
    } else {
      result['value'] = vm.string(call(value, 'toString()Ljava/lang/String;'));
    }
    return result;
  }

  test(
    'Map and Collection constructors wrap values including primitive arrays',
    () {
      DalvikObject collection(String type) {
        final o = vm.allocate('Ljava/util/$type;');
        vm.call('${o.className}-><init>()V', [o], kind: 'direct');
        return o;
      }

      final map = collection('HashMap'), list = collection('ArrayList');
      call(list, 'add(Ljava/lang/Object;)Z', [null]);
      final numbers = vm.array('[I', 3)..values.setAll(0, [1, -2, 3]);
      call(list, 'add(Ljava/lang/Object;)Z', [numbers]);
      call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
        vm.newString('list'),
        list,
      ]);
      final object = create('JSONObject', '(Ljava/util/Map;)V', [map]);
      expect(
        vm.string(call(object, 'toString()Ljava/lang/String;')),
        '{"list":[null,[1,-2,3]]}',
      );
      final wrapped = create('JSONArray', '(Ljava/util/Collection;)V', [list]);
      expect(call(wrapped, 'get(I)Ljava/lang/Object;', [0]), same(jsonNull()));
      final empty = create('JSONArray', '(Ljava/util/Collection;)V', [null]);
      expect(call(empty, 'length()I'), 0);
      call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
        null,
        vm.newString('bad'),
      ]);
      expect(
        () => create('JSONObject', '(Ljava/util/Map;)V', [map]),
        exception('Ljava/lang/NullPointerException;'),
      );
    },
  );
  test('nonfinite object values reject immediately but array Object overload defers to serialization', () {
    final object = create('JSONObject'), array = create('JSONArray');
    final nan = DalvikObject(
      'Ljava/lang/Double;',
      nativeValue: 0x7ff8000000000000,
    );
    expect(
      () => call(
        object,
        'put(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;',
        [vm.newString('x'), nan],
      ),
      exception('Lorg/json/JSONException;'),
    );
    call(array, 'put(Ljava/lang/Object;)Lorg/json/JSONArray;', [nan]);
    expect(call(array, 'length()I'), 1);
    expect(call(array, 'toString()Ljava/lang/String;'), isNull);
  });
  test('wrap retains explicit AOSP unsupported-object null contract', () {
    vm.registerExternalClass('Lexample/Foreign;');
    final foreign = vm.allocate('Lexample/Foreign;');
    Object? wrap(Object? value) => vm.call(
      'Lorg/json/JSONObject;->wrap(Ljava/lang/Object;)Ljava/lang/Object;',
      [value],
      kind: 'static',
    );
    expect(wrap(foreign), isNull);
    expect(wrap(null), same(jsonNull()));
    vm.registerNative(
      'Lexample/Foreign;->equals(Ljava/lang/Object;)Z',
      (v, a) => 1,
    );
    expect(wrap(foreign), same(foreign));
  });

  final cases = jsonDecode(
    File('test/fixtures/dalvik/json_cases.json').readAsStringSync(),
  ) as List;
  final oracle = jsonDecode(
    File('test/fixtures/dalvik/json_oracle.json').readAsStringSync(),
  ) as List;
  for (var i = 0; i < cases.length; i++) {
    test('AOSP android-5.0.0_r1 parser/serializer oracle case $i', () {
      final result = <String, Object?>{};
      try {
        final mode = cases[i]['mode'];
        final object = mode == 'tokener'
            ? call(
                parse('JSONTokener', cases[i]['input'] as String),
                'nextValue()Ljava/lang/Object;',
              )
            : parse(
                mode == 'object' ? 'JSONObject' : 'JSONArray',
                cases[i]['input'] as String,
              );
        result['tree'] = describe(object);
        final serialized = call(object, 'toString()Ljava/lang/String;');
        result['serialized'] = vm.isNull(serialized)
            ? null
            : vm.string(serialized);
      } on DalvikThrown catch (e) {
        final name = e.object.className;
        result['error'] = name
            .substring(1, name.length - 1)
            .replaceAll('/', '.');
        if (name == 'Lorg/json/JSONException;') {
          result['message'] = e.object.nativeValue;
        }
      }
      expect(result, oracle[i]);
    });
  }
  test(
    'all original JSON calls resolve natively or through Exception inheritance',
    () {
      final methods = jsonDecode(
        File('test/fixtures/dalvik/json_api.json').readAsStringSync(),
      ) as List;
      expect(methods.length, 27);
      for (final key in methods) {
        if ((key as String).endsWith('->printStackTrace()V')) {
          expect(
            vm.nativeMethods.containsKey(
              'Ljava/lang/Throwable;->printStackTrace()V',
            ),
            isTrue,
          );
        } else {
          expect(vm.nativeMethods.containsKey(key), isTrue, reason: key);
        }
      }
    },
  );
  test(
    'JSONObject null reference removes while NULL sentinel remains visible',
    () {
      final object = parse('JSONObject', '{a:1,b:null}');
      expect(call(object, 'has(Ljava/lang/String;)Z', [vm.newString('b')]), 1);
      expect(
        vm.string(
          call(object, 'getString(Ljava/lang/String;)Ljava/lang/String;', [
            vm.newString('b'),
          ]),
        ),
        'null',
      );
      expect(
        vm.string(
          call(object, 'optString(Ljava/lang/String;)Ljava/lang/String;', [
            vm.newString('missing'),
          ]),
        ),
        '',
      );
      expect(call(jsonNull(), 'equals(Ljava/lang/Object;)Z', [null]), 1);
      call(
        object,
        'put(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;',
        [vm.newString('a'), null],
      );
      expect(call(object, 'has(Ljava/lang/String;)Z', [vm.newString('a')]), 0);
      call(
        object,
        'put(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;',
        [null, null],
      );
      expect(
        () => call(object, 'put(Ljava/lang/String;I)Lorg/json/JSONObject;', [
          null,
          1,
        ]),
        exception('Lorg/json/JSONException;'),
      );
    },
  );
  test('numeric coercions distinguish Number narrowing from String double conversion', () {
    final object = parse(
      'JSONObject',
      '{int:4294967297, str:"4294967297", decimal:"1.9", truth:"TrUe", max:"9223372036854775806"}',
    );
    expect(
      call(object, 'getInt(Ljava/lang/String;)I', [vm.newString('int')]),
      1,
    );
    expect(
      call(object, 'getInt(Ljava/lang/String;)I', [vm.newString('str')]),
      2147483647,
    );
    expect(
      call(object, 'getInt(Ljava/lang/String;)I', [vm.newString('decimal')]),
      1,
    );
    expect(
      call(object, 'getBoolean(Ljava/lang/String;)Z', [vm.newString('truth')]),
      1,
    );
    expect(
      call(object, 'getLong(Ljava/lang/String;)J', [vm.newString('max')]),
      9223372036854775807,
    );
    final fallback = <Object?>[object, vm.newString('missing'), 0, 0];
    JBits.setWide(fallback, 2, -1234567890123);
    expect(
      vm.call(
        'Lorg/json/JSONObject;->optLong(Ljava/lang/String;J)J',
        fallback,
        kind: 'virtual',
      ),
      -1234567890123,
    );
    expect(
      () =>
          call(object, 'getInt(Ljava/lang/String;)I', [vm.newString('truth')]),
      exception('Lorg/json/JSONException;'),
    );
  });
  test(
    'key iterator removes from original object and detects structural edits',
    () {
      final object = parse('JSONObject', '{a:1,b:2}'),
          keys = call(parse('JSONObject', '{}'), 'keys()Ljava/util/Iterator;');
      expect(call(keys, 'hasNext()Z'), 0);
      final iterator = call(object, 'keys()Ljava/util/Iterator;');
      expect(vm.string(call(iterator, 'next()Ljava/lang/Object;')), 'a');
      call(iterator, 'remove()V');
      expect(call(object, 'has(Ljava/lang/String;)Z', [vm.newString('a')]), 0);
      call(object, 'put(Ljava/lang/String;I)Lorg/json/JSONObject;', [
        vm.newString('c'),
        3,
      ]);
      expect(
        () => call(iterator, 'next()Ljava/lang/Object;'),
        exception('Ljava/util/ConcurrentModificationException;'),
      );
    },
  );
  test(
    'array holes differ from explicit NULL and indexed put pads Java null',
    () {
      final array = parse('JSONArray', '[,null]');
      expect(
        () => call(array, 'get(I)Ljava/lang/Object;', [0]),
        exception('Lorg/json/JSONException;'),
      );
      expect(call(array, 'get(I)Ljava/lang/Object;', [1]), same(jsonNull()));
      call(array, 'put(II)Lorg/json/JSONArray;', [4, 9]);
      expect(
        vm.string(call(array, 'toString()Ljava/lang/String;')),
        '[null,null,null,null,9]',
      );
    },
  );
}
