import 'dart:async';

import '../compat/java_numbers.dart';
import 'cooperative.dart';

typedef DalvikBody = Object? Function(DalvikRuntime vm, List<Object?> args);

class DalvikObject {
  DalvikObject(this.className, {this.nativeValue});
  final String className;
  final Map<String, Object?> fields = {};
  Object? nativeValue;
}

class DalvikArray extends DalvikObject {
  DalvikArray(String descriptor, int length)
    : values = List<Object?>.filled(
        length,
        descriptor[1] == 'L' || descriptor[1] == '[' ? null : 0,
      ),
      super(descriptor);
  final List<Object?> values;
  String get component => className.substring(1);
}

class DalvikMethod {
  const DalvikMethod(this.key, this.access, this.body);
  final String key;
  final int access;
  final DalvikBody? body;
  String get owner => key.substring(0, key.indexOf('->'));
  String get member => key.substring(key.indexOf('->') + 2);
}

class DalvikClass {
  DalvikClass(
    this.name, {
    this.access = 0x1,
    this.superclass,
    this.interfaces = const [],
    Map<String, Object?>? staticFields,
    Map<String, String>? instanceFields,
  }) : staticFields = staticFields ?? {},
       instanceFields = instanceFields ?? {};
  final String name;
  final int access;
  final String? superclass;
  final List<String> interfaces;
  final Map<String, Object?> staticFields;
  final Map<String, String> instanceFields;
  int initialization = 0;
  DalvikThrown? initializationFailure;
  Object? initializationOwner;
  Completer<void>? initializationDone;
}

class DalvikThrown implements Exception {
  const DalvikThrown(this.object);
  final DalvikObject object;
  @override
  String toString() => '${object.className}: ${object.nativeValue ?? ''}';
}

/// Fatal integration error: must never be mistaken for an in-game Java error.
class MissingDalvikBridge extends Error {
  MissingDalvikBridge(this.operation);
  final String operation;
  @override
  String toString() => 'Unported runtime operation: $operation';
}

class DalvikRuntime {
  final Map<String, DalvikClass> classes = {};
  final Map<String, DalvikMethod> methods = {};
  final Map<String, DalvikBody> nativeMethods = {};
  final Map<String, DalvikObject> _strings = {};
  final Map<String, DalvikObject> _typeObjects = {};
  final Map<DalvikObject, int> _monitors = Map.identity();
  int executedInstructions = 0;
  int? instructionLimit;
  int Function()? randomSeedSource;
  int Function()? wallClockMillis;
  int Function()? monotonicMillis;
  final Map<String, String> systemProperties = {};
  final Set<String> availableClassNames = {};
  String? defaultLocaleLanguage;
  final List<String> diagnostics = [];
  void Function(String text)? diagnosticSink;
  final List<String> callStack = [];
  List<String> lastFailureStack = [];
  final Map<DalvikObject, List<String>> throwableTraces = Map.identity();
  List<int>? Function(String path)? resourceLoader;
  void Function(Object? lock)? monitorEnterHook;
  void Function(Object? lock)? monitorExitHook;
  Object Function()? currentThreadHook;
  final Object _mainThread = Object();

  Never suspendUntil(Future<Object?> future) => throw DalvikPause(future);

  void logDiagnostic(String text) {
    diagnostics.add(text);
    diagnosticSink?.call(text);
  }

  DalvikThrown? javaException(Object error) {
    if (error is DalvikThrown) return error;
    if (error is JavaArithmeticException) {
      return DalvikThrown(
        DalvikObject(
          'Ljava/lang/ArithmeticException;',
          nativeValue: error.message,
        ),
      );
    }
    return null;
  }

  void registerClass(DalvikClass definition) {
    if (classes.containsKey(definition.name)) {
      throw StateError('Class registered twice: ${definition.name}');
    }
    classes[definition.name] = definition;
  }

  void registerExternalClass(
    String name, {
    String? superclass = 'Ljava/lang/Object;',
    List<String> interfaces = const [],
  }) {
    classes.putIfAbsent(
      name,
      () => DalvikClass(name, superclass: superclass, interfaces: interfaces),
    );
  }

  void registerNative(String key, DalvikBody body) {
    if (nativeMethods.containsKey(key)) {
      throw StateError('Duplicate bridge $key');
    }
    nativeMethods[key] = body;
  }

  void registerMethod(DalvikMethod method) {
    if (methods.containsKey(method.key)) {
      throw StateError('Duplicate method ${method.key}');
    }
    methods[method.key] = method;
  }

  void tick(String method, int pc) {
    executedInstructions++;
    if (instructionLimit != null && executedInstructions > instructionLimit!) {
      throw StateError('Instruction limit reached at $method:$pc');
    }
  }

  bool isNull(Object? value) => value == null || value is int && value == 0;

  DalvikObject object(Object? value) {
    if (isNull(value)) throwJava('Ljava/lang/NullPointerException;');
    if (value is! DalvikObject) {
      throw StateError('A primitive was used as an object: $value');
    }
    return value;
  }

  DalvikObject newString(String text) =>
      DalvikObject('Ljava/lang/String;', nativeValue: text);
  DalvikObject intern(String text) =>
      _strings.putIfAbsent(text, () => newString(text));
  String string(Object? value) => object(value).nativeValue as String;
  DalvikObject typeObject(String name) => _typeObjects.putIfAbsent(
    name,
    () => DalvikObject('Ljava/lang/Class;', nativeValue: name),
  );

  int nextRandomSeed() {
    final source = randomSeedSource;
    if (source == null) {
      throw MissingDalvikBridge('platform random seed source');
    }
    return source();
  }

  void initialize(String name) {
    final definition = classes[name];
    if (definition == null) throw MissingDalvikBridge('class $name');
    if (definition.initialization == 2) return;
    final thread = currentThreadHook?.call() ?? _mainThread;
    if (definition.initialization == 1) {
      if (identical(definition.initializationOwner, thread)) return;
      suspendUntil(
        definition.initializationDone!.future.then((_) {
          initialize(name);
          return null;
        }),
      );
    }
    if (definition.initializationFailure != null) {
      throwJava('Ljava/lang/NoClassDefFoundError;', name);
    }
    definition.initialization = 1;
    definition.initializationOwner = thread;
    definition.initializationDone = Completer<void>();
    void finish() {
      definition.initialization = 2;
      definition.initializationOwner = null;
      definition.initializationDone!.complete();
    }

    Never fail(Object error, StackTrace trace) {
      definition.initialization = 0;
      definition.initializationOwner = null;
      if (error is DalvikThrown) definition.initializationFailure = error;
      definition.initializationDone!.complete();
      if (error is DalvikThrown &&
          !instanceOf(error.object, 'Ljava/lang/Error;')) {
        throwJava('Ljava/lang/ExceptionInInitializerError;', error.toString());
      }
      Error.throwWithStackTrace(error, trace);
    }

    try {
      dalvikThen(
        () {
          if (definition.superclass != null) initialize(definition.superclass!);
          return null;
        },
        (_) {
          final initializer = methods['$name-><clinit>()V'];
          return initializer == null
              ? null
              : _execute(initializer.key, const []);
        },
        methodKey: '$name <initialize superclass>',
      );
      finish();
    } on DalvikPause catch (pause) {
      pause.addFrame(
        DalvikResumeFrame(
          methodKey: '$name <finish initializer>',
          pc: -1,
          resume: (completion) {
            try {
              completion.unwrap();
              finish();
              return null;
            } catch (error, trace) {
              fail(error, trace);
            }
          },
        ),
      );
      rethrow;
    } catch (error, trace) {
      fail(error, trace);
    }
  }

  DalvikObject allocate(String name) {
    return dalvikThen(
      () {
        initialize(name);
        return null;
      },
      (_) => _allocateInitialized(name),
      methodKey: '$name <allocate>',
    ) as DalvikObject;
  }

  DalvikObject _allocateInitialized(String name) {
    final instance = DalvikObject(name);
    String? current = name;
    while (current != null) {
      final definition = classes[current];
      if (definition == null) throw MissingDalvikBridge('allocation $current');
      for (final field in definition.instanceFields.entries) {
        instance.fields[field.key] = defaultValue(field.value);
      }
      current = definition.superclass;
    }
    return instance;
  }

  static Object? defaultValue(String type) =>
      type.startsWith('L') || type.startsWith('[') ? null : 0;

  DalvikArray array(String descriptor, int length) {
    if (length < 0) throwJava('Ljava/lang/NegativeArraySizeException;');
    return DalvikArray(descriptor, length);
  }

  DalvikArray asArray(Object? value) {
    final result = object(value);
    if (result is! DalvikArray) {
      throw StateError('Not an array: ${result.className}');
    }
    return result;
  }

  Object? arrayGet(Object? value, int index) {
    final array = asArray(value);
    if (index < 0 || index >= array.values.length) {
      throwJava('Ljava/lang/ArrayIndexOutOfBoundsException;', '$index');
    }
    return array.values[index];
  }

  void arrayPut(Object? value, int index, Object? item) {
    final target = asArray(value);
    if (index < 0 || index >= target.values.length) {
      throwJava('Ljava/lang/ArrayIndexOutOfBoundsException;', '$index');
    }
    final component = target.component;
    if (component.startsWith('L') || component.startsWith('[')) {
      if (!isNull(item) && !instanceOf(item, component)) {
        throwJava('Ljava/lang/ArrayStoreException;');
      }
      target.values[index] = isNull(item) ? null : item;
    } else {
      final number = item as int;
      target.values[index] = switch (component) {
        'B' => number.toSigned(8),
        'S' => number.toSigned(16),
        'C' => number.toUnsigned(16),
        'Z' => number & 1,
        'I' || 'F' => number.toSigned(32),
        'J' || 'D' => number,
        _ => throw MissingDalvikBridge('array component $component'),
      };
    }
  }

  bool instanceOf(Object? value, String expected) {
    if (isNull(value)) return false;
    return assignable(object(value).className, expected);
  }

  bool assignable(String actual, String expected) {
    if (actual == expected || expected == 'Ljava/lang/Object;') return true;
    if (actual.startsWith('[')) {
      if (expected == 'Ljava/lang/Cloneable;' ||
          expected == 'Ljava/io/Serializable;') {
        return true;
      }
      if (!expected.startsWith('[')) return false;
      final a = actual.substring(1);
      final b = expected.substring(1);
      if (a.length == 1 || b.length == 1) return a == b;
      return assignable(a, b);
    }
    final definition = classes[actual];
    if (definition == null) throw MissingDalvikBridge('type hierarchy $actual');
    return definition.interfaces.any((type) => assignable(type, expected)) ||
        definition.superclass != null &&
            assignable(definition.superclass!, expected);
  }

  void checkCast(Object? value, String type) {
    if (!isNull(value) && !instanceOf(value, type)) {
      throwJava('Ljava/lang/ClassCastException;', type);
    }
  }

  bool registerEquals(Object? a, Object? b) {
    if (isNull(a) && isNull(b)) return true;
    if (a is int && b is int) return a == b;
    return identical(a, b);
  }

  Object? getField(Object? receiver, String key) {
    final instance = object(receiver);
    return instance.fields[_instanceFieldKey(instance, key)];
  }

  void putField(Object? receiver, String key, Object? value) {
    final instance = object(receiver);
    instance.fields[_instanceFieldKey(instance, key)] = value;
  }

  String _instanceFieldKey(DalvikObject instance, String key) {
    if (instance.fields.containsKey(key)) return key;
    final member = key.substring(key.indexOf('->'));
    String? owner = key.substring(0, key.indexOf('->'));
    while (owner != null) {
      final candidate = '$owner$member';
      if (instance.fields.containsKey(candidate)) return candidate;
      owner = classes[owner]?.superclass;
    }
    throw MissingDalvikBridge('field $key');
  }

  (DalvikClass, String) _staticField(String owner, String key) {
    final member = key.substring(key.indexOf('->'));
    final definition = classes[owner];
    if (definition == null) throw MissingDalvikBridge('field owner $owner');
    final candidate = '$owner$member';
    if (definition.staticFields.containsKey(candidate)) {
      return (definition, candidate);
    }
    for (final interface in definition.interfaces) {
      try {
        return _staticField(interface, key);
      } on MissingDalvikBridge {
        /* Continue field resolution through the hierarchy. */
      }
    }
    if (definition.superclass != null) {
      return _staticField(definition.superclass!, key);
    }
    throw MissingDalvikBridge('static field $key');
  }

  Object? getStatic(String owner, String key) {
    final (definition, resolved) = _staticField(owner, key);
    return dalvikThen(
      () {
        initialize(definition.name);
        return null;
      },
      (_) => definition.staticFields[resolved],
      methodKey: '$key <get static>',
    );
  }

  void putStatic(String owner, String key, Object? value) {
    final (definition, resolved) = _staticField(owner, key);
    dalvikThen(
      () {
        initialize(definition.name);
        return null;
      },
      (_) {
        definition.staticFields[resolved] = value;
        return null;
      },
      methodKey: '$key <put static>',
    );
  }

  Object? call(
    String key,
    List<Object?> args, {
    required String kind,
    String? caller,
  }) {
    final arrow = key.indexOf('->');
    final owner = key.substring(0, arrow);
    final member = key.substring(arrow + 2);
    if (kind == 'static') {
      String? current = owner;
      while (current != null) {
        final candidate = '$current->$member';
        if (methods.containsKey(candidate) ||
            nativeMethods.containsKey(candidate)) {
          final declaringClass = current;
          return dalvikThen(
            () {
              initialize(declaringClass);
              return null;
            },
            (_) => _execute(candidate, args),
            methodKey: '$key <invoke static>',
          );
        }
        current = classes[current]?.superclass;
      }
      throw MissingDalvikBridge('static method $key');
    }
    final receiver = object(args.first);
    if (kind == 'direct') return _execute(key, args);
    String? current = kind == 'super'
        ? classes[caller]?.superclass
        : receiver.className;
    if (current == null) throw MissingDalvikBridge('super owner for $caller');
    while (current != null) {
      final candidate = '$current->$member';
      if (nativeMethods.containsKey(candidate) ||
          methods.containsKey(candidate)) {
        return _execute(candidate, args);
      }
      current = current.startsWith('[')
          ? 'Ljava/lang/Object;'
          : classes[current]?.superclass;
    }
    // Interface default methods are addressed by their declared owner.
    if (methods.containsKey(key) || nativeMethods.containsKey(key)) {
      return _execute(key, args);
    }
    throw MissingDalvikBridge('method $key on ${receiver.className}');
  }

  /// Reinstates the complete Java caller chain captured at a suspension point.
  /// The previous host/thread context is restored even if the method pauses
  /// again, throws, or completes through a nested native continuation.
  T withCallFrame<T>(
    String key,
    T Function() action, {
    List<String>? restoredStack,
  }) {
    final previous = List<String>.of(callStack);
    if (restoredStack != null) {
      if (restoredStack.isEmpty || restoredStack.last != key) {
        throw StateError('Invalid restored Java call stack for $key');
      }
      callStack
        ..clear()
        ..addAll(restoredStack);
    } else {
      callStack.add(key);
    }
    try {
      return action();
    } on DalvikPause {
      rethrow;
    } catch (_) {
      if (lastFailureStack.isEmpty)
        lastFailureStack = List.of(callStack.reversed);
      rethrow;
    } finally {
      callStack
        ..clear()
        ..addAll(previous);
    }
  }

  Object? _execute(String key, List<Object?> args) {
    if (callStack.isEmpty) lastFailureStack = [];
    callStack.add(key);
    try {
      return _executeBody(key, args);
    } on DalvikPause {
      rethrow;
    } catch (_) {
      if (lastFailureStack.isEmpty) {
        lastFailureStack = List.of(callStack.reversed);
      }
      rethrow;
    } finally {
      callStack.removeLast();
    }
  }

  Object? _executeBody(String key, List<Object?> args) {
    final bridge = nativeMethods[key];
    if (bridge != null) return bridge(this, args);
    final method = methods[key];
    final body = method?.body;
    if (body == null) throw MissingDalvikBridge(key);
    final synchronized = method!.access & 0x20 != 0;
    final lock = !synchronized
        ? null
        : method.access & 8 != 0
        ? typeObject(method.owner)
        : object(args.first);
    Object? execute() {
      try {
        return body(this, args);
      } on JavaArithmeticException catch (error) {
        throwJava('Ljava/lang/ArithmeticException;', error.message);
      }
    }

    if (!synchronized) return execute();
    return dalvikThen(
      () {
        monitorEnter(lock);
        return null;
      },
      (_) => dalvikFinally(
        execute,
        () => monitorExit(lock),
        methodKey: '$key <monitor cleanup>',
      ),
      methodKey: '$key <monitor acquire>',
    );
  }

  void monitorEnter(Object? value) {
    final lock = object(value);
    if (monitorEnterHook != null) {
      monitorEnterHook!(lock);
      return;
    }
    _monitors[lock] = (_monitors[lock] ?? 0) + 1;
  }

  void monitorExit(Object? value) {
    final lock = object(value);
    if (monitorExitHook != null) {
      monitorExitHook!(lock);
      return;
    }
    final depth = _monitors[lock] ?? 0;
    if (depth == 0) throwJava('Ljava/lang/IllegalMonitorStateException;');
    if (depth == 1) {
      _monitors.remove(lock);
    } else {
      _monitors[lock] = depth - 1;
    }
  }

  Never throwJava(String type, [String? message]) {
    final error = DalvikObject(type, nativeValue: message);
    throwableTraces[error] = List.of(callStack.reversed);
    throw DalvikThrown(error);
  }
}
