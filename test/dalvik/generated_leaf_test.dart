import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0368.dart';

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/compat/dex_leaf.json')
        .readAsStringSync()
        .replaceFirst('\uFEFF', ''),
  ) as List<dynamic>;
  final vm = DalvikRuntime()..instructionLimit = 30000000;
  registerClass368(vm);
  const owner = 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/GLLib;';
  for (final group in <String, List<dynamic>>{
    for (final vector in vectors) (vector as Map)['method'] as String: [],
  }.entries) {
    test('original DEX ${group.key} matches compiled Java', () {
      for (final data in vectors.where((item) => item['method'] == group.key)) {
        final types = data['parameters'] as List<dynamic>;
        final args = data['args'] as List<dynamic>;
        final registers = <Object?>[];
        final objects = <Object?>[];
        for (var index = 0; index < types.length; index++) {
          final type = types[index] as String;
          final value = args[index];
          if (type.startsWith('[') && value != null) {
            final values = value as List<dynamic>;
            final array = vm.array(type, values.length);
            for (var i = 0; i < values.length; i++) {
              vm.arrayPut(array, i, values[i]);
            }
            objects.add(array);
            registers.add(array);
          } else {
            objects.add(value);
            if (type == 'J') {
              registers.add((value as int).toSigned(32));
              registers.add((value >> 32).toSigned(32));
            } else {
              registers.add(value);
            }
          }
        }
        final result = vm.methods['$owner->${group.key}']!.body!(vm, registers);
        expect(
          result is DalvikArray ? result.values : result,
          data['result'],
          reason: 'args=${data['args']}',
        );
        expect(
          objects
              .map((item) => item is DalvikArray ? item.values : item)
              .toList(),
          data['after'],
          reason: 'mutated arrays',
        );
      }
    });
  }
}
