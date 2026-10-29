import 'dart:convert';
import 'dart:io';

import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main(List<String> args) {
  final data =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final vm = DalvikRuntime();
  registerJavaCore(vm);
  for (final type in ['float', 'double']) {
    var mismatch = 0;
    for (final entry in data[type] as List) {
      final bits = BigInt.parse(
        entry[0] as String,
        radix: 16,
      ).toSigned(64).toInt();
      final key = type == 'float'
          ? 'Ljava/lang/Float;->toString(F)Ljava/lang/String;'
          : 'Ljava/lang/Double;->toString(D)Ljava/lang/String;';
      final words = type == 'float'
          ? <Object?>[bits]
          : <Object?>[bits.toSigned(32), (bits >> 32).toSigned(32)];
      final actual = vm.string(vm.call(key, words, kind: 'static'));
      if (actual != entry[1]) {
        if (mismatch < 15) {
          stdout.writeln(
            '$type ${entry[0]} expected ${entry[1]} actual $actual',
          );
        }
        mismatch++;
      }
    }
    stdout.writeln(
      '$type mismatches $mismatch / ${(data[type] as List).length}',
    );
  }
}
