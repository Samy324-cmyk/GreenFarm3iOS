import 'dart:io';
import 'dart:math' as math;

import 'numbers.dart';
import 'runtime.dart';

const _file = 'Ljava/io/File;';
const _input = 'Ljava/io/FileInputStream;';
const _output = 'Ljava/io/FileOutputStream;';

class JavaFilePath {
  JavaFilePath(String path) : path = _normalize(path);
  final String path;
  static String _normalize(String path) {
    path = path.replaceAll(RegExp('/+'), '/');
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}

class _OpenFile {
  _OpenFile(this.file);
  final RandomAccessFile file;
  bool closed = false;
  T run<T>(DalvikRuntime vm, T Function(RandomAccessFile) operation) {
    if (closed) vm.throwJava('Ljava/io/IOException;', 'Stream Closed');
    try {
      return operation(file);
    } on FileSystemException catch (error) {
      vm.throwJava('Ljava/io/IOException;', error.message);
    }
  }

  void close(DalvikRuntime vm) {
    if (closed) return;
    run(vm, (file) => file.closeSync());
    closed = true;
  }
}

/// Android media APIs receive an open descriptor, not its current cursor.
List<int> javaFileDescriptorBytes(DalvikRuntime vm, Object? descriptor) {
  final state = vm.object(descriptor).nativeValue as _OpenFile;
  return state.run(vm, (file) {
    final position = file.positionSync();
    try {
      file.setPositionSync(0);
      return file.readSync(file.lengthSync());
    } finally {
      file.setPositionSync(position);
    }
  });
}

/// Host directory is supplied by the iOS document-directory bridge at startup.
/// No Android path is silently mapped onto an unrelated host location.
void registerJavaFiles(DalvikRuntime vm, {required String workingDirectory}) {
  final base = workingDirectory.replaceAll('\\', '/');
  if (!Directory(base).isAbsolute) {
    throw ArgumentError('An absolute directory is required');
  }
  String path(Object? value) =>
      (vm.object(value).nativeValue as JavaFilePath).path;
  String absolute(Object? value) {
    final text = path(value);
    return File(text).isAbsolute
        ? text
        : text.isEmpty
        ? base
        : '$base/$text';
  }

  DalvikObject fileObject(String value) =>
      DalvikObject(_file, nativeValue: JavaFilePath(value));
  _OpenFile opened(Object? value) => vm.object(value).nativeValue as _OpenFile;
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  vm.registerExternalClass(
    _file,
    interfaces: ['Ljava/io/Serializable;', 'Ljava/lang/Comparable;'],
  );
  vm.registerExternalClass(_input, superclass: 'Ljava/io/InputStream;');
  vm.registerExternalClass(_output, superclass: 'Ljava/io/OutputStream;');
  vm.registerExternalClass('Ljava/io/FileDescriptor;');
  vm.registerExternalClass(
    'Ljava/io/FileNotFoundException;',
    superclass: 'Ljava/io/IOException;',
  );
  native(_file, '<init>(Ljava/lang/String;)V', (_, a) {
    vm.object(a[0]).nativeValue = JavaFilePath(vm.string(a[1]));
    return null;
  });
  native(_file, '<init>(Ljava/io/File;Ljava/lang/String;)V', (_, a) {
    final child = vm.string(a[2]);
    final parent = vm.isNull(a[1]) ? null : path(a[1]);
    vm.object(a[0]).nativeValue = JavaFilePath(
      parent == null
          ? child
          : parent.isEmpty
          ? '/$child'
          : child.isEmpty
          ? parent
          : '$parent/$child',
    );
    return null;
  });
  for (final member in ['getPath', 'toString']) {
    native(
      _file,
      '$member()Ljava/lang/String;',
      (_, a) => vm.newString(path(a[0])),
    );
  }
  native(
    _file,
    'getAbsolutePath()Ljava/lang/String;',
    (_, a) => vm.newString(absolute(a[0])),
  );
  native(
    _file,
    'getName()Ljava/lang/String;',
    (_, a) => vm.newString(path(a[0]).split('/').last),
  );
  String? parent(Object? value) {
    final text = path(value);
    final slash = text.lastIndexOf('/');
    return slash < 0 || text == '/'
        ? null
        : slash == 0
        ? '/'
        : text.substring(0, slash);
  }

  native(_file, 'getParent()Ljava/lang/String;', (_, a) {
    final result = parent(a[0]);
    return result == null ? null : vm.newString(result);
  });
  native(_file, 'getParentFile()Ljava/io/File;', (_, a) {
    final result = parent(a[0]);
    return result == null ? null : fileObject(result);
  });
  FileSystemEntityType entity(Object? value) => path(value).isEmpty
      ? FileSystemEntityType.notFound
      : FileSystemEntity.typeSync(absolute(value));
  native(
    _file,
    'exists()Z',
    (_, a) => entity(a[0]) != FileSystemEntityType.notFound ? 1 : 0,
  );
  native(
    _file,
    'isDirectory()Z',
    (_, a) => entity(a[0]) == FileSystemEntityType.directory ? 1 : 0,
  );
  native(
    _file,
    'isFile()Z',
    (_, a) => entity(a[0]) == FileSystemEntityType.file ? 1 : 0,
  );
  native(_file, 'length()J', (_, a) {
    try {
      return File(absolute(a[0])).lengthSync();
    } on FileSystemException {
      return 0;
    }
  });
  native(_file, 'createNewFile()Z', (_, a) {
    if (path(a[0]).isEmpty) {
      vm.throwJava('Ljava/io/IOException;', 'Empty file path');
    }
    final file = File(absolute(a[0]));
    if (file.existsSync()) return 0;
    try {
      file.createSync(exclusive: true);
      return 1;
    } on FileSystemException catch (error) {
      if (file.existsSync()) return 0;
      vm.throwJava('Ljava/io/IOException;', error.message);
    }
  });
  for (final recursive in [false, true]) {
    native(_file, '${recursive ? 'mkdirs' : 'mkdir'}()Z', (_, a) {
      if (path(a[0]).isEmpty) return 0;
      final target = Directory(absolute(a[0]));
      if (target.existsSync()) return 0;
      try {
        target.createSync(recursive: recursive);
        return 1;
      } on FileSystemException {
        return 0;
      }
    });
  }
  native(_file, 'delete()Z', (_, a) {
    if (path(a[0]).isEmpty) return 0;
    final target = absolute(a[0]);
    try {
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.notFound) return 0;
      if (type == FileSystemEntityType.directory) {
        Directory(target).deleteSync();
      } else if (type == FileSystemEntityType.link) {
        Link(target).deleteSync();
      } else {
        File(target).deleteSync();
      }
      return 1;
    } on FileSystemException {
      return 0;
    }
  });
  List<String>? listing(Object? value) {
    if (path(value).isEmpty) return null;
    try {
      return Directory(absolute(value))
          .listSync()
          .map((e) => e.path.replaceAll('\\', '/').split('/').last)
          .toList();
    } on FileSystemException {
      return null;
    }
  }

  native(_file, 'list()[Ljava/lang/String;', (_, a) {
    final names = listing(a[0]);
    if (names == null) return null;
    final array = vm.array('[Ljava/lang/String;', names.length);
    for (var i = 0; i < names.length; i++) {
      array.values[i] = vm.newString(names[i]);
    }
    return array;
  });
  native(_file, 'listFiles()[Ljava/io/File;', (_, a) {
    final names = listing(a[0]);
    if (names == null) return null;
    final array = vm.array('[Ljava/io/File;', names.length);
    for (var i = 0; i < names.length; i++) {
      array.values[i] = fileObject('${path(a[0])}/${names[i]}');
    }
    return array;
  });
  void open(List<Object?> args, bool output, bool fromString, bool append) {
    final value = fromString ? fileObject(vm.string(args[1])) : args[1];
    try {
      if (path(value).isEmpty) {
        vm.throwJava('Ljava/io/FileNotFoundException;', 'Empty file path');
      }
      final handle = File(absolute(value)).openSync(
        mode: output
            ? (append ? FileMode.append : FileMode.write)
            : FileMode.read,
      );
      vm.object(args[0]).nativeValue = _OpenFile(handle);
    } on FileSystemException catch (error) {
      vm.throwJava('Ljava/io/FileNotFoundException;', error.message);
    }
  }

  for (final owner in [_input, _output]) {
    for (final fromString in [false, true]) {
      final argument = fromString ? 'Ljava/lang/String;' : _file;
      native(owner, '<init>($argument)V', (_, a) {
        open(a, owner == _output, fromString, false);
        return null;
      });
      if (owner == _output) {
        native(owner, '<init>(${argument}Z)V', (_, a) {
          open(a, true, fromString, a[2] != 0);
          return null;
        });
      }
    }
    native(owner, 'close()V', (_, a) {
      opened(a[0]).close(vm);
      return null;
    });
  }
  native(
    _input,
    'read()I',
    (_, a) => opened(a[0]).run(vm, (f) => f.readByteSync()),
  );
  void bounds(DalvikArray array, int offset, int length) {
    if (offset < 0 || length < 0 || offset > array.values.length - length) {
      vm.throwJava('Ljava/lang/IndexOutOfBoundsException;');
    }
  }

  native(_input, 'read([BII)I', (_, a) {
    final array = vm.asArray(a[1]), offset = a[2] as int, length = a[3] as int;
    bounds(array, offset, length);
    return opened(a[0]).run(vm, (f) {
      if (length == 0) return 0;
      final bytes = f.readSync(length);
      if (bytes.isEmpty) return -1;
      for (var i = 0; i < bytes.length; i++) {
        array.values[offset + i] = bytes[i].toSigned(8);
      }
      return bytes.length;
    });
  });
  native(
    _input,
    'available()I',
    (_, a) => opened(a[0]).run(
      vm,
      (f) =>
          math.max(0, math.min(0x7fffffff, f.lengthSync() - f.positionSync())),
    ),
  );
  native(
    _input,
    'skip(J)J',
    (_, a) => opened(a[0]).run(vm, (f) {
      final count = JBits.wide(a, 1), position = f.positionSync();
      final next = position + count;
      if (next < 0) vm.throwJava('Ljava/io/IOException;', 'Invalid seek');
      f.setPositionSync(next);
      return count;
    }),
  );
  native(
    _input,
    'getFD()Ljava/io/FileDescriptor;',
    (_, a) =>
        DalvikObject('Ljava/io/FileDescriptor;', nativeValue: opened(a[0])),
  );
  native(
    'Ljava/io/FileDescriptor;',
    'valid()Z',
    (_, a) => (vm.object(a[0]).nativeValue as _OpenFile).closed ? 0 : 1,
  );
  native(_output, 'write(I)V', (_, a) {
    opened(a[0]).run(vm, (f) => f.writeByteSync((a[1] as int) & 255));
    return null;
  });
  native(_output, 'write([BII)V', (_, a) {
    final array = vm.asArray(a[1]), offset = a[2] as int, length = a[3] as int;
    bounds(array, offset, length);
    opened(a[0]).run(
      vm,
      (f) => f.writeFromSync(
        List<int>.generate(
          length,
          (i) => (array.values[offset + i] as int) & 255,
        ),
      ),
    );
    return null;
  });
  native(_output, 'flush()V', (_, a) {
    opened(a[0]).run(vm, (f) => f.flushSync());
    return null;
  });
}
