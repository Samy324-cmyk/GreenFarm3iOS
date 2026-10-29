import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_files.dart';
import 'package:green_farm_port/engine/dalvik/java_io.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  late Directory directory;
  const file = 'Ljava/io/File;';
  const input = 'Ljava/io/FileInputStream;';
  const output = 'Ljava/io/FileOutputStream;';
  DalvikObject construct(String owner, String descriptor, List<Object?> args) {
    final result = vm.allocate(owner);
    vm.call('$owner-><init>$descriptor', [result, ...args], kind: 'direct');
    return result;
  }

  Object? call(String owner, String member, List<Object?> args) =>
      vm.call('$owner->$member', args, kind: 'virtual');
  DalvikObject path(String name) =>
      construct(file, '(Ljava/lang/String;)V', [vm.newString(name)]);
  setUp(() {
    final root = Directory('.dart_tool/file-bridge-tests')
      ..createSync(recursive: true);
    directory = root.createTempSync('case-');
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaIo(vm);
    registerJavaFiles(vm, workingDirectory: directory.absolute.path);
    addTearDown(() {
      final target = directory.resolveSymbolicLinksSync();
      final parent = root.resolveSymbolicLinksSync();
      if (!target.startsWith('$parent${Platform.pathSeparator}'))
        throw StateError('Cleanup escaped test root');
      Directory(target).deleteSync(recursive: true);
    });
  });

  test('persistent signed bytes, append, skip, EOF and closed streams', () {
    final target = path('save.dat');
    var out = construct(output, '(Ljava/io/File;)V', [target]);
    final data = vm.array('[B', 4)..values.setAll(0, [0, -1, -128, 127]);
    call(output, 'write([B)V', [out, data]);
    call(output, 'close()V', [out]);
    expect(call(file, 'length()J', [target]), 4);
    out = construct(output, '(Ljava/io/File;Z)V', [target, 1]);
    call(output, 'write(I)V', [out, 257]);
    call(output, 'close()V', [out]);
    final source = construct(input, '(Ljava/io/File;)V', [target]);
    expect(call(input, 'available()I', [source]), 5);
    expect(call(input, 'read()I', [source]), 0);
    expect(call(input, 'skip(J)J', [source, 1, 0]), 1);
    final read = vm.array('[B', 8);
    expect(call(input, 'read([BII)I', [source, read, 2, 6]), 3);
    expect(read.values, [0, 0, -128, 127, 1, 0, 0, 0]);
    expect(call(input, 'read()I', [source]), -1);
    final descriptor = call(input, 'getFD()Ljava/io/FileDescriptor;', [source]);
    expect(call('Ljava/io/FileDescriptor;', 'valid()Z', [descriptor]), 1);
    call(input, 'close()V', [source]);
    call(input, 'close()V', [source]);
    expect(call('Ljava/io/FileDescriptor;', 'valid()Z', [descriptor]), 0);
    expect(
      () => call(input, 'read()I', [source]),
      throwsA(isA<DalvikThrown>()),
    );
  });

  test('directory creation and failed nonempty deletion', () {
    final folder = path('one/two');
    expect(call(file, 'mkdir()Z', [folder]), 0);
    expect(call(file, 'mkdirs()Z', [folder]), 1);
    expect(call(file, 'mkdirs()Z', [folder]), 0);
    final child = construct(file, '(Ljava/io/File;Ljava/lang/String;)V', [
      folder,
      vm.newString('record'),
    ]);
    expect(call(file, 'createNewFile()Z', [child]), 1);
    expect(call(file, 'createNewFile()Z', [child]), 0);
    expect(call(file, 'delete()Z', [folder]), 0);
    final list =
        call(file, 'list()[Ljava/lang/String;', [folder]) as DalvikArray;
    expect(list.values.map(vm.string), ['record']);
    expect(call(file, 'delete()Z', [child]), 1);
    expect(call(file, 'delete()Z', [folder]), 1);
  });

  test('empty File path never operates on the working directory', () {
    final empty = path('');
    expect(call(file, 'exists()Z', [empty]), 0);
    expect(call(file, 'mkdirs()Z', [empty]), 0);
    expect(call(file, 'delete()Z', [empty]), 0);
    expect(call(file, 'list()[Ljava/lang/String;', [empty]), isNull);
    expect(directory.existsSync(), isTrue);
    expect(
      () => call(file, 'createNewFile()Z', [empty]),
      throwsA(isA<DalvikThrown>()),
    );
  });

  test('missing file opens throw FileNotFoundException and preserve disk', () {
    final target = path('missing.dat');
    expect(
      () => construct(input, '(Ljava/io/File;)V', [target]),
      throwsA(
        isA<DalvikThrown>().having(
          (e) => e.object.className,
          'type',
          'Ljava/io/FileNotFoundException;',
        ),
      ),
    );
    expect(call(file, 'exists()Z', [target]), 0);
    expect(call(file, 'length()J', [target]), 0);
  });
}
