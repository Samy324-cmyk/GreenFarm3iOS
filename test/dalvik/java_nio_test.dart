import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_nio.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  const byte = 'Ljava/nio/ByteBuffer;',
      base = 'Ljava/nio/Buffer;',
      intBuffer = 'Ljava/nio/IntBuffer;',
      floatBuffer = 'Ljava/nio/FloatBuffer;',
      shortBuffer = 'Ljava/nio/ShortBuffer;',
      order = 'Ljava/nio/ByteOrder;';
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaNio(vm);
  });
  Object? call(
    String owner,
    String method,
    List<Object?> a, {
    String kind = 'virtual',
  }) => vm.call('$owner->$method', a, kind: kind);
  Object? stat(String owner, String method, List<Object?> a) =>
      call(owner, method, a, kind: 'static');
  Object? allocate(int count, {bool direct = false}) =>
      stat(byte, '${direct ? 'allocateDirect' : 'allocate'}(I)$byte', [count]);
  Matcher failure(String name) => isA<DalvikThrown>().having(
    (e) => e.object.className,
    'exception',
    'Ljava/$name;',
  );
  DalvikArray array(String type, List<int> values) =>
      vm.array('[$type', values.length)..values.setAll(0, values);
  Object? endian(Endian value) => vm
      .classes[order]!
      .staticFields['$order->${value == Endian.big ? 'BIG_ENDIAN' : 'LITTLE_ENDIAN'}:$order'];
  test('Direct allocation, byte order, absolute put and relative getInt', () {
    final b = allocate(8, direct: true);
    expect(call(base, 'isDirect()Z', [b]), 1);
    expect(call(base, 'hasArray()Z', [b]), 0);
    call(byte, 'put(IB)$byte', [b, 0, 0x80]);
    call(byte, 'put(IB)$byte', [b, 1, 0xff]);
    expect(call(byte, 'getInt()I', [b]), -2130771968);
    expect(call(base, 'position()I', [b]), 4);
    call(base, 'rewind()$base', [b]);
    call(byte, 'order($order)$byte', [b, endian(Endian.little)]);
    expect(call(byte, 'getInt()I', [b]), 65408);
    expect(() => call(byte, 'getInt()I', [b]), returnsNormally);
    expect(
      () => call(byte, 'getInt()I', [b]),
      throwsA(failure('nio/BufferUnderflowException')),
    );
    expect(call(base, 'position()I', [b]), 8);
    expect(
      () => call(byte, 'put(IB)$byte', [b, 8, 1]),
      throwsA(failure('lang/IndexOutOfBoundsException')),
    );
  });
  test(
    'Views share storage, have independent state and capture original order',
    () {
      final b = allocate(12);
      call(byte, 'order($order)$byte', [b, endian(Endian.little)]);
      call(base, 'position(I)$base', [b, 1]);
      final ints = call(byte, 'asIntBuffer()$intBuffer', [b]);
      expect(javaNioBuffer(vm, ints).capacity, 2);
      call(intBuffer, 'put(I)$intBuffer', [ints, 0x01020304]);
      expect(javaNioBuffer(vm, b).copyBytes(remaining: false), [
        0,
        4,
        3,
        2,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(javaNioBuffer(vm, b).position, 1);
      expect(javaNioBuffer(vm, ints).position, 1);
      call(byte, 'order($order)$byte', [b, endian(Endian.big)]);
      expect(call(intBuffer, 'get(I)I', [ints, 0]), 0x01020304);
      final floats = call(byte, 'asFloatBuffer()$floatBuffer', [b]);
      expect(call(floatBuffer, 'get(I)F', [floats, 0]), 0x04030201);
      expect(call(intBuffer, 'hasArray()Z', [ints]), 0);
    },
  );
  test(
    'Wrapped arrays remain bidirectionally aliased with original storage',
    () {
      final values = array('I', [0x12345678, -1, 3, 4]);
      final b = stat(intBuffer, 'wrap([I)$intBuffer', [values]);
      call(intBuffer, 'put(II)$intBuffer', [b, 1, 0x76543210]);
      expect(values.values[1], 0x76543210);
      values.values[2] = -99;
      expect(call(intBuffer, 'get(I)I', [b, 2]), -99);
      expect(call(intBuffer, 'array()[I', [b]), same(values));
      call(base, 'position(I)$base', [b, 1]);
      final slice = call(intBuffer, 'slice()$intBuffer', [b]);
      expect(call(base, 'arrayOffset()I', [slice]), 1);
      call(intBuffer, 'put(II)$intBuffer', [slice, 0, 8]);
      expect(values.values[1], 8);
      final raw = javaNioBuffer(vm, b).copyBytes();
      expect(raw.length, 12);
      expect(
        raw.sublist(0, 4),
        Endian.host == Endian.little ? [8, 0, 0, 0] : [0, 0, 0, 8],
      );
    },
  );
  test(
    'Position limit mark reset flip rewind clear and illegal transitions',
    () {
      final b = allocate(6);
      call(base, 'position(I)$base', [b, 2]);
      call(base, 'mark()$base', [b]);
      call(base, 'position(I)$base', [b, 4]);
      call(base, 'reset()$base', [b]);
      expect(javaNioBuffer(vm, b).position, 2);
      call(base, 'position(I)$base', [b, 1]);
      expect(
        () => call(base, 'reset()$base', [b]),
        throwsA(failure('nio/InvalidMarkException')),
      );
      call(base, 'position(I)$base', [b, 5]);
      call(base, 'limit(I)$base', [b, 3]);
      expect(javaNioBuffer(vm, b).position, 3);
      call(base, 'flip()$base', [b]);
      expect(
        [javaNioBuffer(vm, b).position, javaNioBuffer(vm, b).limit],
        [0, 3],
      );
      expect(
        () => call(base, 'position(I)$base', [b, 4]),
        throwsA(failure('lang/IllegalArgumentException')),
      );
      call(base, 'clear()$base', [b]);
      expect(
        [javaNioBuffer(vm, b).position, javaNioBuffer(vm, b).limit],
        [0, 6],
      );
    },
  );
  test('Bulk put/get are atomic on bounds failure and support overlap', () {
    final values = array('I', [1, 2, 3, 4]);
    final b = stat(intBuffer, 'wrap([I)$intBuffer', [values]);
    call(base, 'position(I)$base', [b, 1]);
    call(intBuffer, 'put([III)$intBuffer', [b, values, 0, 3]);
    expect(values.values, [1, 1, 2, 3]);
    call(base, 'clear()$base', [b]);
    call(intBuffer, 'get([III)$intBuffer', [b, values, 1, 3]);
    expect(values.values, [1, 1, 1, 2]);
    expect(
      () => call(intBuffer, 'put([I)$intBuffer', [
        b,
        array('I', [9, 9]),
      ]),
      throwsA(failure('nio/BufferOverflowException')),
    );
    expect(javaNioBuffer(vm, b).position, 3);
    expect(values.values, [1, 1, 1, 2]);
  });
  test(
    'Byte duplicate resets order, shares data; read-only views reject writes',
    () {
      final b = allocate(8);
      call(byte, 'order($order)$byte', [b, endian(Endian.little)]);
      final duplicate = call(byte, 'duplicate()$byte', [b]);
      expect(javaNioBuffer(vm, duplicate).order, Endian.big);
      call(byte, 'putInt(I)$byte', [duplicate, 0x12345678]);
      expect(call(byte, 'getInt(I)I', [b, 0]), 0x78563412);
      final ro = call(byte, 'asReadOnlyBuffer()$byte', [b]);
      expect(call(base, 'hasArray()Z', [ro]), 0);
      expect(
        () => call(byte, 'put(B)$byte', [ro, 2]),
        throwsA(failure('nio/ReadOnlyBufferException')),
      );
      expect(
        () => call(byte, 'array()[B', [ro]),
        throwsA(failure('nio/ReadOnlyBufferException')),
      );
      call(byte, 'put(IB)$byte', [b, 0, 99]);
      expect(call(byte, 'get(I)B', [ro, 0]), 99);
    },
  );
  test('Compact preserves remaining data and resets limit/mark', () {
    final b = stat(shortBuffer, 'wrap([S)$shortBuffer', [
      array('S', [1, 2, 3, 4, 5]),
    ]);
    call(base, 'position(I)$base', [b, 2]);
    call(base, 'limit(I)$base', [b, 4]);
    call(base, 'mark()$base', [b]);
    call(shortBuffer, 'compact()$shortBuffer', [b]);
    expect(vm.asArray(call(shortBuffer, 'array()[S', [b])).values, [
      3,
      4,
      3,
      4,
      5,
    ]);
    expect([javaNioBuffer(vm, b).position, javaNioBuffer(vm, b).limit], [2, 5]);
    expect(
      () => call(base, 'reset()$base', [b]),
      throwsA(failure('nio/InvalidMarkException')),
    );
  });
  test(
    '80 JVM oracle traces: offsets, orders, direct/heap and shared views',
    () {
      final cases = jsonDecode(
        File('test/dalvik/fixtures/nio.json').readAsStringSync(),
      ) as List;
      for (final row in cases) {
        final b = allocate(32, direct: row['direct'] as bool);
        call(byte, 'order($order)$byte', [
          b,
          endian(row['little'] == true ? Endian.little : Endian.big),
        ]);
        call(base, 'position(I)$base', [b, row['offset']]);
        final ints = call(byte, 'asIntBuffer()$intBuffer', [b]);
        final values = (row['values'] as List).cast<int>();
        for (var i = 0; i < values.length; i++) {
          call(intBuffer, 'put(II)$intBuffer', [ints, i, values[i]]);
        }
        expect(javaNioBuffer(vm, b).copyBytes(remaining: false), row['bytes']);
        final shorts = javaNioBuffer(
          vm,
          call(byte, 'asShortBuffer()$shortBuffer', [b]),
        );
        expect(List.generate(shorts.capacity, shorts.readRaw), row['shorts']);
        final floats = javaNioBuffer(
          vm,
          call(byte, 'asFloatBuffer()$floatBuffer', [b]),
        );
        expect(List.generate(floats.capacity, floats.readRaw), row['floats']);
      }
    },
  );
}
