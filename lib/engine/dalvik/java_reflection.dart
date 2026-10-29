import '../compat/java_numbers.dart';
import 'cooperative.dart';
import 'numbers.dart';
import 'runtime.dart';

const _class = 'Ljava/lang/Class;';
const _method = 'Ljava/lang/reflect/Method;';
const _accessible = 'Ljava/lang/reflect/AccessibleObject;';
const _targetException = 'Ljava/lang/reflect/InvocationTargetException;';
const _causeField = '$_targetException->target:Ljava/lang/Throwable;';
const _wrappers = {
  'Z': 'Boolean',
  'B': 'Byte',
  'C': 'Character',
  'S': 'Short',
  'I': 'Integer',
  'J': 'Long',
  'F': 'Float',
  'D': 'Double',
};
const _primitiveNames = {
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

// Java long-to-float is one rounding step. Going through a Dart double can
// double-round values immediately above a float midpoint near 2^62.
int _integerFloatBits(int value) {
  final magnitude = BigInt.from(value).abs();
  if (magnitude.bitLength <= 24) return JavaNumbers.floatBits(value.toDouble());
  var exponent = magnitude.bitLength - 1;
  final shift = magnitude.bitLength - 24;
  var significant = magnitude >> shift;
  final remainder = magnitude - (significant << shift);
  final half = BigInt.one << (shift - 1);
  if (remainder > half || (remainder == half && significant.isOdd)) {
    significant += BigInt.one;
  }
  if (significant.bitLength > 24) {
    significant >>= 1;
    exponent++;
  }
  return ((value < 0 ? 0x80000000 : 0) |
          ((exponent + 127) << 23) |
          (significant.toInt() & 0x7fffff))
      .toSigned(32);
}

List<String> _parameters(String key) {
  final start = key.indexOf('(') + 1, end = key.indexOf(')');
  final result = <String>[];
  var offset = start;
  while (offset < end) {
    final first = offset;
    while (key[offset] == '[') {
      offset++;
    }
    offset = key[offset] == 'L' ? key.indexOf(';', offset) + 1 : offset + 1;
    result.add(key.substring(first, offset));
  }
  return result;
}

String _package(String descriptor) {
  final slash = descriptor.lastIndexOf('/');
  return slash < 0 ? '' : descriptor.substring(1, slash).replaceAll('/', '.');
}

class _ReflectedMethod {
  _ReflectedMethod(this.metadata);
  final DalvikMethod metadata;
  bool accessible = false;
  String get name => metadata.member.substring(0, metadata.member.indexOf('('));
  String get returnType =>
      metadata.key.substring(metadata.key.indexOf(')') + 1);
}

/// Native declarations used reflectively by the original Android startup.
/// This describes actual public methods, not arbitrary successful lookups.
const originalReflectiveNativeAccess = {
  'Landroid/view/Display;->getRealSize(Landroid/graphics/Point;)V': 0x1,
};

void registerJavaReflection(
  DalvikRuntime vm, {
  Map<String, int> nativeMethodAccess = const {},
  Map<String, String> simpleClassNames = const {},
}) {
  final nativeAccess = {
    ...originalReflectiveNativeAccess,
    ...nativeMethodAccess,
  };
  final packages = <String, DalvikObject>{};
  vm.registerExternalClass('Ljava/lang/Package;');
  vm.registerExternalClass(_accessible);
  vm.registerExternalClass(_method, superclass: _accessible);
  for (final type in [
    'NoSuchMethodException',
    'IllegalAccessException',
    'InstantiationException',
  ]) {
    vm.registerExternalClass(
      'Ljava/lang/$type;',
      superclass: 'Ljava/lang/Exception;',
    );
  }
  vm.registerExternalClass(
    _targetException,
    superclass: 'Ljava/lang/Exception;',
  );
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  String className(Object? value) => vm.object(value).nativeValue as String;
  _ReflectedMethod method(Object? value) =>
      vm.object(value).nativeValue as _ReflectedMethod;
  String? caller() {
    for (final key in vm.callStack.reversed.skip(1)) {
      final owner = key.substring(0, key.indexOf('->'));
      if (!owner.startsWith('Ljava/lang/reflect/')) return owner;
    }
    return null;
  }

  bool allowed(String owner, int access, String? from, Object? receiver) {
    if (owner == from) return true;
    final classAccess = vm.classes[owner]?.access;
    if (classAccess == null) {
      throw MissingDalvikBridge('Reflection class metadata $owner');
    }
    final samePackage = from != null && _package(owner) == _package(from);
    if (classAccess & 1 == 0 && !samePackage) return false;
    if (access & 1 != 0) return true;
    if (access & 2 != 0) return false;
    if (samePackage) return true;
    return access & 4 != 0 &&
        from != null &&
        vm.assignable(from, owner) &&
        (access & 8 != 0 ||
            (receiver is DalvikObject && vm.instanceOf(receiver, from)));
  }

  Iterable<DalvikMethod> declared(String owner) sync* {
    yield* vm.methods.values.where((value) => value.owner == owner);
    for (final entry in nativeAccess.entries) {
      if (entry.key.startsWith('$owner->') &&
          !vm.methods.containsKey(entry.key)) {
        yield DalvikMethod(entry.key, entry.value, null);
      }
    }
  }

  DalvikMethod? lookup(
    String owner,
    String name,
    List<String> parameters,
    bool inherited,
  ) {
    final prefix = '$name(${parameters.join()})';
    final matches = declared(owner)
        .where(
          (m) =>
              m.member.startsWith(prefix) && (!inherited || m.access & 1 != 0),
        )
        .toList();
    if (matches.isNotEmpty) {
      var selected = matches.first;
      for (final candidate in matches.skip(1)) {
        final actual = candidate.key.substring(candidate.key.indexOf(')') + 1);
        final current = selected.key.substring(selected.key.indexOf(')') + 1);
        if (actual != current &&
            actual.length > 1 &&
            current.length > 1 &&
            vm.assignable(actual, current)) {
          selected = candidate;
        }
      }
      return selected;
    }
    if (inherited) {
      final definition = vm.classes[owner];
      if (definition?.superclass != null) {
        final found = lookup(definition!.superclass!, name, parameters, true);
        if (found != null) return found;
      }
      for (final interface in definition?.interfaces ?? const <String>[]) {
        final found = lookup(interface, name, parameters, true);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<String> parameterTypes(Object? value) {
    if (vm.isNull(value)) return [];
    return vm.asArray(value).values.map((element) {
      if (vm.isNull(element)) {
        vm.throwJava(
          'Ljava/lang/NoSuchMethodException;',
          'Null parameter type',
        );
      }
      return className(element);
    }).toList();
  }

  List<Object?> words(String type, int raw) {
    if (type == 'J' || type == 'D') {
      return [raw.toSigned(32), (raw >> 32).toSigned(32)];
    }
    return [raw.toSigned(32)];
  }

  List<Object?> argument(Object? value, String target) {
    if (target.length > 1) {
      if (!vm.isNull(value) && !vm.instanceOf(value, target)) {
        vm.throwJava(
          'Ljava/lang/IllegalArgumentException;',
          'Argument type mismatch',
        );
      }
      return [vm.isNull(value) ? null : value];
    }
    if (vm.isNull(value) || value is! DalvikObject) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Primitive argument requires a wrapper',
      );
    }
    String? source;
    for (final entry in _wrappers.entries) {
      if (value.className == 'Ljava/lang/${entry.value};') source = entry.key;
    }
    const widening = {
      'Z': 'Z',
      'B': 'BSIJFD',
      'S': 'SIJFD',
      'C': 'CIJFD',
      'I': 'IJFD',
      'J': 'JFD',
      'F': 'FD',
      'D': 'D',
    };
    if (source == null || !widening[source]!.contains(target)) {
      vm.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Illegal primitive narrowing',
      );
    }
    final raw = value.nativeValue as int;
    if (source == target || !'FD'.contains(target)) return words(target, raw);
    final number = source == 'F'
        ? JavaNumbers.floatFromBits(raw)
        : raw.toDouble();
    if (target == 'F') return [_integerFloatBits(raw)];
    final registers = <Object?>[0, 0];
    JBits.setDouble(registers, 0, number);
    return registers;
  }

  Object? box(Object? value, String type) {
    if (type == 'V') return null;
    if (type.length > 1) return value;
    final owner = 'Ljava/lang/${_wrappers[type]};';
    return vm.call(
      '$owner->valueOf($type)$owner',
      words(type, value as int),
      kind: 'static',
    );
  }

  Never wrap(DalvikThrown target) {
    final wrapper = DalvikObject(_targetException);
    wrapper.fields[_causeField] = target.object;
    vm.throwableTraces[wrapper] = List.of(vm.callStack.reversed);
    throw DalvikThrown(wrapper);
  }

  Object? invokeTarget(
    _ReflectedMethod reflected,
    List<Object?> arguments,
    String kind,
  ) {
    Object? value;
    try {
      value = vm.call(reflected.metadata.key, arguments, kind: kind);
    } on DalvikPause catch (pause) {
      pause.addFrame(
        DalvikResumeFrame(
          methodKey: 'Method.invoke ${reflected.metadata.key}',
          pc: -1,
          resume: (completion) {
            Object? result;
            try {
              result = completion.unwrap();
            } on DalvikThrown catch (error) {
              wrap(error);
            }
            return box(result, reflected.returnType);
          },
        ),
      );
      rethrow;
    } on DalvikThrown catch (error) {
      wrap(error);
    }
    return box(value, reflected.returnType);
  }

  native(_class, 'getPackage()Ljava/lang/Package;', (v, a) {
    final name = className(a[0]);
    if (name.length == 1 || name.startsWith('[')) return null;
    final packageName = _package(name);
    if (packageName.isEmpty) return null;
    return packages.putIfAbsent(
      packageName,
      () => DalvikObject('Ljava/lang/Package;', nativeValue: packageName),
    );
  });
  native(
    'Ljava/lang/Package;',
    'getName()Ljava/lang/String;',
    (v, a) => v.intern(v.object(a[0]).nativeValue as String),
  );
  String simpleName(String descriptor) {
    if (descriptor.startsWith('[')) {
      return '${simpleName(descriptor.substring(1))}[]';
    }
    if (_primitiveNames.containsKey(descriptor)) {
      return _primitiveNames[descriptor]!;
    }
    final explicit = simpleClassNames[descriptor];
    if (explicit != null) return explicit;
    final bare = descriptor.substring(
      descriptor.lastIndexOf('/') + 1,
      descriptor.length - 1,
    );
    final result = bare.startsWith('L') && !descriptor.contains('/')
        ? bare.substring(1)
        : bare;
    if (result.contains(r'$')) {
      throw MissingDalvikBridge(
        'Inner-class simple-name annotation $descriptor',
      );
    }
    return result;
  }

  native(
    _class,
    'getSimpleName()Ljava/lang/String;',
    (v, a) => v.intern(simpleName(className(a[0]))),
  );
  native(_class, 'getModifiers()I', (v, a) {
    var descriptor = className(a[0]);
    final array = descriptor.startsWith('[');
    while (descriptor.startsWith('[')) {
      descriptor = descriptor.substring(1);
    }
    if (descriptor.length == 1) return 0x411;
    final definition = v.classes[descriptor];
    if (definition == null) {
      throw MissingDalvikBridge('Reflection class modifiers $descriptor');
    }
    return array ? (definition.access & 7) | 0x410 : definition.access;
  });
  for (final inherited in [false, true]) {
    native(
      _class,
      '${inherited ? 'getMethod' : 'getDeclaredMethod'}(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;',
      (v, a) {
        final owner = className(a[0]), name = v.string(a[1]);
        final parameters = parameterTypes(a[2]);
        final found = name.startsWith('<')
            ? null
            : lookup(owner, name, parameters, inherited);
        if (found == null) {
          v.throwJava(
            'Ljava/lang/NoSuchMethodException;',
            '$owner.$name(${parameters.join()})',
          );
        }
        return DalvikObject(_method, nativeValue: _ReflectedMethod(found));
      },
    );
  }
  native(
    _accessible,
    'isAccessible()Z',
    (v, a) => method(a[0]).accessible ? 1 : 0,
  );
  native(_accessible, 'setAccessible(Z)V', (v, a) {
    method(a[0]).accessible = a[1] != 0;
    return null;
  });
  native(
    _method,
    'getName()Ljava/lang/String;',
    (v, a) => v.intern(method(a[0]).name),
  );
  native(_method, 'getModifiers()I', (v, a) => method(a[0]).metadata.access);
  native(
    _method,
    'getDeclaringClass()Ljava/lang/Class;',
    (v, a) => v.typeObject(method(a[0]).metadata.owner),
  );
  native(
    _method,
    'getReturnType()Ljava/lang/Class;',
    (v, a) => v.typeObject(method(a[0]).returnType),
  );
  native(_method, 'getParameterTypes()[Ljava/lang/Class;', (v, a) {
    final parameters = _parameters(method(a[0]).metadata.key);
    final array = v.array('[Ljava/lang/Class;', parameters.length);
    for (var n = 0; n < parameters.length; n++) {
      array.values[n] = v.typeObject(parameters[n]);
    }
    return array;
  });
  native(
    _method,
    'invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;',
    (v, a) {
      final reflected = method(a[0]), metadata = reflected.metadata;
      final isStatic = metadata.access & 8 != 0;
      if (!reflected.accessible &&
          !allowed(metadata.owner, metadata.access, caller(), a[1])) {
        v.throwJava('Ljava/lang/IllegalAccessException;', metadata.key);
      }
      if (!isStatic) {
        v.object(a[1]);
        if (!v.instanceOf(a[1], metadata.owner)) {
          v.throwJava(
            'Ljava/lang/IllegalArgumentException;',
            'Object is not an instance of declaring class',
          );
        }
      }
      final supplied = v.isNull(a[2]) ? <Object?>[] : v.asArray(a[2]).values;
      final expected = _parameters(metadata.key);
      if (supplied.length != expected.length) {
        v.throwJava(
          'Ljava/lang/IllegalArgumentException;',
          'Wrong number of arguments',
        );
      }
      final arguments = <Object?>[if (!isStatic) a[1]];
      for (var n = 0; n < expected.length; n++) {
        arguments.addAll(argument(supplied[n], expected[n]));
      }
      final kind = isStatic
          ? 'static'
          : metadata.access & 2 != 0
          ? 'direct'
          : 'virtual';
      if (!isStatic) return invokeTarget(reflected, arguments, kind);
      // Class-initializer failures are not target-method failures.
      return dalvikThen(
        () {
          v.initialize(metadata.owner);
          return null;
        },
        (_) => invokeTarget(reflected, arguments, kind),
        methodKey: '${metadata.key} <reflective initialization>',
      );
    },
  );
  for (final name in ['getTargetException', 'getCause']) {
    native(
      _targetException,
      '$name()Ljava/lang/Throwable;',
      (v, a) => v.object(a[0]).fields[_causeField],
    );
  }
  native(_class, 'newInstance()Ljava/lang/Object;', (v, a) {
    final owner = className(a[0]), definition = v.classes[className(a[0])];
    if (owner.startsWith('[') || owner.length == 1) {
      v.throwJava('Ljava/lang/InstantiationException;', owner);
    }
    if (definition == null) {
      throw MissingDalvikBridge('Class.newInstance unported class $owner');
    }
    if (definition.access & 0x600 != 0) {
      v.throwJava('Ljava/lang/InstantiationException;', owner);
    }
    final constructor = lookup(owner, '<init>', [], false);
    if (constructor == null) {
      v.throwJava(
        'Ljava/lang/InstantiationException;',
        '$owner has no zero-argument constructor',
      );
    }
    if (!allowed(owner, constructor.access, caller(), null)) {
      v.throwJava('Ljava/lang/IllegalAccessException;', owner);
    }
    return dalvikThen(
      () => v.allocate(owner),
      (object) => dalvikThen(
        () => v.call(constructor.key, [object], kind: 'direct'),
        (_) => object,
        methodKey: '$owner <reflective constructor>',
      ),
      methodKey: '$owner <reflective allocation>',
    );
  });
}
