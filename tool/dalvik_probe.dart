import 'dart:io';

import '../lib/engine/dalvik/runtime.dart';
import '../lib/engine/dalvik/java_core.dart';
import '../lib/engine/dalvik/java_io.dart';
import '../lib/engine/dalvik/java_collections.dart';
import '../lib/generated/program.dart';

// Integration diagnostic, not an app entry point or substitute game.
void main(List<String> args) {
  final vm = DalvikRuntime()
    ..instructionLimit = 10000000
    ..wallClockMillis = (() => DateTime.now().millisecondsSinceEpoch)
    ..randomSeedSource = (() => DateTime.now().microsecondsSinceEpoch)
    ..defaultLocaleLanguage = 'es';
  final stopwatch = Stopwatch()..start();
  vm.monotonicMillis = () => stopwatch.elapsedMilliseconds;
  registerJavaCore(vm);
  registerJavaIo(vm);
  registerJavaCollections(vm);
  registerOriginalProgram(vm);
  final target = args.isEmpty
      ? 'Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/cGame;'
      : args.first;
  try {
    vm.initialize(target);
    stdout.writeln('Class initialized: $target');
    stdout.writeln('Executed instructions: ${vm.executedInstructions}');
  } catch (error, trace) {
    stderr.writeln(error);
    stderr.writeln(vm.lastFailureStack.join('\n'));
    stderr.writeln(trace.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
