// Adapted from Android libcore org.json, android-5.0.0_r1.
// Copyright (C) 2010 The Android Open Source Project.
// Licensed under the Apache License, Version 2.0; see
// third_party/android_json/LICENSE and third_party/android_json/NOTICE.
import 'dart:typed_data';

import '../compat/java_numbers.dart';
import 'numbers.dart';
import 'runtime.dart';

const _jsonObject = 'Lorg/json/JSONObject;';
const _jsonArray = 'Lorg/json/JSONArray;';
const _jsonNull = 'Lorg/json/JSONObject\$1;';
const _keysClass = 'Lorg/json/JSONObject\$Keys;';
const _jsonException = 'Lorg/json/JSONException;';

class _ObjectData {
  final Map<String, Object?> values = {};
  int modifications = 0;
  void set(String key, Object? value) {
    if (!values.containsKey(key)) modifications++;
    values[key] = value;
  }

  Object? remove(Object? key) {
    if (values.containsKey(key)) modifications++;
    return values.remove(key);
  }
}

class _ArrayData {
  final List<Object?> values = [];
}

class _Keys {
  _Keys(this.owner)
    : keys = owner.values.keys.toList(),
      expected = owner.modifications;
  final _ObjectData owner;
  final List<String> keys;
  int expected;
  int position = 0;
  String? last;
}

int _doubleBits(double value) => (ByteData(
  8,
)..setFloat64(0, value, Endian.little)).getInt64(0, Endian.little);
double _doubleValue(int bits) => (ByteData(
  8,
)..setInt64(0, bits, Endian.little)).getFloat64(0, Endian.little);

class _JsonEngine {
  _JsonEngine(this.vm);
  final DalvikRuntime vm;
  final DalvikObject nullValue = DalvikObject(_jsonNull);
  DalvikObject box(String type, int value) =>
      DalvikObject('Ljava/lang/$type;', nativeValue: value);
  DalvikObject object() =>
      DalvikObject(_jsonObject, nativeValue: _ObjectData());
  DalvikObject array() => DalvikObject(_jsonArray, nativeValue: _ArrayData());
  _ObjectData objectData(Object? value) =>
      vm.object(value).nativeValue as _ObjectData;
  _ArrayData arrayData(Object? value) =>
      vm.object(value).nativeValue as _ArrayData;
  Object? normalized(Object? value) =>
      vm.isNull(value) ? null : vm.object(value);
  String? name(Object? value) => vm.isNull(value) ? null : vm.string(value);
  Never error(String message) => vm.throwJava(_jsonException, message);
  Object? invoke(Object? value, String member) =>
      vm.call('Ljava/lang/Object;->$member', [value], kind: 'virtual');
  String text(Object? value) => vm.isNull(value)
      ? 'null'
      : vm.string(invoke(value, 'toString()Ljava/lang/String;'));
  bool isNumber(Object? value) => vm.instanceOf(value, 'Ljava/lang/Number;');
  int? floating(Object? value) {
    if (isNumber(value)) return invoke(value, 'doubleValue()D') as int;
    if (vm.instanceOf(value, 'Ljava/lang/String;')) {
      try {
        return vm.call('Ljava/lang/Double;->parseDouble(Ljava/lang/String;)D', [
          value,
        ], kind: 'static') as int;
      } on DalvikThrown catch (e) {
        if (e.object.className != 'Ljava/lang/NumberFormatException;') rethrow;
      }
    }
    return null;
  }

  int? integer(Object? value, {bool wide = false}) {
    if (isNumber(value)) {
      return invoke(value, wide ? 'longValue()J' : 'intValue()I') as int;
    }
    if (vm.instanceOf(value, 'Ljava/lang/String;')) {
      final bits = floating(value);
      if (bits != null) {
        if (!wide) return JavaNumbers.doubleToInt(_doubleValue(bits));
        return invoke(box('Double', bits), 'longValue()J') as int;
      }
    }
    return null;
  }

  int? boolean(Object? value) {
    if (vm.instanceOf(value, 'Ljava/lang/Boolean;')) {
      return vm.object(value).nativeValue as int;
    }
    if (vm.instanceOf(value, 'Ljava/lang/String;')) {
      final s = vm.string(value).toLowerCase();
      if (s == 'true') return 1;
      if (s == 'false') return 0;
    }
    return null;
  }

  void checkNumber(Object? value) {
    if (isNumber(value) && !_doubleValue(floating(value)!).isFinite) {
      error('Forbidden numeric value: ${text(value)}');
    }
  }

  String numberText(Object? value) {
    if (vm.isNull(value)) error('Number must be non-null');
    checkNumber(value);
    final doubleValue = _doubleValue(floating(value)!);
    if (vm.object(value).className == 'Ljava/lang/Double;' &&
        doubleValue == 0 &&
        doubleValue.isNegative) {
      return '-0';
    }
    final longValue = invoke(value, 'longValue()J') as int;
    return doubleValue == longValue.toDouble()
        ? longValue.toString()
        : text(value);
  }

  String quote(String value) {
    final out = StringBuffer('"');
    for (final c in value.codeUnits) {
      switch (c) {
        case 34:
        case 92:
        case 47:
          out.writeCharCode(92);
          out.writeCharCode(c);
        case 9:
          out.write(r'\t');
        case 8:
          out.write(r'\b');
        case 10:
          out.write(r'\n');
        case 13:
          out.write(r'\r');
        case 12:
          out.write(r'\f');
        default:
          if (c <= 31) {
            out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
          } else {
            out.writeCharCode(c);
          }
      }
    }
    return '$out"';
  }

  String encode(Object? value) {
    if (vm.isNull(value) || identical(value, nullValue)) return 'null';
    final native = vm.object(value).nativeValue;
    if (native is _ObjectData) {
      return '{${native.values.entries.map((e) => '${quote(e.key)}:${encode(e.value)}').join(',')}}';
    }
    if (native is _ArrayData) return '[${native.values.map(encode).join(',')}]';
    if (vm.instanceOf(value, 'Ljava/lang/Boolean;')) return text(value);
    if (isNumber(value)) return numberText(value);
    return quote(text(value));
  }

  Object? stringify(Object? value) {
    try {
      return vm.newString(encode(value));
    } on DalvikThrown catch (e) {
      if (e.object.className == _jsonException) return null;
      rethrow;
    }
  }

  void put(Object? receiver, String? key, Object? value) {
    value = normalized(value);
    if (value == null) {
      objectData(receiver).remove(key);
      return;
    }
    checkNumber(value);
    if (key == null) error('Names must be non-null');
    objectData(receiver).set(key, value);
  }

  Object? get(Object? receiver, Object? key, {bool required = false}) {
    final native = vm.object(receiver).nativeValue;
    if (native is _ObjectData) {
      final label = name(key);
      final result = native.values[label];
      if (required && result == null) error('No value for ${label ?? 'null'}');
      return result;
    }
    final values = (native as _ArrayData).values;
    final index = key as int;
    if (index < 0 || index >= values.length) {
      if (required) error('Index $index out of range [0..${values.length})');
      return null;
    }
    final result = values[index];
    if (required && result == null) error('Value at $index is null.');
    return result;
  }

  Never mismatch(Object? key, Object? value, String type) {
    final label = key is int ? key.toString() : name(key) ?? 'null';
    if (vm.isNull(value)) error('Value at $label is null.');
    final actual = vm.object(value).className;
    error(
      'Value ${text(value)} at $label of type ${actual.substring(1, actual.length - 1).replaceAll('/', '.')} cannot be converted to $type',
    );
  }

  Iterable<Object?> iterate(Object? collection) sync* {
    final iterator = vm.call(
      'Ljava/util/Collection;->iterator()Ljava/util/Iterator;',
      [collection],
      kind: 'interface',
    );
    while (vm.call('Ljava/util/Iterator;->hasNext()Z', [
          iterator,
        ], kind: 'interface') ==
        1) {
      yield vm.call('Ljava/util/Iterator;->next()Ljava/lang/Object;', [
        iterator,
      ], kind: 'interface');
    }
  }

  DalvikObject fromCollection(Object? value) {
    final result = array();
    if (!vm.isNull(value)) {
      arrayData(result).values.addAll(iterate(value).map(wrap));
    }
    return result;
  }

  DalvikObject fromMap(Object? value) {
    final result = object();
    final entries = vm.call('Ljava/util/Map;->entrySet()Ljava/util/Set;', [
      value,
    ], kind: 'interface');
    for (final entry in iterate(entries)) {
      final key = vm.call(
        'Ljava/util/Map\$Entry;->getKey()Ljava/lang/Object;',
        [entry],
        kind: 'interface',
      );
      if (vm.isNull(key)) {
        vm.throwJava('Ljava/lang/NullPointerException;', 'key == null');
      }
      if (!vm.instanceOf(key, 'Ljava/lang/String;')) {
        vm.throwJava('Ljava/lang/ClassCastException;');
      }
      final item = vm.call(
        'Ljava/util/Map\$Entry;->getValue()Ljava/lang/Object;',
        [entry],
        kind: 'interface',
      );
      objectData(result).set(vm.string(key), wrap(item));
    }
    return result;
  }

  Object? wrap(Object? value) {
    if (vm.isNull(value)) return nullValue;
    if (vm.instanceOf(value, _jsonObject) ||
        vm.instanceOf(value, _jsonArray) ||
        identical(value, nullValue)) {
      return value;
    }
    if (vm.call('Ljava/lang/Object;->equals(Ljava/lang/Object;)Z', [
          value,
          nullValue,
        ], kind: 'virtual') ==
        1) {
      return value;
    }
    // Preserve the platform contract's explicit fallback for foreign objects.
    // MissingDalvikBridge is never caught as an ordinary Java exception.
    try {
      if (vm.instanceOf(value, 'Ljava/util/Collection;')) {
        return fromCollection(value);
      }
      if (value is DalvikArray) {
        final result = array();
        for (final item in value.values) {
          final descriptor = value.component;
          if (descriptor.length > 1) {
            arrayData(result).values.add(wrap(item));
          } else {
            final type = switch (descriptor) {
              'Z' => 'Boolean',
              'B' => 'Byte',
              'C' => 'Character',
              'S' => 'Short',
              'I' => 'Integer',
              'J' => 'Long',
              'F' => 'Float',
              'D' => 'Double',
              _ => throw MissingDalvikBridge('JSON array type $descriptor'),
            };
            arrayData(result).values.add(box(type, item as int));
          }
        }
        return result;
      }
      if (vm.instanceOf(value, 'Ljava/util/Map;')) return fromMap(value);
      final name = vm.object(value).className;
      if (isNumber(value) ||
          name == 'Ljava/lang/String;' ||
          name == 'Ljava/lang/Boolean;' ||
          name == 'Ljava/lang/Character;') {
        return value;
      }
      if (name.startsWith('Ljava/')) return vm.newString(text(value));
    } on DalvikThrown catch (error) {
      if (vm.instanceOf(error.object, 'Ljava/lang/Exception;')) return null;
      rethrow;
    }
    return null;
  }
}

class _Tokener {
  _Tokener(this.engine, String? input)
    : input = input != null && input.startsWith('\ufeff')
          ? input.substring(1)
          : input;
  final _JsonEngine engine;
  final String? input;
  int position = 0;
  String get source {
    if (input == null) engine.vm.throwJava('Ljava/lang/NullPointerException;');
    return input!;
  }

  Never syntax(String message) =>
      engine.error('$message at character $position of ${input ?? 'null'}');
  void line() {
    while (position < source.length) {
      final c = source.codeUnitAt(position++);
      if (c == 10 || c == 13) break;
    }
  }

  int clean() {
    while (position < source.length) {
      final c = source.codeUnitAt(position++);
      if (c == 9 || c == 32 || c == 10 || c == 13) continue;
      if (c == 47 && position < source.length) {
        final next = source.codeUnitAt(position);
        if (next == 42) {
          position++;
          final end = source.indexOf('*/', position);
          if (end == -1) syntax('Unterminated comment');
          position = end + 2;
          continue;
        }
        if (next == 47) {
          position++;
          line();
          continue;
        }
      }
      if (c == 35) {
        line();
        continue;
      }
      return c;
    }
    return -1;
  }

  DalvikObject nextValue() {
    final c = clean();
    switch (c) {
      case -1:
        syntax('End of input');
      case 123:
        return readObject();
      case 91:
        return readArray();
      case 34:
      case 39:
        return engine.vm.newString(readString(c));
      default:
        position--;
        return literal();
    }
  }

  String readString(int quote) {
    final out = StringBuffer();
    while (position < source.length) {
      final c = source.codeUnitAt(position++);
      if (c == quote) return out.toString();
      if (c != 92) {
        out.writeCharCode(c);
        continue;
      }
      if (position == source.length) syntax('Unterminated escape sequence');
      final escaped = source.codeUnitAt(position++);
      if (escaped == 117) {
        if (position + 4 > source.length) {
          syntax('Unterminated escape sequence');
        }
        final hex = source.substring(position, position + 4);
        position += 4;
        final value = engine.vm.call(
          'Ljava/lang/Integer;->parseInt(Ljava/lang/String;I)I',
          [engine.vm.newString(hex), 16],
          kind: 'static',
        ) as int;
        out.writeCharCode(value & 65535);
      } else {
        out.writeCharCode(switch (escaped) {
          116 => 9,
          98 => 8,
          110 => 10,
          114 => 13,
          102 => 12,
          _ => escaped,
        });
      }
    }
    syntax('Unterminated string');
  }

  DalvikObject literal() {
    final start = position;
    const excluded = '{}[]/\\:,=;# \t\f';
    while (position < source.length) {
      final c = source[position];
      if (c == '\r' || c == '\n' || excluded.contains(c)) break;
      position++;
    }
    final text = source.substring(start, position);
    if (text.isEmpty) syntax('Expected literal value');
    switch (text.toLowerCase()) {
      case 'null':
        return engine.nullValue;
      case 'true':
        return engine.box('Boolean', 1);
      case 'false':
        return engine.box('Boolean', 0);
    }
    if (!text.contains('.')) {
      var number = text, radix = 10;
      if (number.startsWith('0x') || number.startsWith('0X')) {
        number = number.substring(2);
        radix = 16;
      } else if (number.startsWith('0') && number.length > 1) {
        number = number.substring(1);
        radix = 8;
      }
      try {
        final value = engine.vm.call(
          'Ljava/lang/Long;->parseLong(Ljava/lang/String;I)J',
          [engine.vm.newString(number), radix],
          kind: 'static',
        ) as int;
        return engine.box(
          value >= -2147483648 && value <= 2147483647 ? 'Integer' : 'Long',
          value,
        );
      } on DalvikThrown catch (e) {
        if (e.object.className != 'Ljava/lang/NumberFormatException;') rethrow;
      }
    }
    final string = engine.vm.newString(text),
        bits = engine.floating(engine.vm.newString(text));
    return bits == null ? string : engine.box('Double', bits);
  }

  DalvikObject readObject() {
    final result = engine.object();
    final first = clean();
    if (first == 125) return result;
    if (first != -1) position--;
    while (true) {
      final key = nextValue();
      if (key.className != 'Ljava/lang/String;') {
        syntax(
          'Names must be strings, but ${engine.text(key)} is of type ${key.className.substring(1, key.className.length - 1).replaceAll('/', '.')}',
        );
      }
      final name = engine.vm.string(key), separator = clean();
      if (separator != 58 && separator != 61) {
        syntax("Expected ':' after $name");
      }
      if (position < source.length && source[position] == '>') position++;
      engine.put(result, name, nextValue());
      final next = clean();
      if (next == 125) return result;
      if (next != 59 && next != 44) syntax('Unterminated object');
    }
  }

  DalvikObject readArray() {
    final result = engine.array(), values = engine.arrayData(result).values;
    var trailing = false;
    while (true) {
      final next = clean();
      if (next == -1) syntax('Unterminated array');
      if (next == 93) {
        if (trailing) values.add(null);
        return result;
      }
      if (next == 44 || next == 59) {
        values.add(null);
        trailing = true;
        continue;
      }
      position--;
      values.add(nextValue());
      final separator = clean();
      if (separator == 93) return result;
      if (separator == 44 || separator == 59) {
        trailing = true;
        continue;
      }
      syntax('Unterminated array');
    }
  }
}

void registerJavaJson(DalvikRuntime vm) {
  final engine = _JsonEngine(vm);
  for (final name in [
    _jsonObject,
    _jsonArray,
    _jsonNull,
    'Lorg/json/JSONTokener;',
  ]) {
    vm.registerExternalClass(name);
  }
  vm.registerExternalClass(_jsonException, superclass: 'Ljava/lang/Exception;');
  vm.registerExternalClass(_keysClass, interfaces: ['Ljava/util/Iterator;']);
  vm
          .classes[_jsonObject]!
          .staticFields['$_jsonObject->NULL:Ljava/lang/Object;'] =
      engine.nullValue;
  void bind(String owner, String method, DalvikBody body) =>
      vm.registerNative('$owner->$method', body);
  bind(
    _jsonNull,
    'equals(Ljava/lang/Object;)Z',
    (v, a) => v.isNull(a[1]) || identical(a[0], a[1]) ? 1 : 0,
  );
  bind(
    _jsonNull,
    'toString()Ljava/lang/String;',
    (v, a) => v.newString('null'),
  );
  bind(_jsonException, '<init>(Ljava/lang/String;)V', (v, a) {
    v.object(a[0]).nativeValue = engine.name(a[1]);
    return null;
  });
  for (final owner in [_jsonObject, _jsonArray]) {
    final object = owner == _jsonObject,
        keyType = owner == _jsonObject ? 'Ljava/lang/String;' : 'I';
    bind(owner, '<init>()V', (v, a) {
      v.object(a[0]).nativeValue = object ? _ObjectData() : _ArrayData();
      return null;
    });
    for (final tokener in [false, true]) {
      bind(
        owner,
        '<init>(${tokener ? 'Lorg/json/JSONTokener;' : 'Ljava/lang/String;'})V',
        (v, a) {
          final reader = tokener
              ? v.object(a[1]).nativeValue as _Tokener
              : _Tokener(engine, engine.name(a[1]));
          final result = reader.nextValue();
          if (result.className != owner) {
            engine.error(
              'Value ${engine.text(result)} of type ${result.className.substring(1, result.className.length - 1).replaceAll('/', '.')} cannot be converted to ${object ? 'JSONObject' : 'JSONArray'}',
            );
          }
          v.object(a[0]).nativeValue = result.nativeValue;
          return null;
        },
      );
    }
    bind(
      owner,
      'length()I',
      (v, a) => object
          ? engine.objectData(a[0]).values.length
          : engine.arrayData(a[0]).values.length,
    );
    bind(
      owner,
      'toString()Ljava/lang/String;',
      (v, a) => engine.stringify(a[0]),
    );
    bind(
      owner,
      'get($keyType)Ljava/lang/Object;',
      (v, a) => engine.get(a[0], a[1], required: true),
    );
    bind(
      owner,
      'opt($keyType)Ljava/lang/Object;',
      (v, a) => engine.get(a[0], a[1]),
    );
    bind(owner, 'isNull($keyType)Z', (v, a) {
      final value = engine.get(a[0], a[1]);
      return value == null || identical(value, engine.nullValue) ? 1 : 0;
    });
    bind(owner, 'remove($keyType)Ljava/lang/Object;', (v, a) {
      if (object) return engine.objectData(a[0]).remove(engine.name(a[1]));
      final values = engine.arrayData(a[0]).values, i = a[1] as int;
      return i < 0 || i >= values.length ? null : values.removeAt(i);
    });
    const types = {
      'Boolean': 'Z',
      'Int': 'I',
      'Long': 'J',
      'Double': 'D',
      'String': 'Ljava/lang/String;',
      'JSONObject': _jsonObject,
      'JSONArray': _jsonArray,
    };
    for (final entry in types.entries) {
      Object? convert(Object? value) => switch (entry.key) {
        'Boolean' => engine.boolean(value),
        'Int' => engine.integer(value),
        'Long' => engine.integer(value, wide: true),
        'Double' => engine.floating(value),
        'String' => vm.isNull(value) ? null : vm.newString(engine.text(value)),
        _ => vm.instanceOf(value, entry.value) ? value : null,
      };
      bind(owner, 'get${entry.key}($keyType)${entry.value}', (v, a) {
        final value = engine.get(a[0], a[1], required: true),
            result = convert(value);
        if (result == null) {
          engine.mismatch(a[1], value, switch (entry.key) {
            'Boolean' => 'boolean',
            'Int' => 'int',
            'Long' => 'long',
            'Double' => 'double',
            _ => entry.key,
          });
        }
        return result;
      });
      Object? defaultValue() => switch (entry.key) {
        'Boolean' || 'Int' || 'Long' => 0,
        'Double' => _doubleBits(double.nan),
        'String' => vm.newString(''),
        _ => null,
      };
      bind(
        owner,
        'opt${entry.key}($keyType)${entry.value}',
        (v, a) => convert(engine.get(a[0], a[1])) ?? defaultValue(),
      );
      if (!entry.key.startsWith('JSON')) {
        bind(
          owner,
          'opt${entry.key}($keyType${entry.value})${entry.value}',
          (v, a) =>
              convert(engine.get(a[0], a[1])) ??
              (entry.value == 'J' || entry.value == 'D'
                  ? JBits.wide(a, 2)
                  : a[2]),
        );
      }
    }
    for (final type in ['Ljava/lang/Object;', 'Z', 'I', 'J', 'D']) {
      Object? value(List<Object?> a, int offset) => type == 'Ljava/lang/Object;'
          ? engine.normalized(a[offset])
          : engine.box(
              switch (type) {
                'Z' => 'Boolean',
                'I' => 'Integer',
                'J' => 'Long',
                _ => 'Double',
              },
              type == 'J' || type == 'D'
                  ? JBits.wide(a, offset)
                  : (a[offset] as int).toSigned(32),
            );
      bind(owner, 'put(${object ? 'Ljava/lang/String;' : ''}$type)$owner', (
        v,
        a,
      ) {
        final item = value(a, object ? 2 : 1);
        if (object) {
          engine.put(a[0], engine.name(a[1]), item);
        } else {
          if (type == 'D') engine.checkNumber(item);
          engine.arrayData(a[0]).values.add(item);
        }
        return a[0];
      });
      if (!object) {
        bind(owner, 'put(I$type)$owner', (v, a) {
          final item = value(a, 2);
          engine.checkNumber(item);
          final index = a[1] as int, values = engine.arrayData(a[0]).values;
          if (index < 0) v.throwJava('Ljava/lang/IndexOutOfBoundsException;');
          while (values.length <= index) {
            values.add(null);
          }
          values[index] = item;
          return a[0];
        });
      }
    }
  }
  bind(_jsonObject, '<init>(Ljava/util/Map;)V', (v, a) {
    v.object(a[0]).nativeValue = engine.fromMap(a[1]).nativeValue;
    return null;
  });
  bind(_jsonArray, '<init>(Ljava/util/Collection;)V', (v, a) {
    v.object(a[0]).nativeValue = engine.fromCollection(a[1]).nativeValue;
    return null;
  });
  bind(
    _jsonObject,
    'has(Ljava/lang/String;)Z',
    (v, a) =>
        engine.objectData(a[0]).values.containsKey(engine.name(a[1])) ? 1 : 0,
  );
  bind(
    _jsonObject,
    'keys()Ljava/util/Iterator;',
    (v, a) =>
        DalvikObject(_keysClass, nativeValue: _Keys(engine.objectData(a[0]))),
  );
  bind(
    _jsonObject,
    'quote(Ljava/lang/String;)Ljava/lang/String;',
    (v, a) => v.newString(engine.quote(engine.name(a[0]) ?? '')),
  );
  bind(
    _jsonObject,
    'numberToString(Ljava/lang/Number;)Ljava/lang/String;',
    (v, a) => v.newString(engine.numberText(a[0])),
  );
  bind(
    _jsonObject,
    'wrap(Ljava/lang/Object;)Ljava/lang/Object;',
    (v, a) => engine.wrap(a[0]),
  );
  bind(_keysClass, 'hasNext()Z', (v, a) {
    final keys = v.object(a[0]).nativeValue as _Keys;
    return keys.position < keys.keys.length ? 1 : 0;
  });
  bind(_keysClass, 'next()Ljava/lang/Object;', (v, a) {
    final keys = v.object(a[0]).nativeValue as _Keys;
    if (keys.expected != keys.owner.modifications) {
      v.throwJava('Ljava/util/ConcurrentModificationException;');
    }
    if (keys.position >= keys.keys.length) {
      v.throwJava('Ljava/util/NoSuchElementException;');
    }
    keys.last = keys.keys[keys.position++];
    return v.newString(keys.last!);
  });
  bind(_keysClass, 'remove()V', (v, a) {
    final keys = v.object(a[0]).nativeValue as _Keys;
    if (keys.last == null) v.throwJava('Ljava/lang/IllegalStateException;');
    if (keys.expected != keys.owner.modifications) {
      v.throwJava('Ljava/util/ConcurrentModificationException;');
    }
    keys.owner.remove(keys.last);
    keys.expected = keys.owner.modifications;
    keys.last = null;
    return null;
  });
  const tokener = 'Lorg/json/JSONTokener;';
  _Tokener reader(DalvikRuntime v, List<Object?> a) =>
      v.object(a[0]).nativeValue as _Tokener;
  bind(tokener, '<init>(Ljava/lang/String;)V', (v, a) {
    v.object(a[0]).nativeValue = _Tokener(engine, engine.name(a[1]));
    return null;
  });
  bind(
    tokener,
    'nextValue()Ljava/lang/Object;',
    (v, a) => reader(v, a).nextValue(),
  );
  bind(
    tokener,
    'nextString(C)Ljava/lang/String;',
    (v, a) => v.newString(reader(v, a).readString(a[1] as int)),
  );
  bind(tokener, 'nextClean()C', (v, a) {
    final c = reader(v, a).clean();
    return c == -1 ? 0 : c;
  });
  bind(tokener, 'next()C', (v, a) {
    final r = reader(v, a);
    return r.position < r.source.length ? r.source.codeUnitAt(r.position++) : 0;
  });
  bind(tokener, 'more()Z', (v, a) {
    final r = reader(v, a);
    return r.position < r.source.length ? 1 : 0;
  });
  bind(tokener, 'back()V', (v, a) {
    final r = reader(v, a);
    if (r.position > 0) r.position--;
    return null;
  });
  bind(tokener, 'toString()Ljava/lang/String;', (v, a) {
    final r = reader(v, a);
    return v.newString(' at character ${r.position} of ${r.input ?? 'null'}');
  });
}
