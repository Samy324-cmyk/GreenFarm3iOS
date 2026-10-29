import 'dart:math' as math;
import 'dart:typed_data';

import '../compat/java_numbers.dart';
import '../compat/java_random.dart';
import 'cooperative.dart';
import 'numbers.dart';
import 'java_decimal.dart';
import 'java_unicode_data.dart';
import 'java_parse_decimal.dart';
import 'runtime.dart';

const _object = 'Ljava/lang/Object;';
const _string = 'Ljava/lang/String;';

final class _Builder {
  _Builder([this.text = '']);
  String text;
}

int _doubleBits(double value) => (ByteData(
  8,
)..setFloat64(0, value, Endian.little)).getInt64(0, Endian.little);
int _int(Object? value) => (value as int).toSigned(32);
int _bool(bool value) => value ? 1 : 0;

String _trim(String value) {
  var first = 0, last = value.length;
  while (first < last && value.codeUnitAt(first) <= 32) {
    first++;
  }
  while (last > first && value.codeUnitAt(last - 1) <= 32) {
    last--;
  }
  return value.substring(first, last);
}

void _bounds(
  DalvikRuntime vm,
  int start,
  int end,
  int size, {
  bool string = false,
}) {
  if (start < 0 || end < start || end > size) {
    vm.throwJava(
      string
          ? 'Ljava/lang/StringIndexOutOfBoundsException;'
          : 'Ljava/lang/IndexOutOfBoundsException;',
      '$start..$end of $size',
    );
  }
}

String _className(String descriptor) {
  const primitives = {
    'V': 'void',
    'Z': 'boolean',
    'B': 'byte',
    'C': 'char',
    'S': 'short',
    'I': 'int',
    'J': 'long',
    'F': 'float',
    'D': 'double',
  };
  if (primitives.containsKey(descriptor)) return primitives[descriptor]!;
  if (descriptor.startsWith('L')) {
    return descriptor.substring(1, descriptor.length - 1).replaceAll('/', '.');
  }
  return descriptor.replaceAll('/', '.');
}

int _stringHash(String value) {
  var h = 0;
  for (final c in value.codeUnits) {
    h = (31 * h + c).toSigned(32);
  }
  return h;
}

/// Registers Java value semantics actually required by the original DEX.
/// Platform/thread/network operations remain explicit missing bridges.
void registerJavaCore(DalvikRuntime vm) {
  void cls(
    String name, {
    String? parent = _object,
    List<String> interfaces = const [],
  }) => vm.registerExternalClass(
    name,
    superclass: parent,
    interfaces: interfaces,
  );
  void native(String owner, String method, DalvikBody body) =>
      vm.registerNative('$owner->$method', body);
  cls(_object, parent: null);
  for (final name in [
    'Ljava/io/Serializable;',
    'Ljava/lang/Cloneable;',
    'Ljava/lang/Comparable;',
    'Ljava/lang/CharSequence;',
    'Ljava/lang/Runnable;',
  ]) {
    cls(name);
  }
  cls(
    _string,
    interfaces: [
      'Ljava/io/Serializable;',
      'Ljava/lang/Comparable;',
      'Ljava/lang/CharSequence;',
    ],
  );
  for (final name in ['StringBuilder', 'StringBuffer']) {
    cls(
      'Ljava/lang/$name;',
      interfaces: ['Ljava/lang/CharSequence;', 'Ljava/io/Serializable;'],
    );
  }
  for (final name in ['Class', 'Package', 'Math', 'System']) {
    cls('Ljava/lang/$name;');
  }
  cls('Ljava/lang/Number;', interfaces: ['Ljava/io/Serializable;']);
  for (final name in ['Byte', 'Short', 'Integer', 'Long', 'Float', 'Double']) {
    cls(
      'Ljava/lang/$name;',
      parent: 'Ljava/lang/Number;',
      interfaces: ['Ljava/lang/Comparable;'],
    );
  }
  for (final name in ['Boolean', 'Character']) {
    cls(
      'Ljava/lang/$name;',
      interfaces: ['Ljava/io/Serializable;', 'Ljava/lang/Comparable;'],
    );
  }
  cls('Ljava/util/Random;', interfaces: ['Ljava/io/Serializable;']);
  cls('Ljava/lang/Throwable;', interfaces: ['Ljava/io/Serializable;']);
  const hierarchy = {
    'Error': 'Throwable',
    'Exception': 'Throwable',
    'RuntimeException': 'Exception',
    'IllegalArgumentException': 'RuntimeException',
    'IllegalStateException': 'RuntimeException',
    'NullPointerException': 'RuntimeException',
    'ArithmeticException': 'RuntimeException',
    'IndexOutOfBoundsException': 'RuntimeException',
    'ArrayIndexOutOfBoundsException': 'IndexOutOfBoundsException',
    'StringIndexOutOfBoundsException': 'IndexOutOfBoundsException',
    'NegativeArraySizeException': 'RuntimeException',
    'ArrayStoreException': 'RuntimeException',
    'ClassCastException': 'RuntimeException',
    'IllegalMonitorStateException': 'RuntimeException',
    'NumberFormatException': 'IllegalArgumentException',
    'UnsupportedOperationException': 'RuntimeException',
    'InterruptedException': 'Exception',
    'ClassNotFoundException': 'Exception',
    'CloneNotSupportedException': 'Exception',
    'LinkageError': 'Error',
    'NoClassDefFoundError': 'LinkageError',
    'ExceptionInInitializerError': 'LinkageError',
    'AssertionError': 'Error',
    'OutOfMemoryError': 'Error',
  };
  for (final e in hierarchy.entries) {
    cls('Ljava/lang/${e.key};', parent: 'Ljava/lang/${e.value};');
  }
  cls('Ljava/io/IOException;', parent: 'Ljava/lang/Exception;');
  cls(
    'Ljava/io/UnsupportedEncodingException;',
    parent: 'Ljava/io/IOException;',
  );

  final identities = Map<DalvikObject, int>.identity();
  var nextIdentity = 1;
  int identity(Object? value) =>
      identities.putIfAbsent(vm.object(value), () => nextIdentity++);
  String objectText(Object? value) {
    if (vm.isNull(value)) return 'null';
    final result = vm.call('$_object->toString()Ljava/lang/String;', [
      value,
    ], kind: 'virtual');
    return vm.string(result);
  }

  native(_object, '<init>()V', (_, a) {
    vm.object(a[0]);
    return null;
  });
  native(
    _object,
    'equals(Ljava/lang/Object;)Z',
    (_, a) => _bool(identical(vm.object(a[0]), a[1])),
  );
  native(_object, 'hashCode()I', (_, a) => identity(a[0]));
  native(
    _object,
    'getClass()Ljava/lang/Class;',
    (_, a) => vm.typeObject(vm.object(a[0]).className),
  );
  native(
    _object,
    'toString()Ljava/lang/String;',
    (_, a) => vm.newString(
      '${_className(vm.object(a[0]).className)}@${(vm.call('$_object->hashCode()I', [a[0]], kind: 'virtual') as int).toUnsigned(32).toRadixString(16)}',
    ),
  );

  for (final name in ['Throwable', ...hierarchy.keys]) {
    final owner = 'Ljava/lang/$name;';
    native(owner, '<init>()V', (_, a) {
      final error = vm.object(a[0]);
      error.nativeValue = null;
      vm.throwableTraces[error] = _exceptionFrames(vm);
      return null;
    });
    native(owner, '<init>(Ljava/lang/String;)V', (_, a) {
      final error = vm.object(a[0]);
      error.nativeValue = vm.isNull(a[1]) ? null : vm.string(a[1]);
      vm.throwableTraces[error] = _exceptionFrames(vm);
      return null;
    });
  }
  native('Ljava/lang/Throwable;', 'getMessage()Ljava/lang/String;', (_, a) {
    final m = vm.object(a[0]).nativeValue;
    return m == null ? null : vm.newString(m as String);
  });
  native('Ljava/lang/Throwable;', 'printStackTrace()V', (_, a) {
    final error = vm.object(a[0]);
    final text =
        '${_className(error.className)}${error.nativeValue == null ? '' : ': ${error.nativeValue}'}';
    final frames = vm.throwableTraces[error] ?? const <String>[];
    vm.logDiagnostic([text, ...frames.map((f) => '\tat $f')].join('\n'));
    return null;
  });
  native('Ljava/lang/Throwable;', 'toString()Ljava/lang/String;', (_, a) {
    final o = vm.object(a[0]);
    return vm.newString(
      '${_className(o.className)}${o.nativeValue == null ? '' : ': ${o.nativeValue}'}',
    );
  });

  native(
    'Ljava/lang/Class;',
    'getName()Ljava/lang/String;',
    (_, a) => vm.newString(_className(vm.object(a[0]).nativeValue as String)),
  );
  native('Ljava/lang/Class;', 'forName(Ljava/lang/String;)Ljava/lang/Class;', (
    _,
    a,
  ) {
    final name = vm.string(a[0]);
    if (name.contains('/') || name.isEmpty) {
      vm.throwJava('Ljava/lang/ClassNotFoundException;', name);
    }
    final descriptor = name.startsWith('[')
        ? name.replaceAll('.', '/')
        : 'L${name.replaceAll('.', '/')};';
    var component = descriptor;
    while (component.startsWith('[')) {
      component = component.substring(1);
    }
    final primitive = component.length == 1 && 'ZBCSIJFD'.contains(component);
    if (!primitive && !vm.classes.containsKey(component)) {
      if (vm.availableClassNames.contains(component)) {
        throw MissingDalvikBridge(
          'Class.forName available but unported $component',
        );
      }
      vm.throwJava('Ljava/lang/ClassNotFoundException;', name);
    }
    if (descriptor.startsWith('[')) return vm.typeObject(descriptor);
    return dalvikThen(
      () {
        vm.initialize(descriptor);
        return null;
      },
      (_) => vm.typeObject(descriptor),
      methodKey: 'Class.forName $descriptor',
    );
  });
  native(
    'Ljava/lang/Class;',
    'isArray()Z',
    (_, a) => _bool((vm.object(a[0]).nativeValue as String).startsWith('[')),
  );
  native(
    'Ljava/lang/Class;',
    'isPrimitive()Z',
    (_, a) => _bool((vm.object(a[0]).nativeValue as String).length == 1),
  );
  native('Ljava/lang/Class;', 'isAssignableFrom(Ljava/lang/Class;)Z', (_, a) {
    final actual = vm.object(a[1]).nativeValue as String;
    final expected = vm.object(a[0]).nativeValue as String;
    return _bool(
      actual.length == 1 || expected.length == 1
          ? actual == expected
          : vm.assignable(actual, expected),
    );
  });
  native(
    'Ljava/lang/Class;',
    'isInstance(Ljava/lang/Object;)Z',
    (_, a) => _bool(vm.instanceOf(a[1], vm.object(a[0]).nativeValue as String)),
  );
  native('Ljava/lang/Class;', 'getComponentType()Ljava/lang/Class;', (_, a) {
    final d = vm.object(a[0]).nativeValue as String;
    return d.startsWith('[') ? vm.typeObject(d.substring(1)) : null;
  });
  native('Ljava/lang/Class;', 'getSuperclass()Ljava/lang/Class;', (_, a) {
    final d = vm.object(a[0]).nativeValue as String;
    final p = d.startsWith('[') ? _object : vm.classes[d]?.superclass;
    return p == null ? null : vm.typeObject(p);
  });

  _registerStrings(vm, native, objectText);
  _registerBuilders(vm, native, objectText);
  _registerNumbers(vm, native);
  _registerSystem(vm, native, identity);
  _registerLocaleAndEnum(vm, native);
  vm.registerExternalClass('Ljava/lang/reflect/Array;');
  native(
    'Ljava/lang/reflect/Array;',
    'newInstance(Ljava/lang/Class;[I)Ljava/lang/Object;',
    (_, a) {
      final component = vm.object(a[0]).nativeValue as String;
      final dims = vm.asArray(a[1]).values.cast<int>();
      final existing = component.length - component.replaceAll('[', '').length;
      if (component == 'V' || dims.isEmpty || dims.length + existing > 255) {
        vm.throwJava('Ljava/lang/IllegalArgumentException;');
      }
      if (dims.any((v) => v < 0)) {
        vm.throwJava('Ljava/lang/NegativeArraySizeException;');
      }
      DalvikArray create(int i) {
        final array = vm.array('${'[' * (dims.length - i)}$component', dims[i]);
        if (i + 1 < dims.length) {
          for (var j = 0; j < dims[i]; j++) {
            array.values[j] = create(i + 1);
          }
        }
        return array;
      }

      return create(0);
    },
  );
}

List<String> _exceptionFrames(DalvikRuntime vm) =>
    vm.callStack.reversed.skipWhile((key) {
      final at = key.indexOf('->');
      return at > 0 &&
          key.substring(at).startsWith('-><init>') &&
          vm.assignable(key.substring(0, at), 'Ljava/lang/Throwable;');
    }).toList();

typedef _Register = void Function(String owner, String member, DalvikBody body);

void _registerStrings(
  DalvikRuntime vm,
  _Register native,
  String Function(Object?) objectText,
) {
  String text(Object? value) => vm.string(value);
  String sequence(Object? value) {
    final o = vm.object(value);
    if (o.nativeValue is _Builder) return (o.nativeValue as _Builder).text;
    return text(value);
  }

  DalvikObject result(String s) => vm.newString(s);
  native(_string, '<init>()V', (_, a) {
    vm.object(a[0]).nativeValue = '';
    return null;
  });
  native(_string, '<init>(Ljava/lang/String;)V', (_, a) {
    vm.object(a[0]).nativeValue = text(a[1]);
    return null;
  });
  for (final sub in [false, true]) {
    native(_string, sub ? '<init>([CII)V' : '<init>([C)V', (_, a) {
      final data = vm.asArray(a[1]);
      final start = sub ? _int(a[2]) : 0;
      final count = sub ? _int(a[3]) : data.values.length;
      _bounds(vm, start, start + count, data.values.length);
      vm.object(a[0]).nativeValue = String.fromCharCodes(
        data.values.sublist(start, start + count).cast<int>(),
      );
      return null;
    });
    for (final charset in [false, true]) {
      final signature =
          '<init>([B${sub ? 'II' : ''}${charset ? 'Ljava/lang/String;' : ''})V';
      native(_string, signature, (_, a) {
        final data = vm.asArray(a[1]);
        final start = sub ? _int(a[2]) : 0;
        final count = sub ? _int(a[3]) : data.values.length;
        _bounds(vm, start, start + count, data.values.length);
        final name = charset ? text(a[sub ? 4 : 2]) : 'UTF-8';
        vm.object(a[0]).nativeValue = _decode(
          vm,
          Uint8List.fromList(
            data.values.sublist(start, start + count).cast<int>(),
          ),
          name,
        );
        return null;
      });
    }
  }
  native(_string, 'length()I', (_, a) => text(a[0]).length);
  native(_string, 'isEmpty()Z', (_, a) => _bool(text(a[0]).isEmpty));
  native(_string, 'toString()Ljava/lang/String;', (_, a) => a[0]);
  native(
    _string,
    'intern()Ljava/lang/String;',
    (_, a) => vm.intern(text(a[0])),
  );
  native(_string, 'hashCode()I', (_, a) => _stringHash(text(a[0])));
  native(
    _string,
    'equals(Ljava/lang/Object;)Z',
    (_, a) => _bool(
      a[1] is DalvikObject &&
          (a[1] as DalvikObject).className == _string &&
          text(a[0]) == text(a[1]),
    ),
  );
  native(_string, 'charAt(I)C', (_, a) {
    final s = text(a[0]), i = _int(a[1]);
    _bounds(vm, i, i + 1, s.length, string: true);
    return s.codeUnitAt(i);
  });
  for (final second in [false, true]) {
    native(
      _string,
      second
          ? 'substring(II)Ljava/lang/String;'
          : 'substring(I)Ljava/lang/String;',
      (_, a) {
        final s = text(a[0]),
            start = _int(a[1]),
            end = second ? _int(a[2]) : s.length;
        _bounds(vm, start, end, s.length, string: true);
        return start == 0 && end == s.length
            ? a[0]
            : result(s.substring(start, end));
      },
    );
  }
  native(_string, 'trim()Ljava/lang/String;', (_, a) {
    final s = text(a[0]), trimmed = _trim(s);
    return s == trimmed ? a[0] : result(trimmed);
  });
  native(_string, 'concat(Ljava/lang/String;)Ljava/lang/String;', (_, a) {
    final other = text(a[1]);
    return other.isEmpty ? a[0] : result(text(a[0]) + other);
  });
  native(
    _string,
    'contains(Ljava/lang/CharSequence;)Z',
    (_, a) => _bool(text(a[0]).contains(sequence(a[1]))),
  );
  native(
    _string,
    'startsWith(Ljava/lang/String;)Z',
    (_, a) => _bool(text(a[0]).startsWith(text(a[1]))),
  );
  native(
    _string,
    'endsWith(Ljava/lang/String;)Z',
    (_, a) => _bool(text(a[0]).endsWith(text(a[1]))),
  );
  for (final withStart in [false, true]) {
    for (final char in [false, true]) {
      for (final last in [false, true]) {
        final signature =
            '${last ? 'lastIndexOf' : 'indexOf'}(${char ? 'I' : 'Ljava/lang/String;'}${withStart ? 'I' : ''})I';
        native(_string, signature, (_, a) {
          final s = text(a[0]);
          String needle;
          if (char) {
            final c = _int(a[1]);
            if (c < 0 || c > 0x10ffff) return -1;
            needle = String.fromCharCode(c);
          } else {
            needle = text(a[1]);
          }
          var start = withStart
              ? _int(a[2])
              : last
              ? s.length
              : 0;
          if (last) {
            if (start < 0) return -1;
            start = math.min(start, s.length);
            return s.lastIndexOf(needle, start);
          }
          start = math.max(0, start);
          if (start > s.length) return needle.isEmpty ? s.length : -1;
          return s.indexOf(needle, start);
        });
      }
    }
  }
  native(
    _string,
    'compareTo(Ljava/lang/String;)I',
    (_, a) => _compare(text(a[0]), text(a[1])),
  );
  native(
    _string,
    'equalsIgnoreCase(Ljava/lang/String;)Z',
    (_, a) => vm.isNull(a[1])
        ? 0
        : _bool(_compareIgnoreCase(text(a[0]), text(a[1])) == 0),
  );
  native(
    _string,
    'compareToIgnoreCase(Ljava/lang/String;)I',
    (_, a) => _compareIgnoreCase(text(a[0]), text(a[1])),
  );
  native(_string, 'replace(CC)Ljava/lang/String;', (_, a) {
    final s = text(a[0]),
        from = String.fromCharCode(_int(a[1]) & 65535),
        to = String.fromCharCode(_int(a[2]) & 65535);
    return from == to || !s.contains(from)
        ? a[0]
        : result(s.replaceAll(from, to));
  });
  native(
    _string,
    'replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;',
    (_, a) => result(text(a[0]).replaceAll(sequence(a[1]), sequence(a[2]))),
  );
  native(_string, 'toCharArray()[C', (_, a) {
    final s = text(a[0]);
    return vm.array('[C', s.length)..values.setAll(0, s.codeUnits);
  });
  native(_string, 'getChars(II[CI)V', (_, a) {
    final s = text(a[0]), start = _int(a[1]), end = _int(a[2]);
    _bounds(vm, start, end, s.length, string: true);
    final dst = vm.asArray(a[3]), at = _int(a[4]);
    _bounds(vm, at, at + end - start, dst.values.length);
    dst.values.setRange(at, at + end - start, s.codeUnits, start);
    return null;
  });
  for (final charset in [false, true]) {
    native(
      _string,
      charset ? 'getBytes(Ljava/lang/String;)[B' : 'getBytes()[B',
      (_, a) {
        final b = _encode(vm, text(a[0]), charset ? text(a[1]) : 'UTF-8');
        return vm.array('[B', b.length)
          ..values.setAll(0, b.map((v) => v.toSigned(8)));
      },
    );
  }
  for (final type in [
    'I',
    'J',
    'C',
    'Z',
    'F',
    'D',
    'Ljava/lang/Object;',
    '[C',
  ]) {
    native(_string, 'valueOf($type)Ljava/lang/String;', (_, a) {
      final s = switch (type) {
        'I' => _int(a[0]).toString(),
        'J' => JBits.wide(a, 0).toString(),
        'C' => String.fromCharCode(_int(a[0]) & 65535),
        'Z' => _int(a[0]) == 0 ? 'false' : 'true',
        'F' => _floating(JBits.float(a, 0), true),
        'D' => _floating(JBits.doubleValue(a, 0), false),
        '[C' => String.fromCharCodes(vm.asArray(a[0]).values.cast<int>()),
        _ => objectText(a[0]),
      };
      return result(s);
    });
  }
  for (final upper in [false, true]) {
    for (final explicit in [false, true]) {
      native(
        _string,
        'to${upper ? 'Upper' : 'Lower'}Case(${explicit ? 'Ljava/util/Locale;' : ''})Ljava/lang/String;',
        (_, a) {
          final s = text(a[0]);
          final language = explicit
              ? (vm.object(a[1]).nativeValue as _LocaleValue).language
              : vm.defaultLocaleLanguage;
          if (language == null) {
            throw MissingDalvikBridge('default locale language');
          }
          final mapped = _caseText(s, language, upper);
          return mapped == s ? a[0] : result(mapped);
        },
      );
    }
  }
}

int _compare(String a, String b) {
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    final d = a.codeUnitAt(i) - b.codeUnitAt(i);
    if (d != 0) return d;
  }
  return a.length - b.length;
}

int _foldUnit(int unit) {
  final upper = (javaUnicode[unit]?[3] as int?) ?? unit;
  return (javaUnicode[upper]?[2] as int?) ?? upper;
}

int _compareIgnoreCase(String a, String b) {
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    final x = a.codeUnitAt(i), y = b.codeUnitAt(i);
    if (x == y) continue;
    final d = _foldUnit(x) - _foldUnit(y);
    if (d != 0) return d;
  }
  return a.length - b.length;
}

String _charset(DalvikRuntime vm, String name) {
  final key = name.toUpperCase().replaceAll('_', '-');
  return switch (key) {
    'UTF8' || 'UTF-8' => 'UTF-8',
    'ASCII' || 'US-ASCII' => 'US-ASCII',
    'ISO-8859-1' || 'ISO8859-1' || 'LATIN1' => 'ISO-8859-1',
    'UTF-16' || 'UTF16' => 'UTF-16',
    'UTF-16LE' => 'UTF-16LE',
    'UTF-16BE' => 'UTF-16BE',
    _ => vm.throwJava('Ljava/io/UnsupportedEncodingException;', name),
  };
}

Uint8List _encode(DalvikRuntime vm, String text, String name) {
  final c = _charset(vm, name), out = <int>[];
  if (c.startsWith('UTF-16')) {
    final le = c.endsWith('LE');
    if (c == 'UTF-16' && text.isNotEmpty) out.addAll([254, 255]);
    for (var i = 0; i < text.length; i++) {
      var unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (i + 1 < text.length &&
            text.codeUnitAt(i + 1) >= 0xdc00 &&
            text.codeUnitAt(i + 1) <= 0xdfff) {
          out.addAll(le ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255]);
          unit = text.codeUnitAt(++i);
        } else {
          unit = 0xfffd;
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        unit = 0xfffd;
      }
      out.addAll(le ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255]);
    }
    return Uint8List.fromList(out);
  }
  for (var i = 0; i < text.length; i++) {
    var point = text.codeUnitAt(i);
    if (point >= 0xd800 &&
        point <= 0xdbff &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) >= 0xdc00 &&
        text.codeUnitAt(i + 1) <= 0xdfff) {
      point =
          0x10000 + ((point - 0xd800) << 10) + text.codeUnitAt(++i) - 0xdc00;
    } else if (point >= 0xd800 && point <= 0xdfff) {
      out.add(63);
      continue;
    }
    if (c != 'UTF-8') {
      out.add(point <= (c == 'US-ASCII' ? 127 : 255) ? point : 63);
    } else if (point < 128) {
      out.add(point);
    } else if (point < 2048) {
      out.addAll([0xc0 | (point >> 6), 0x80 | (point & 63)]);
    } else if (point < 65536) {
      out.addAll([
        0xe0 | (point >> 12),
        0x80 | ((point >> 6) & 63),
        0x80 | (point & 63),
      ]);
    } else {
      out.addAll([
        0xf0 | (point >> 18),
        0x80 | ((point >> 12) & 63),
        0x80 | ((point >> 6) & 63),
        0x80 | (point & 63),
      ]);
    }
  }
  return Uint8List.fromList(out);
}

String _decode(DalvikRuntime vm, Uint8List data, String name) {
  final c = _charset(vm, name);
  if (c == 'UTF-8') return _decodeUtf8(data);
  if (c == 'ISO-8859-1') return String.fromCharCodes(data);
  if (c == 'US-ASCII') {
    return String.fromCharCodes(data.map((v) => v < 128 ? v : 0xfffd));
  }
  var le = c == 'UTF-16LE', start = 0;
  if (c == 'UTF-16' && data.length >= 2) {
    if (data[0] == 255 && data[1] == 254) {
      le = true;
      start = 2;
    } else if (data[0] == 254 && data[1] == 255) {
      start = 2;
    }
  }
  final units = <int>[];
  int unit(int i) =>
      le ? data[i] | (data[i + 1] << 8) : (data[i] << 8) | data[i + 1];
  var i = start;
  for (; i + 1 < data.length; i += 2) {
    final value = unit(i);
    if (value >= 0xd800 && value <= 0xdbff) {
      if (i + 3 >= data.length) {
        units.add(0xfffd);
        i = data.length;
        break;
      }
      final low = unit(i + 2);
      i += 2;
      if (low >= 0xdc00 && low <= 0xdfff) {
        units.addAll([value, low]);
      } else {
        units.add(0xfffd);
      }
    } else {
      units.add(
        value >= 0xdc00 && value <= 0xdfff || value == 0xfffe ? 0xfffd : value,
      );
    }
  }
  if (i < data.length) units.add(0xfffd);
  return String.fromCharCodes(units);
}

String _decodeUtf8(Uint8List data) {
  final out = <int>[];
  for (var i = 0; i < data.length;) {
    final first = data[i];
    if (first < 128) {
      out.add(first);
      i++;
      continue;
    }
    final length = first >= 0xc2 && first <= 0xdf
        ? 2
        : first >= 0xe0 && first <= 0xef
        ? 3
        : first >= 0xf0 && first <= 0xf4
        ? 4
        : 0;
    if (length == 0) {
      out.add(0xfffd);
      i++;
      continue;
    }
    var count = 1;
    while (count < length && i + count < data.length) {
      final next = data[i + count];
      if (next < 0x80 || next > 0xbf) break;
      if (count == 1 &&
          (first == 0xe0 && next < 0xa0 ||
              first == 0xf0 && next < 0x90 ||
              first == 0xf4 && next > 0x8f)) {
        break;
      }
      count++;
    }
    if (count < length) {
      out.add(0xfffd);
      i += count;
      continue;
    }
    var point = first & ((1 << (7 - length)) - 1);
    for (var j = 1; j < length; j++) {
      point = (point << 6) | (data[i + j] & 63);
    }
    out.add(point >= 0xd800 && point <= 0xdfff ? 0xfffd : point);
    i += length;
  }
  return String.fromCharCodes(out);
}

String _floating(double value, bool single) => javaFloatingText(value, single);

void _registerBuilders(
  DalvikRuntime vm,
  _Register native,
  String Function(Object?) objectText,
) {
  for (final name in ['StringBuilder', 'StringBuffer']) {
    final owner = 'Ljava/lang/$name;';
    _Builder builder(Object? value) => vm.object(value).nativeValue as _Builder;
    native(owner, '<init>()V', (_, a) {
      vm.object(a[0]).nativeValue = _Builder();
      return null;
    });
    native(owner, '<init>(I)V', (_, a) {
      if (_int(a[1]) < 0) {
        vm.throwJava('Ljava/lang/NegativeArraySizeException;');
      }
      vm.object(a[0]).nativeValue = _Builder();
      return null;
    });
    native(owner, '<init>(Ljava/lang/String;)V', (_, a) {
      vm.object(a[0]).nativeValue = _Builder(vm.string(a[1]));
      return null;
    });
    native(owner, 'length()I', (_, a) => builder(a[0]).text.length);
    native(
      owner,
      'toString()Ljava/lang/String;',
      (_, a) => vm.newString(builder(a[0]).text),
    );
    for (final type in [
      'I',
      'J',
      'Z',
      'C',
      'F',
      'D',
      'Ljava/lang/String;',
      'Ljava/lang/Object;',
    ]) {
      native(owner, 'append($type)$owner', (_, a) {
        final s = switch (type) {
          'I' => _int(a[1]).toString(),
          'J' => JBits.wide(a, 1).toString(),
          'Z' => _int(a[1]) == 0 ? 'false' : 'true',
          'C' => String.fromCharCode(_int(a[1]) & 65535),
          'F' => _floating(JBits.float(a, 1), true),
          'D' => _floating(JBits.doubleValue(a, 1), false),
          _ => objectText(a[1]),
        };
        builder(a[0]).text += s;
        return a[0];
      });
    }
    native(owner, 'insert(ILjava/lang/String;)$owner', (_, a) {
      final b = builder(a[0]), i = _int(a[1]);
      _bounds(vm, i, i, b.text.length, string: true);
      b.text = b.text.substring(0, i) + objectText(a[2]) + b.text.substring(i);
      return a[0];
    });
    native(owner, 'delete(II)$owner', (_, a) {
      final b = builder(a[0]),
          start = _int(a[1]),
          end = math.min(_int(a[2]), b.text.length);
      _bounds(vm, start, end, b.text.length, string: true);
      b.text = b.text.substring(0, start) + b.text.substring(end);
      return a[0];
    });
    native(owner, 'deleteCharAt(I)$owner', (_, a) {
      final b = builder(a[0]), i = _int(a[1]);
      _bounds(vm, i, i + 1, b.text.length, string: true);
      b.text = b.text.substring(0, i) + b.text.substring(i + 1);
      return a[0];
    });
    native(owner, 'setCharAt(IC)V', (_, a) {
      final b = builder(a[0]), i = _int(a[1]);
      _bounds(vm, i, i + 1, b.text.length, string: true);
      b.text =
          b.text.substring(0, i) +
          String.fromCharCode(_int(a[2]) & 65535) +
          b.text.substring(i + 1);
      return null;
    });
    native(owner, 'setLength(I)V', (_, a) {
      final b = builder(a[0]), n = _int(a[1]);
      if (n < 0) vm.throwJava('Ljava/lang/StringIndexOutOfBoundsException;');
      b.text = n <= b.text.length
          ? b.text.substring(0, n)
          : b.text + '\u0000' * (n - b.text.length);
      return null;
    });
  }
}

int _parseInteger(DalvikRuntime vm, String s, int radix, int bits) {
  if (radix < 2 || radix > 36 || s.isEmpty) {
    vm.throwJava('Ljava/lang/NumberFormatException;', s);
  }
  final normalized = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (i == 0 && (c == 43 || c == 45)) {
      normalized.writeCharCode(c);
      continue;
    }
    final d = (javaUnicode[c]?[4] as int?) ?? -1;
    if (d < 0 || d >= radix) {
      vm.throwJava('Ljava/lang/NumberFormatException;', s);
    }
    normalized.write(d.toRadixString(radix));
  }
  final parsed = BigInt.tryParse(normalized.toString(), radix: radix);
  final limit = BigInt.one << (bits - 1);
  if (parsed == null || parsed < -limit || parsed >= limit || s.trim() != s) {
    vm.throwJava('Ljava/lang/NumberFormatException;', s);
  }
  return parsed.toInt();
}

double _parseFloating(DalvikRuntime vm, String text, {bool single = false}) {
  final bits = javaParseFloatingBits(_trim(text), single: single);
  if (bits == null) vm.throwJava('Ljava/lang/NumberFormatException;', text);
  return single
      ? JavaNumbers.floatFromBits(bits)
      : (ByteData(
          8,
        )..setInt64(0, bits, Endian.little)).getFloat64(0, Endian.little);
}

void _registerNumbers(DalvikRuntime vm, _Register native) {
  final cache = <String, DalvikObject>{};
  final specs = {
    'Byte': 'B',
    'Short': 'S',
    'Integer': 'I',
    'Long': 'J',
    'Float': 'F',
    'Double': 'D',
    'Boolean': 'Z',
    'Character': 'C',
  };
  int raw(List<Object?> a, int i, String type) =>
      type == 'J' || type == 'D' ? JBits.wide(a, i) : _int(a[i]);
  DalvikObject box(String owner, int value, {bool cached = false}) => cached
      ? cache.putIfAbsent(
          '$owner:$value',
          () => DalvikObject(owner, nativeValue: value),
        )
      : DalvikObject(owner, nativeValue: value);
  String format(String type, int value) => switch (type) {
    'F' => _floating(JavaNumbers.floatFromBits(value), true),
    'D' => _floating(
      (ByteData(
        8,
      )..setInt64(0, value, Endian.little)).getFloat64(0, Endian.little),
      false,
    ),
    'Z' => value == 0 ? 'false' : 'true',
    'C' => String.fromCharCode(value & 65535),
    _ => value.toString(),
  };
  for (final entry in specs.entries) {
    final owner = 'Ljava/lang/${entry.key};', type = entry.value;
    native(owner, '<init>($type)V', (_, a) {
      vm.object(a[0]).nativeValue = raw(a, 1, type);
      return null;
    });
    native(owner, 'valueOf($type)$owner', (_, a) {
      final v = raw(a, 0, type);
      return box(
        owner,
        v,
        cached:
            type == 'Z' ||
            (type == 'B' || type == 'S' || type == 'I' || type == 'J') &&
                v >= -128 &&
                v <= 127 ||
            type == 'C' && v >= 0 && v <= 127,
      );
    });
    native(
      owner,
      'toString()Ljava/lang/String;',
      (_, a) => vm.newString(format(type, vm.object(a[0]).nativeValue as int)),
    );
    native(
      owner,
      'toString($type)Ljava/lang/String;',
      (_, a) => vm.newString(format(type, raw(a, 0, type))),
    );
    int canonical(int v) {
      if (type == 'F' && JavaNumbers.floatFromBits(v).isNaN) return 0x7fc00000;
      if (type == 'D' &&
          (ByteData(8)..setInt64(0, v, Endian.little))
              .getFloat64(0, Endian.little)
              .isNaN) {
        return 0x7ff8000000000000;
      }
      return v;
    }

    native(
      owner,
      'equals(Ljava/lang/Object;)Z',
      (_, a) => _bool(
        a[1] is DalvikObject &&
            (a[1] as DalvikObject).className == owner &&
            canonical(vm.object(a[0]).nativeValue as int) ==
                canonical(vm.object(a[1]).nativeValue as int),
      ),
    );
    native(owner, 'hashCode()I', (_, a) {
      final v = canonical(vm.object(a[0]).nativeValue as int);
      return type == 'Z'
          ? (v == 0 ? 1237 : 1231)
          : (type == 'J' || type == 'D')
          ? (v ^ (v >>> 32)).toSigned(32)
          : v.toSigned(32);
    });
    if (type == 'Z') {
      native(owner, 'booleanValue()Z', (_, a) => vm.object(a[0]).nativeValue);
    } else if (type == 'C') {
      native(owner, 'charValue()C', (_, a) => vm.object(a[0]).nativeValue);
    } else {
      num number(Object? value) {
        final v = vm.object(value).nativeValue as int;
        return type == 'F'
            ? JavaNumbers.floatFromBits(v)
            : type == 'D'
            ? (ByteData(
                8,
              )..setInt64(0, v, Endian.little)).getFloat64(0, Endian.little)
            : v;
      }

      native(owner, 'intValue()I', (_, a) {
        final n = number(a[0]);
        return n is int ? n.toSigned(32) : JavaNumbers.doubleToInt(n as double);
      });
      native(owner, 'byteValue()B', (_, a) {
        final n = number(a[0]);
        return (n is int ? n : JavaNumbers.doubleToInt(n as double)).toSigned(
          8,
        );
      });
      native(owner, 'shortValue()S', (_, a) {
        final n = number(a[0]);
        return (n is int ? n : JavaNumbers.doubleToInt(n as double)).toSigned(
          16,
        );
      });
      native(owner, 'longValue()J', (_, a) {
        final n = number(a[0]);
        if (n is int) return n;
        final r = <Object?>[0, 0];
        JBits.setDouble(r, 0, n as double);
        JBits.unary(0x8b, r, 0, 0);
        return JBits.wide(r, 0);
      });
      native(owner, 'floatValue()F', (_, a) {
        final n = number(a[0]);
        if (n is int) {
          final r = <Object?>[0, 0];
          JBits.setWide(r, 0, n);
          JBits.unary(0x85, r, 0, 0);
          return r[0];
        }
        return JavaNumbers.floatBits(n as double);
      });
      native(
        owner,
        'doubleValue()D',
        (_, a) => _doubleBits(number(a[0]).toDouble()),
      );
    }
    vm.classes[owner]!.staticFields['$owner->TYPE:Ljava/lang/Class;'] = vm
        .typeObject(type);
  }
  final boolean = vm.classes['Ljava/lang/Boolean;']!;
  boolean.staticFields['Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;'] = box(
    'Ljava/lang/Boolean;',
    1,
    cached: true,
  );
  boolean.staticFields['Ljava/lang/Boolean;->FALSE:Ljava/lang/Boolean;'] = box(
    'Ljava/lang/Boolean;',
    0,
    cached: true,
  );
  native(
    'Ljava/lang/Boolean;',
    'valueOf(Ljava/lang/String;)Ljava/lang/Boolean;',
    (_, a) => box(
      'Ljava/lang/Boolean;',
      _bool(!vm.isNull(a[0]) && vm.string(a[0]).toLowerCase() == 'true'),
      cached: true,
    ),
  );
  for (final name in ['Integer', 'Long']) {
    final owner = 'Ljava/lang/$name;',
        type = name == 'Integer' ? 'I' : 'J',
        bits = name == 'Integer' ? 32 : 64;
    for (final radix in [false, true]) {
      native(
        owner,
        'parse${name == 'Integer' ? 'Int' : 'Long'}(Ljava/lang/String;${radix ? 'I' : ''})$type',
        (_, a) => _parseInteger(
          vm,
          vm.isNull(a[0]) ? 'null' : vm.string(a[0]),
          radix ? _int(a[1]) : 10,
          bits,
        ),
      );
    }
  }
  native('Ljava/lang/Integer;', 'toString(II)Ljava/lang/String;', (_, a) {
    var radix = _int(a[1]);
    if (radix < 2 || radix > 36) radix = 10;
    return vm.newString(_int(a[0]).toRadixString(radix));
  });
  native(
    'Ljava/lang/Integer;',
    'toHexString(I)Ljava/lang/String;',
    (_, a) => vm.newString(_int(a[0]).toUnsigned(32).toRadixString(16)),
  );
  native(
    'Ljava/lang/Float;',
    'parseFloat(Ljava/lang/String;)F',
    (_, a) => JavaNumbers.floatBits(
      _parseFloating(vm, vm.string(a[0]), single: true),
    ),
  );
  native(
    'Ljava/lang/Double;',
    'parseDouble(Ljava/lang/String;)D',
    (_, a) => _doubleBits(_parseFloating(vm, vm.string(a[0]))),
  );
  native(
    'Ljava/lang/Float;',
    'valueOf(Ljava/lang/String;)Ljava/lang/Float;',
    (_, a) => box(
      'Ljava/lang/Float;',
      JavaNumbers.floatBits(_parseFloating(vm, vm.string(a[0]), single: true)),
    ),
  );
  native(
    'Ljava/lang/Double;',
    'isNaN(D)Z',
    (_, a) => _bool(JBits.doubleValue(a, 0).isNaN),
  );
  native('Ljava/lang/Float;', 'intBitsToFloat(I)F', (_, a) => _int(a[0]));
  native('Ljava/lang/Character;', 'isDigit(C)Z', (_, a) {
    final digit = (javaUnicode[_int(a[0]) & 65535]?[4] as int?) ?? -1;
    return _bool(digit >= 0 && digit < 10);
  });
  native('Ljava/lang/Float;', 'compareTo(Ljava/lang/Float;)I', (_, a) {
    final x = vm.object(a[0]).nativeValue as int,
        y = vm.object(a[1]).nativeValue as int;
    final xv = JavaNumbers.floatFromBits(x), yv = JavaNumbers.floatFromBits(y);
    if (xv < yv) return -1;
    if (xv > yv) return 1;
    final xb = (xv.isNaN ? 0x7fc00000 : x).toSigned(32),
        yb = (yv.isNaN ? 0x7fc00000 : y).toSigned(32);
    return xb.compareTo(yb);
  });
  native(
    'Ljava/lang/Double;',
    'longBitsToDouble(J)D',
    (_, a) => JBits.wide(a, 0),
  );
  _registerMath(vm, native);
  final random = 'Ljava/util/Random;';
  JavaRandom rng(Object? o) => vm.object(o).nativeValue as JavaRandom;
  native(random, '<init>()V', (_, a) {
    vm.object(a[0]).nativeValue = JavaRandom(vm.nextRandomSeed());
    return null;
  });
  native(random, '<init>(J)V', (_, a) {
    vm.object(a[0]).nativeValue = JavaRandom(JBits.wide(a, 1));
    return null;
  });
  native(random, 'setSeed(J)V', (_, a) {
    rng(a[0]).setSeed(JBits.wide(a, 1));
    return null;
  });
  native(random, 'nextInt()I', (_, a) => rng(a[0]).nextInt());
  native(random, 'nextInt(I)I', (_, a) {
    final bound = _int(a[1]);
    if (bound <= 0) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'bound must be positive',
      );
    }
    return rng(a[0]).nextInt(bound);
  });
  native(random, 'nextLong()J', (_, a) => rng(a[0]).nextLong());
  native(
    random,
    'nextFloat()F',
    (_, a) => JavaNumbers.floatBits(rng(a[0]).nextFloat()),
  );
  native(
    random,
    'nextDouble()D',
    (_, a) => _doubleBits(rng(a[0]).nextDouble()),
  );
  native(random, 'nextBoolean()Z', (_, a) => _bool(rng(a[0]).nextBoolean()));
}

void _registerMath(DalvikRuntime vm, _Register native) {
  const owner = 'Ljava/lang/Math;';
  native(owner, 'abs(I)I', (_, a) {
    final v = _int(a[0]);
    return (v < 0 ? -v : v).toSigned(32);
  });
  native(owner, 'abs(J)J', (_, a) {
    final v = JBits.wide(a, 0);
    return v < 0 ? -v : v;
  });
  native(owner, 'abs(F)F', (_, a) => _int(a[0]) & 0x7fffffff);
  native(owner, 'abs(D)D', (_, a) => JBits.wide(a, 0) & 0x7fffffffffffffff);
  for (final wide in [false, true]) {
    for (final min in [false, true]) {
      native(
        owner,
        '${min ? 'min' : 'max'}(${wide ? 'JJ' : 'II'})${wide ? 'J' : 'I'}',
        (_, a) {
          final x = wide ? JBits.wide(a, 0) : _int(a[0]),
              y = wide ? JBits.wide(a, 2) : _int(a[1]);
          return min ? math.min(x, y) : math.max(x, y);
        },
      );
    }
  }
  final unary = <String, double Function(double)>{
    'sqrt': math.sqrt,
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'asin': math.asin,
    'acos': math.acos,
    'atan': math.atan,
    'floor': (x) => x.floorToDouble(),
    'ceil': (x) => x.ceilToDouble(),
  };
  for (final op in unary.entries) {
    native(
      owner,
      '${op.key}(D)D',
      (_, a) => _doubleBits(op.value(JBits.doubleValue(a, 0))),
    );
  }
  native(
    owner,
    'pow(DD)D',
    (_, a) => _doubleBits(
      math.pow(JBits.doubleValue(a, 0), JBits.doubleValue(a, 2)).toDouble(),
    ),
  );
  native(
    owner,
    'round(F)I',
    (_, a) =>
        JavaNumbers.doubleToInt((JBits.float(a, 0) + 0.5).floorToDouble()),
  );
}

void _registerSystem(
  DalvikRuntime vm,
  _Register native,
  int Function(Object?) identity,
) {
  const owner = 'Ljava/lang/System;';
  native(owner, 'currentTimeMillis()J', (_, a) {
    final clock = vm.wallClockMillis;
    if (clock == null) throw MissingDalvikBridge('platform wall clock');
    return clock();
  });
  native(
    owner,
    'identityHashCode(Ljava/lang/Object;)I',
    (_, a) => vm.isNull(a[0]) ? 0 : identity(a[0]),
  );
  native(owner, 'getProperty(Ljava/lang/String;)Ljava/lang/String;', (_, a) {
    final key = vm.string(a[0]);
    if (key.isEmpty) {
      vm.throwJava('Ljava/lang/IllegalArgumentException;', 'key is empty');
    }
    final v = vm.systemProperties[key];
    return v == null ? null : vm.newString(v);
  });
  native(
    owner,
    'setProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
    (_, a) {
      final key = vm.string(a[0]), value = vm.string(a[1]);
      if (key.isEmpty) {
        vm.throwJava('Ljava/lang/IllegalArgumentException;', 'key is empty');
      }
      final old = vm.systemProperties[key];
      vm.systemProperties[key] = value;
      return old == null ? null : vm.newString(old);
    },
  );
  native(owner, 'arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V', (_, a) {
    final source = vm.object(a[0]), destination = vm.object(a[2]);
    if (source is! DalvikArray || destination is! DalvikArray) {
      vm.throwJava('Ljava/lang/ArrayStoreException;');
    }
    final from = _int(a[1]), to = _int(a[3]), count = _int(a[4]);
    final sp = source.component.length == 1,
        dp = destination.component.length == 1;
    if (sp != dp || sp && source.component != destination.component) {
      vm.throwJava('Ljava/lang/ArrayStoreException;');
    }
    if (from < 0 ||
        to < 0 ||
        count < 0 ||
        from + count > source.values.length ||
        to + count > destination.values.length) {
      vm.throwJava('Ljava/lang/ArrayIndexOutOfBoundsException;');
    }
    final copy = source.values.sublist(from, from + count);
    // Checked reference copies may partially succeed before ArrayStoreException.
    for (var i = 0; i < count; i++) {
      vm.arrayPut(destination, to + i, copy[i]);
    }
    return null;
  });
}

final class _LocaleValue {
  const _LocaleValue(this.language, this.country, [this.variant = '']);
  final String language;
  final String? country;
  final String variant;
}

void _registerLocaleAndEnum(DalvikRuntime vm, _Register native) {
  const locale = 'Ljava/util/Locale;', en = 'Ljava/lang/Enum;';
  vm.registerExternalClass(
    locale,
    interfaces: ['Ljava/lang/Cloneable;', 'Ljava/io/Serializable;'],
  );
  for (final count in [1, 2, 3]) {
    native(locale, '<init>(${'Ljava/lang/String;' * count})V', (_, a) {
      var language = vm.string(a[1]).toLowerCase();
      language = switch (language) {
        'he' => 'iw',
        'yi' => 'ji',
        'id' => 'in',
        _ => language,
      };
      vm.object(a[0]).nativeValue = _LocaleValue(
        language,
        count > 1 ? vm.string(a[2]).toUpperCase() : '',
        count > 2 ? vm.string(a[3]) : '',
      );
      return null;
    });
  }
  native(locale, 'getDefault()Ljava/util/Locale;', (_, a) {
    final lang = vm.defaultLocaleLanguage;
    if (lang == null) throw MissingDalvikBridge('default locale language');
    return DalvikObject(
      locale,
      nativeValue: _LocaleValue(lang, vm.systemProperties['user.country']),
    );
  });
  native(
    locale,
    'getLanguage()Ljava/lang/String;',
    (_, a) =>
        vm.newString((vm.object(a[0]).nativeValue as _LocaleValue).language),
  );
  native(locale, 'getCountry()Ljava/lang/String;', (_, a) {
    final value = (vm.object(a[0]).nativeValue as _LocaleValue).country;
    if (value == null) throw MissingDalvikBridge('default locale country');
    return vm.newString(value);
  });
  native(locale, 'toString()Ljava/lang/String;', (_, a) {
    final v = vm.object(a[0]).nativeValue as _LocaleValue;
    if (v.country == null) throw MissingDalvikBridge('default locale country');
    return vm.newString(
      '${v.language}${v.country!.isNotEmpty || v.variant.isNotEmpty ? '_${v.country}' : ''}${v.variant.isNotEmpty ? '_${v.variant}' : ''}',
    );
  });
  const known = {
    'ROOT': ['', ''],
    'ENGLISH': ['en', ''],
    'US': ['en', 'US'],
    'UK': ['en', 'GB'],
    'FRENCH': ['fr', ''],
    'GERMAN': ['de', ''],
    'ITALIAN': ['it', ''],
    'JAPANESE': ['ja', ''],
    'KOREAN': ['ko', ''],
    'CHINESE': ['zh', ''],
    'SIMPLIFIED_CHINESE': ['zh', 'CN'],
    'TRADITIONAL_CHINESE': ['zh', 'TW'],
  };
  for (final e in known.entries) {
    vm.classes[locale]!.staticFields['$locale->${e.key}:$locale'] =
        DalvikObject(locale, nativeValue: _LocaleValue(e.value[0], e.value[1]));
  }
  vm.registerExternalClass(
    en,
    interfaces: ['Ljava/lang/Comparable;', 'Ljava/io/Serializable;'],
  );
  native(en, '<init>(Ljava/lang/String;I)V', (_, a) {
    final o = vm.object(a[0]);
    o.fields['$en->name:Ljava/lang/String;'] = a[1];
    o.fields['$en->ordinal:I'] = _int(a[2]);
    return null;
  });
  native(en, 'ordinal()I', (_, a) => vm.object(a[0]).fields['$en->ordinal:I']);
  native(
    en,
    'name()Ljava/lang/String;',
    (_, a) => vm.object(a[0]).fields['$en->name:Ljava/lang/String;'],
  );
  native(
    en,
    'toString()Ljava/lang/String;',
    (_, a) => vm.object(a[0]).fields['$en->name:Ljava/lang/String;'],
  );
  native(en, 'valueOf(Ljava/lang/Class;Ljava/lang/String;)Ljava/lang/Enum;', (
    _,
    a,
  ) {
    final owner = vm.object(a[0]).nativeValue as String, name = vm.string(a[1]);
    final values = vm.asArray(
      vm.call('$owner->values()[$owner', [], kind: 'static'),
    );
    for (final value in values.values) {
      final o = vm.object(value);
      if (vm.string(o.fields['$en->name:Ljava/lang/String;']) == name) return o;
    }
    vm.throwJava(
      'Ljava/lang/IllegalArgumentException;',
      'No enum constant ${_className(owner)}.$name',
    );
  });
}

String _caseText(String text, String language, bool upper) {
  if (language == 'lt') {
    throw MissingDalvikBridge('Lithuanian contextual case conversion');
  }
  final points = text.runes.toList(), out = <int>[];
  bool cased(int c) {
    final row = javaUnicode[c];
    return row != null && (row[2] != c || row[3] != c);
  }

  bool ignored(int c) => c == 39 || c == 0x2019 || (c >= 0x300 && c <= 0x36f);
  for (var i = 0; i < points.length; i++) {
    final cp = points[i];
    if (language == 'tr' || language == 'az') {
      if (upper && cp == 0x69) {
        out.add(0x130);
        continue;
      }
      if (!upper && cp == 0x130) {
        out.add(0x69);
        continue;
      }
      if (!upper && cp == 0x49) {
        if (i + 1 < points.length && points[i + 1] == 0x307) {
          out.add(0x69);
          i++;
        } else {
          out.add(0x131);
        }
        continue;
      }
    }
    if (!upper && cp == 0x3a3) {
      var before = i - 1, after = i + 1;
      while (before >= 0 && ignored(points[before])) {
        before--;
      }
      while (after < points.length && ignored(points[after])) {
        after++;
      }
      if (before >= 0 &&
          cased(points[before]) &&
          (after == points.length || !cased(points[after]))) {
        out.add(0x3c2);
        continue;
      }
    }
    final row = javaUnicode[cp];
    if (row == null) {
      out.addAll(String.fromCharCode(cp).codeUnits);
    } else {
      out.addAll(row[upper ? 1 : 0] as List<int>);
    }
  }
  return String.fromCharCodes(out);
}
