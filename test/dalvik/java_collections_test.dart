import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

Matcher javaError(String type) => throwsA(
  isA<DalvikThrown>().having(
    (e) => e.object.className,
    'class',
    'Ljava/$type;',
  ),
);

void main() {
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaCollections(vm);
  });
  Object? call(
    DalvikObject receiver,
    String member, [
    List<Object?> args = const [],
  ]) => vm.call('${receiver.className}->$member', [
    receiver,
    ...args,
  ], kind: 'virtual');
  DalvikObject create(
    String name, [
    String signature = '()V',
    List<Object?> args = const [],
  ]) {
    final object = vm.allocate('Ljava/util/$name;');
    vm.call('${object.className}-><init>$signature', [
      object,
      ...args,
    ], kind: 'direct');
    return object;
  }

  DalvikObject s(String text) => vm.newString(text);
  Object? staticCall(String owner, String member, List<Object?> args) =>
      vm.call('Ljava/util/$owner;->$member', args, kind: 'static');

  test('all 84 collection APIs referenced by original DEX have bridges', () {
    final methods = jsonDecode(
      File('test/fixtures/dalvik/collections_api.json').readAsStringSync(),
    ) as List;
    expect(methods.length, 84);
    for (final method in methods) {
      expect(
        vm.nativeMethods.containsKey(method),
        isTrue,
        reason: method as String,
      );
    }
  });

  test('operation trace matches independently executed JDK oracle', () {
    final trace = <String>[];
    String text(Object? value) => vm.isNull(value) ? 'null' : vm.string(value);
    String boolean(Object? value) => (value == 1).toString();
    void error(void Function() action) {
      try {
        action();
        trace.add('no error');
      } on DalvikThrown catch (e) {
        trace.add(
          e.object.className
              .substring(1, e.object.className.length - 1)
              .replaceAll('/', '.'),
        );
      }
    }

    final v = create('Vector');
    for (final value in [s('a'), null, s('b')]) {
      call(v, 'addElement(Ljava/lang/Object;)V', [value]);
    }
    trace.add(
      'vector:${call(v, 'size()I')}:${call(v, 'indexOf(Ljava/lang/Object;)I', [null])}:${boolean(call(v, 'contains(Ljava/lang/Object;)Z', [s('a')]))}',
    );
    final enumeration =
        call(v, 'elements()Ljava/util/Enumeration;') as DalvikObject;
    call(v, 'addElement(Ljava/lang/Object;)V', [s('c')]);
    while (call(enumeration, 'hasMoreElements()Z') == 1) {
      trace.add(
        'enum:${text(call(enumeration, 'nextElement()Ljava/lang/Object;'))}',
      );
    }
    error(() => call(v, 'elementAt(I)Ljava/lang/Object;', [-1]));
    final list = create('ArrayList');
    for (final value in ['a', 'b']) {
      call(list, 'add(Ljava/lang/Object;)Z', [s(value)]);
    }
    final iterator =
        call(list, 'iterator()Ljava/util/Iterator;') as DalvikObject;
    call(list, 'set(ILjava/lang/Object;)Ljava/lang/Object;', [0, s('c')]);
    trace.add('iterator:${text(call(iterator, 'next()Ljava/lang/Object;'))}');
    call(iterator, 'remove()V');
    trace.add(
      'after-remove:${call(list, 'size()I')}:${text(call(iterator, 'next()Ljava/lang/Object;'))}',
    );
    error(() => call(iterator, 'next()Ljava/lang/Object;'));
    final invalid =
        call(list, 'iterator()Ljava/util/Iterator;') as DalvikObject;
    call(list, 'add(Ljava/lang/Object;)Z', [s('d')]);
    error(() => call(invalid, 'next()Ljava/lang/Object;'));
    final table = create('Hashtable');
    trace.add(
      'table-put:${text(call(table, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [s('key'), s('first')]))}',
    );
    trace.add(
      'table-put:${text(call(table, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [s('key'), s('second')]))}',
    );
    trace.add(
      'table:${call(table, 'size()I')}:${text(call(table, 'get(Ljava/lang/Object;)Ljava/lang/Object;', [s('key')]))}',
    );
    error(
      () => call(
        table,
        'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',
        [null, s('value')],
      ),
    );
    error(
      () => call(
        table,
        'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',
        [s('x'), null],
      ),
    );
    error(() => call(table, 'contains(Ljava/lang/Object;)Z', [null]));
    final map = create('HashMap');
    call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
      null,
      null,
    ]);
    trace.add(
      'null-key:${boolean(call(map, 'containsKey(Ljava/lang/Object;)Z', [null]))}',
    );
    final view = call(map, 'values()Ljava/util/Collection;') as DalvikObject;
    call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
      s('a'),
      s('b'),
    ]);
    call(view, 'remove(Ljava/lang/Object;)Z', [s('b')]);
    trace.add(
      'view:${call(map, 'size()I')}:${boolean(call(map, 'containsKey(Ljava/lang/Object;)Z', [s('a')]))}',
    );
    final set = create('HashSet');
    for (final value in [s('a'), s('a'), null]) {
      call(set, 'add(Ljava/lang/Object;)Z', [value]);
    }
    trace.add('set:${call(set, 'size()I')}');
    final array = vm.array('[Ljava/lang/String;', 2)
      ..values.setAll(0, [s('one'), s('two')]);
    final source = staticCall(
      'Arrays',
      'asList([Ljava/lang/Object;)Ljava/util/List;',
      [array],
    ) as DalvikObject;
    final output = vm.array('[Ljava/lang/String;', 4)
      ..values.fillRange(0, 4, s('old'));
    final reused = identical(
      call(source, 'toArray([Ljava/lang/Object;)[Ljava/lang/Object;', [output]),
      output,
    );
    trace.add('toArray:$reused:[${output.values.map(text).join(', ')}]');
    error(() => call(source, 'add(Ljava/lang/Object;)Z', [s('x')]));
    final singleton = staticCall(
      'Collections',
      'singletonList(Ljava/lang/Object;)Ljava/util/List;',
      [s('a')],
    ) as DalvikObject;
    error(
      () => call(singleton, 'set(ILjava/lang/Object;)Ljava/lang/Object;', [
        0,
        s('b'),
      ]),
    );
    final equal = create('ArrayList', '(Ljava/util/Collection;)V', [source]);
    trace.add(
      'list-equality:${boolean(call(source, 'equals(Ljava/lang/Object;)Z', [equal]))}:${call(source, 'hashCode()I')}:${call(equal, 'hashCode()I')}',
    );
    final wide = <Object?>[0, 0];
    JBits.setWide(wide, 0, -1234567890123);
    final date = create('Date', '(J)V', wide);
    trace.add('date:${call(date, 'getTime()J')}');
    JBits.setWide(wide, 0, 9876543210123);
    call(date, 'setTime(J)V', wide);
    trace.add('date:${call(date, 'getTime()J')}');
    expect(
      trace,
      jsonDecode(
        File('test/fixtures/dalvik/collections_oracle.json').readAsStringSync(),
      ),
    );
  });

  test(
    'Vector preserves order, null, signed indices and Java String equality',
    () {
      final v = create('Vector');
      for (final value in [s('first'), null, s('last')]) {
        call(v, 'addElement(Ljava/lang/Object;)V', [value]);
      }
      expect(call(v, 'size()I'), 3);
      expect(call(v, 'contains(Ljava/lang/Object;)Z', [s('first')]), 1);
      expect(call(v, 'elementAt(I)Ljava/lang/Object;', [1]), isNull);
      expect(vm.string(call(v, 'firstElement()Ljava/lang/Object;')), 'first');
      expect(vm.string(call(v, 'lastElement()Ljava/lang/Object;')), 'last');
      call(v, 'setElementAt(Ljava/lang/Object;I)V', [s('middle'), 1]);
      call(v, 'removeElementAt(I)V', [0]);
      expect(
        vm.string(call(v, 'elementAt(I)Ljava/lang/Object;', [0])),
        'middle',
      );
      expect(
        () => call(v, 'elementAt(I)Ljava/lang/Object;', [-1]),
        javaError('lang/ArrayIndexOutOfBoundsException'),
      );
      call(v, 'removeAllElements()V');
      expect(
        () => call(v, 'lastElement()Ljava/lang/Object;'),
        javaError('util/NoSuchElementException'),
      );
    },
  );

  test('ArrayList iterators detect structural mutations but accept set and own removal', () {
    final list = create('ArrayList');
    call(list, 'add(Ljava/lang/Object;)Z', [s('a')]);
    call(list, 'add(Ljava/lang/Object;)Z', [s('b')]);
    final iterator =
        call(list, 'iterator()Ljava/util/Iterator;') as DalvikObject;
    call(list, 'set(ILjava/lang/Object;)Ljava/lang/Object;', [
      0,
      s('replacement'),
    ]);
    expect(
      vm.string(call(iterator, 'next()Ljava/lang/Object;')),
      'replacement',
    );
    call(iterator, 'remove()V');
    expect(call(list, 'size()I'), 1);
    expect(
      () => call(iterator, 'remove()V'),
      javaError('lang/IllegalStateException'),
    );
    expect(vm.string(call(iterator, 'next()Ljava/lang/Object;')), 'b');
    expect(
      () => call(iterator, 'next()Ljava/lang/Object;'),
      javaError('util/NoSuchElementException'),
    );
    final broken = call(list, 'iterator()Ljava/util/Iterator;') as DalvikObject;
    call(list, 'add(Ljava/lang/Object;)Z', [null]);
    expect(
      () => call(broken, 'next()Ljava/lang/Object;'),
      javaError('util/ConcurrentModificationException'),
    );
  });

  test('Vector enumeration is live; Collections enumeration delegates fail-fast iterator', () {
    final list = create('Vector');
    call(list, 'addElement(Ljava/lang/Object;)V', [s('a')]);
    final live =
        call(list, 'elements()Ljava/util/Enumeration;') as DalvikObject;
    final wrapped = staticCall(
      'Collections',
      'enumeration(Ljava/util/Collection;)Ljava/util/Enumeration;',
      [list],
    ) as DalvikObject;
    call(list, 'addElement(Ljava/lang/Object;)V', [s('b')]);
    expect(vm.string(call(live, 'nextElement()Ljava/lang/Object;')), 'a');
    expect(vm.string(call(live, 'nextElement()Ljava/lang/Object;')), 'b');
    expect(call(live, 'hasMoreElements()Z'), 0);
    expect(
      () => call(wrapped, 'nextElement()Ljava/lang/Object;'),
      javaError('util/ConcurrentModificationException'),
    );
  });

  test('Hashtable uses Java key hash and equals, preserves original key, rejects null', () {
    final table = create('Hashtable'), key = s('same');
    expect(
      call(
        table,
        'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',
        [key, s('one')],
      ),
      isNull,
    );
    expect(
      vm.string(
        call(
          table,
          'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',
          [s('same'), s('two')],
        ),
      ),
      'one',
    );
    expect(call(table, 'size()I'), 1);
    expect(
      vm.string(
        call(table, 'get(Ljava/lang/Object;)Ljava/lang/Object;', [s('same')]),
      ),
      'two',
    );
    final keys = call(table, 'keys()Ljava/util/Enumeration;') as DalvikObject;
    expect(call(keys, 'nextElement()Ljava/lang/Object;'), same(key));
    for (final member in [
      'get(Ljava/lang/Object;)Ljava/lang/Object;',
      'containsKey(Ljava/lang/Object;)Z',
      'remove(Ljava/lang/Object;)Ljava/lang/Object;',
    ]) {
      expect(
        () => call(table, member, [0]),
        javaError('lang/NullPointerException'),
      );
    }
    expect(
      () => call(
        table,
        'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',
        [key, null],
      ),
      javaError('lang/NullPointerException'),
    );
  });

  test('HashMap allows null key/value and values view remains backed', () {
    final map = create('HashMap');
    call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
      null,
      null,
    ]);
    expect(call(map, 'containsKey(Ljava/lang/Object;)Z', [0]), 1);
    final values = call(map, 'values()Ljava/util/Collection;') as DalvikObject;
    expect(call(values, 'size()I'), 1);
    call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
      s('key'),
      s('value'),
    ]);
    expect(call(values, 'size()I'), 2);
    expect(call(values, 'remove(Ljava/lang/Object;)Z', [s('value')]), 1);
    expect(call(map, 'containsKey(Ljava/lang/Object;)Z', [s('key')]), 0);
    expect(
      () => call(values, 'add(Ljava/lang/Object;)Z', [s('no')]),
      javaError('lang/UnsupportedOperationException'),
    );
  });

  test('HashSet deduplicates separately allocated boxed and String keys', () {
    final set = create('HashSet');
    for (final key in [s('a'), s('a'), null, 0]) {
      call(set, 'add(Ljava/lang/Object;)Z', [key]);
    }
    expect(call(set, 'size()I'), 2);
    final a = vm.call('Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;', [
      300,
    ], kind: 'static');
    final b = vm.call('Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;', [
      300,
    ], kind: 'static');
    call(set, 'add(Ljava/lang/Object;)Z', [a]);
    expect(call(set, 'add(Ljava/lang/Object;)Z', [b]), 0);
    expect(call(set, 'size()I'), 3);
  });

  test(
    'typed toArray reuses oversized target and throws on incompatible type',
    () {
      final list = create('ArrayList');
      call(list, 'add(Ljava/lang/Object;)Z', [s('a')]);
      final array = vm.array('[Ljava/lang/String;', 3);
      array.values.fillRange(0, 3, s('old'));
      expect(
        call(list, 'toArray([Ljava/lang/Object;)[Ljava/lang/Object;', [array]),
        same(array),
      );
      expect(vm.string(array.values[0]), 'a');
      expect(array.values[1], isNull);
      expect(vm.string(array.values[2]), 'old');
      final empty = vm.array('[Ljava/lang/String;', 0);
      final result = call(
        list,
        'toArray([Ljava/lang/Object;)[Ljava/lang/Object;',
        [empty],
      ) as DalvikArray;
      expect(result.className, '[Ljava/lang/String;');
      expect(result.values.length, 1);
      expect(
        () => call(list, 'toArray([Ljava/lang/Object;)[Ljava/lang/Object;', [
          vm.array('[Ljava/lang/Integer;', 1),
        ]),
        javaError('lang/ArrayStoreException'),
      );
    },
  );

  test(
    'Arrays.asList is backed by typed source and singletonList is immutable',
    () {
      final array = vm.array('[Ljava/lang/String;', 1);
      array.values[0] = s('a');
      final list = staticCall(
        'Arrays',
        'asList([Ljava/lang/Object;)Ljava/util/List;',
        [array],
      ) as DalvikObject;
      expect(vm.instanceOf(list, 'Ljava/util/Collection;'), isTrue);
      call(list, 'set(ILjava/lang/Object;)Ljava/lang/Object;', [0, s('b')]);
      expect(vm.string(array.values[0]), 'b');
      array.values[0] = s('c');
      expect(vm.string(call(list, 'get(I)Ljava/lang/Object;', [0])), 'c');
      expect(
        () => call(list, 'add(Ljava/lang/Object;)Z', [s('x')]),
        javaError('lang/UnsupportedOperationException'),
      );
      expect(
        () => call(list, 'set(ILjava/lang/Object;)Ljava/lang/Object;', [
          0,
          vm.allocate('Ljava/lang/Object;'),
        ]),
        javaError('lang/ArrayStoreException'),
      );
      final singleton = staticCall(
        'Collections',
        'singletonList(Ljava/lang/Object;)Ljava/util/List;',
        [null],
      ) as DalvikObject;
      expect(
        () => call(singleton, 'set(ILjava/lang/Object;)Ljava/lang/Object;', [
          0,
          s('x'),
        ]),
        javaError('lang/UnsupportedOperationException'),
      );
    },
  );

  test('Stack supports duplicate search and empty-pop exception', () {
    final stack = create('Stack');
    for (final value in ['a', 'b', 'a']) {
      call(stack, 'push(Ljava/lang/Object;)Ljava/lang/Object;', [s(value)]);
    }
    expect(call(stack, 'search(Ljava/lang/Object;)I', [s('a')]), 1);
    expect(vm.string(call(stack, 'pop()Ljava/lang/Object;')), 'a');
    expect(call(stack, 'search(Ljava/lang/Object;)I', [s('a')]), 2);
    call(stack, 'removeAllElements()V');
    expect(
      () => call(stack, 'pop()Ljava/lang/Object;'),
      javaError('util/EmptyStackException'),
    );
  });

  test(
    'Date stores complete signed wide milliseconds; clocks are explicit',
    () {
      final wide = <Object?>[0, 0];
      JBits.setWide(wide, 0, -1234567890123);
      final date = create('Date', '(J)V', wide);
      expect(call(date, 'getTime()J'), -1234567890123);
      JBits.setWide(wide, 0, 9876543210123);
      call(date, 'setTime(J)V', wide);
      expect(call(date, 'getTime()J'), 9876543210123);
      expect(() => create('Date'), throwsA(isA<MissingDalvikBridge>()));
      vm.wallClockMillis = () => 1234;
      expect(call(create('Date'), 'getTime()J'), 1234);
      expect(
        () => staticCall('Calendar', 'getInstance()Ljava/util/Calendar;', []),
        throwsA(isA<MissingDalvikBridge>()),
      );
      expect(
        () => staticCall('TimeZone', 'getDefault()Ljava/util/TimeZone;', []),
        throwsA(isA<MissingDalvikBridge>()),
      );
    },
  );
}
