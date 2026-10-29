import 'runtime.dart';
import 'numbers.dart';

const _object = 'Ljava/lang/Object;';
const _collection = 'Ljava/util/Collection;';
const _list = 'Ljava/util/List;';
const _iterator = 'Ljava/util/Iterator;';
const _enumeration = 'Ljava/util/Enumeration;';

/// Calendar fields, timezone rules and locale week rules must come from the
/// host. Calendar is not silently replaced with UTC or a fixed offset.
abstract interface class JavaCalendarPlatform {
  Object createCalendar(int epochMillis);
  int getField(Object calendar, int field);
  void setField(Object calendar, int field, int value);
  int getMillis(Object calendar);
  void setMillis(Object calendar, int millis);
  Object defaultTimeZone();
  int rawOffset(Object timeZone);
}

abstract interface class JavaCalendarArithmetic {
  void addField(Object calendar, int field, int amount);
}

Object? _nullable(DalvikRuntime vm, Object? value) =>
    vm.isNull(value) ? null : vm.object(value);
bool _equal(DalvikRuntime vm, Object? a, Object? b) {
  if (vm.isNull(a)) return vm.isNull(b);
  if (identical(a, b)) return true;
  return vm.call('$_object->equals(Ljava/lang/Object;)Z', [
        a,
        _nullable(vm, b),
      ], kind: 'virtual') ==
      1;
}

int _hash(DalvikRuntime vm, Object? key) => vm.isNull(key)
    ? 0
    : vm.call('$_object->hashCode()I', [key], kind: 'virtual') as int;

abstract class _CollectionState {
  int get modifications;
  int get length;
  Object? at(int index);
  bool add(DalvikRuntime vm, Object? value);
  Object? removeAt(DalvikRuntime vm, int index);
  void clear(DalvikRuntime vm);
  List<Object?> snapshot() => List.generate(length, at);
  int indexOf(DalvikRuntime vm, Object? value) {
    for (var i = 0; i < length; i++) {
      if (_equal(vm, value, at(i))) return i;
    }
    return -1;
  }
}

class _ListState extends _CollectionState {
  _ListState([
    List<Object?>? values,
    this.fixed = false,
    this.readOnly = false,
    this.backingArray,
  ]) : values = values ?? [];
  final List<Object?> values;
  final bool fixed;
  final bool readOnly;
  final DalvikArray? backingArray;
  @override
  int modifications = 0;
  @override
  int get length => values.length;
  @override
  Object? at(int index) => values[index];
  void requireResize(DalvikRuntime vm) {
    if (fixed || readOnly) {
      vm.throwJava('Ljava/lang/UnsupportedOperationException;');
    }
  }

  @override
  bool add(DalvikRuntime vm, Object? value) {
    requireResize(vm);
    values.add(_nullable(vm, value));
    modifications++;
    return true;
  }

  @override
  Object? removeAt(DalvikRuntime vm, int index) {
    requireResize(vm);
    modifications++;
    return values.removeAt(index);
  }

  Object? set(DalvikRuntime vm, int index, Object? value) {
    if (readOnly) vm.throwJava('Ljava/lang/UnsupportedOperationException;');
    final old = values[index];
    if (backingArray case final array?) {
      vm.arrayPut(array, index, value);
    } else {
      values[index] = _nullable(vm, value);
    }
    return old;
  }

  @override
  void clear(DalvikRuntime vm) {
    requireResize(vm);
    values.clear();
    modifications++;
  }
}

class _Entry {
  _Entry(this.key, this.value, this.hash, this.allowNull);
  final Object? key;
  Object? value;
  final int hash;
  final bool allowNull;
}

class _MapState {
  _MapState(this.allowNull);
  final bool allowNull;
  final List<_Entry> entries = [];
  int modifications = 0;
  int index(DalvikRuntime vm, Object? key) {
    if (!allowNull && vm.isNull(key)) {
      vm.throwJava('Ljava/lang/NullPointerException;');
    }
    final hash = _hash(vm, key);
    return _hashedIndex(vm, key, hash);
  }

  int _hashedIndex(DalvikRuntime vm, Object? key, int hash) {
    return entries.indexWhere(
      (entry) =>
          entry.hash == hash &&
          (allowNull ? _equal(vm, key, entry.key) : _equal(vm, entry.key, key)),
    );
  }

  Object? put(DalvikRuntime vm, Object? key, Object? value) {
    if (!allowNull && (vm.isNull(key) || vm.isNull(value))) {
      vm.throwJava('Ljava/lang/NullPointerException;');
    }
    key = _nullable(vm, key);
    value = _nullable(vm, value);
    final hash = _hash(vm, key);
    final i = _hashedIndex(vm, key, hash);
    if (i >= 0) {
      final old = entries[i].value;
      entries[i].value = value;
      return old;
    }
    entries.add(_Entry(key, value, hash, allowNull));
    modifications++;
    return null;
  }

  Object? remove(DalvikRuntime vm, Object? key) {
    final i = index(vm, key);
    if (i < 0) return null;
    modifications++;
    return entries.removeAt(i).value;
  }

  void clear() {
    entries.clear();
    modifications++;
  }
}

enum _ViewType { keys, mappedValues, entries }

class _MapView extends _CollectionState {
  _MapView(this.map, this.type);
  final _MapState map;
  final _ViewType type;
  @override
  int get modifications => map.modifications;
  @override
  int get length => map.entries.length;
  @override
  int indexOf(DalvikRuntime vm, Object? value) {
    if (type == _ViewType.keys) return map.index(vm, value);
    if (type == _ViewType.mappedValues) {
      if (!map.allowNull && vm.isNull(value)) {
        vm.throwJava('Ljava/lang/NullPointerException;');
      }
      return super.indexOf(vm, value);
    }
    if (!vm.instanceOf(value, 'Ljava/util/Map\$Entry;')) return -1;
    final key = vm.call('Ljava/util/Map\$Entry;->getKey()Ljava/lang/Object;', [
      value,
    ], kind: 'interface');
    final candidateValue = vm.call(
      'Ljava/util/Map\$Entry;->getValue()Ljava/lang/Object;',
      [value],
      kind: 'interface',
    );
    final i = map.index(vm, key);
    return i >= 0 && _equal(vm, map.entries[i].value, candidateValue) ? i : -1;
  }

  @override
  Object? at(int index) {
    final entry = map.entries[index];
    return switch (type) {
      _ViewType.keys => entry.key,
      _ViewType.mappedValues => entry.value,
      _ViewType.entries => DalvikObject(
        'Ljava/util/Map\$Entry;',
        nativeValue: entry,
      ),
    };
  }

  @override
  bool add(DalvikRuntime vm, Object? value) =>
      vm.throwJava('Ljava/lang/UnsupportedOperationException;');
  @override
  Object? removeAt(DalvikRuntime vm, int index) {
    final value = at(index);
    map.entries.removeAt(index);
    map.modifications++;
    return value;
  }

  @override
  void clear(DalvikRuntime vm) => map.clear();
}

class _SetState extends _MapView {
  _SetState() : super(_MapState(true), _ViewType.keys);
  @override
  int indexOf(DalvikRuntime vm, Object? value) => map.index(vm, value);
  @override
  bool add(DalvikRuntime vm, Object? value) {
    value = _nullable(vm, value);
    final hash = _hash(vm, value);
    if (map._hashedIndex(vm, value, hash) >= 0) return false;
    map.entries.add(_Entry(value, value, hash, true));
    map.modifications++;
    return true;
  }
}

class _Cursor {
  _Cursor(this.collection, {this.failFast = true})
    : expected = collection.modifications;
  final _CollectionState collection;
  final bool failFast;
  int expected;
  int position = 0;
  int last = -1;
  void check(DalvikRuntime vm) {
    if (failFast && expected != collection.modifications) {
      vm.throwJava('Ljava/util/ConcurrentModificationException;');
    }
  }

  Object? next(DalvikRuntime vm) {
    check(vm);
    if (position >= collection.length) {
      vm.throwJava('Ljava/util/NoSuchElementException;');
    }
    last = position;
    return collection.at(position++);
  }

  void remove(DalvikRuntime vm) {
    if (last < 0) vm.throwJava('Ljava/lang/IllegalStateException;');
    check(vm);
    collection.removeAt(vm, last);
    position = last;
    last = -1;
    expected = collection.modifications;
  }
}

class _EnumerationDelegate {
  _EnumerationDelegate(this.iterator);
  final Object? iterator;
}

_CollectionState _state(DalvikRuntime vm, Object? value) =>
    vm.object(value).nativeValue as _CollectionState;
List<Object?> _elements(DalvikRuntime vm, Object? value) {
  final object = vm.object(value);
  if (object.nativeValue case final _CollectionState state) {
    return state.snapshot();
  }
  final iterator = vm.call('$_collection->iterator()Ljava/util/Iterator;', [
    object,
  ], kind: 'interface');
  final result = <Object?>[];
  while (vm.call('$_iterator->hasNext()Z', [iterator], kind: 'interface') ==
      1) {
    result.add(
      vm.call('$_iterator->next()Ljava/lang/Object;', [
        iterator,
      ], kind: 'interface'),
    );
  }
  return result;
}

/// Enumeration adapter used by other native bridges, such as ZipFile.entries.
DalvikObject javaEnumeration(Iterable<Object?> values) => DalvikObject(
  _enumeration,
  nativeValue: _Cursor(_ListState(values.toList()), failFast: false),
);

void registerJavaCollections(
  DalvikRuntime vm, {
  JavaCalendarPlatform? calendarPlatform,
}) {
  vm.registerExternalClass('Ljava/lang/Iterable;');
  for (final name in [
    'Collection',
    'List',
    'Set',
    'Map',
    'Map\$Entry',
    'Iterator',
    'Enumeration',
    'RandomAccess',
  ]) {
    vm.registerExternalClass(
      'Ljava/util/$name;',
      interfaces: name == 'List' || name == 'Set'
          ? [_collection]
          : name == 'Collection'
          ? ['Ljava/lang/Iterable;']
          : [],
    );
  }
  for (final name in [
    'NoSuchElementException',
    'ConcurrentModificationException',
    'EmptyStackException',
  ]) {
    vm.registerExternalClass(
      'Ljava/util/$name;',
      superclass: 'Ljava/lang/RuntimeException;',
    );
  }
  for (final name in ['ArrayList', 'Vector', 'Stack']) {
    vm.registerExternalClass(
      'Ljava/util/$name;',
      superclass: name == 'Stack' ? 'Ljava/util/Vector;' : _object,
      interfaces: [
        _list,
        _collection,
        'Ljava/lang/Cloneable;',
        'Ljava/io/Serializable;',
      ],
    );
  }
  vm.registerExternalClass(
    'Ljava/util/HashSet;',
    interfaces: ['Ljava/util/Set;', _collection],
  );
  for (final name in ['HashMap', 'Hashtable']) {
    vm.registerExternalClass(
      'Ljava/util/$name;',
      interfaces: ['Ljava/util/Map;'],
    );
  }
  for (final name in [
    'Collections',
    'Arrays',
    'Date',
    'Calendar',
    'TimeZone',
  ]) {
    vm.registerExternalClass('Ljava/util/$name;');
  }
  vm.registerExternalClass(
    'Ljava/util/GregorianCalendar;',
    superclass: 'Ljava/util/Calendar;',
  );
  void bind(String owner, String method, DalvikBody body) =>
      vm.registerNative('Ljava/util/$owner;->$method', body);
  void index(
    DalvikRuntime v,
    _CollectionState state,
    int i, {
    bool insertion = false,
    bool vector = false,
  }) {
    if (i < 0 || i >= state.length + (insertion ? 1 : 0)) {
      v.throwJava(
        vector
            ? 'Ljava/lang/ArrayIndexOutOfBoundsException;'
            : 'Ljava/lang/IndexOutOfBoundsException;',
        '$i',
      );
    }
  }

  for (final owner in ['ArrayList', 'Vector']) {
    bind(owner, '<init>()V', (v, a) {
      v.object(a[0]).nativeValue = _ListState();
      return null;
    });
    bind(owner, '<init>(I)V', (v, a) {
      if ((a[1] as int) < 0) {
        v.throwJava('Ljava/lang/IllegalArgumentException;');
      }
      v.object(a[0]).nativeValue = _ListState();
      return null;
    });
    bind(owner, '<init>(Ljava/util/Collection;)V', (v, a) {
      v.object(a[0]).nativeValue = _ListState(_elements(v, a[1]));
      return null;
    });
  }
  bind('Stack', '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = _ListState();
    return null;
  });
  bind('HashSet', '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = _SetState();
    return null;
  });
  for (final owner in [
    'ArrayList',
    'Vector',
    'List',
    'Collection',
    'Set',
    'HashSet',
  ]) {
    bind(owner, 'size()I', (v, a) => _state(v, a[0]).length);
    bind(owner, 'isEmpty()Z', (v, a) => _state(v, a[0]).length == 0 ? 1 : 0);
    bind(
      owner,
      'contains(Ljava/lang/Object;)Z',
      (v, a) => _state(v, a[0]).indexOf(v, a[1]) >= 0 ? 1 : 0,
    );
    bind(
      owner,
      'add(Ljava/lang/Object;)Z',
      (v, a) => _state(v, a[0]).add(v, a[1]) ? 1 : 0,
    );
    bind(owner, 'addAll(Ljava/util/Collection;)Z', (v, a) {
      final state = _state(v, a[0]);
      final items = _elements(v, a[1]);
      var changed = false;
      for (final item in items) {
        changed = state.add(v, item) || changed;
      }
      return changed ? 1 : 0;
    });
    bind(owner, 'clear()V', (v, a) {
      _state(v, a[0]).clear(v);
      return null;
    });
    bind(owner, 'remove(Ljava/lang/Object;)Z', (v, a) {
      final state = _state(v, a[0]);
      final i = state.indexOf(v, a[1]);
      if (i < 0) return 0;
      state.removeAt(v, i);
      return 1;
    });
    bind(
      owner,
      'iterator()Ljava/util/Iterator;',
      (v, a) => DalvikObject(_iterator, nativeValue: _Cursor(_state(v, a[0]))),
    );
    bind(owner, 'toArray([Ljava/lang/Object;)[Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]);
      final supplied = v.asArray(a[1]);
      final result = supplied.values.length < state.length
          ? v.array(supplied.className, state.length)
          : supplied;
      for (var i = 0; i < state.length; i++) {
        v.arrayPut(result, i, state.at(i));
      }
      if (result.values.length > state.length) {
        v.arrayPut(result, state.length, null);
      }
      return result;
    });
    bind(owner, 'toArray()[Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]);
      final result = v.array('[Ljava/lang/Object;', state.length);
      for (var i = 0; i < state.length; i++) {
        v.arrayPut(result, i, state.at(i));
      }
      return result;
    });
  }
  for (final owner in ['ArrayList', 'Vector', 'List']) {
    bind(owner, 'get(I)Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]);
      index(v, state, a[1] as int, vector: owner == 'Vector');
      return state.at(a[1] as int);
    });
    bind(owner, 'set(ILjava/lang/Object;)Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]) as _ListState;
      index(v, state, a[1] as int, vector: owner == 'Vector');
      return state.set(v, a[1] as int, a[2]);
    });
    bind(
      owner,
      'indexOf(Ljava/lang/Object;)I',
      (v, a) => _state(v, a[0]).indexOf(v, a[1]),
    );
    bind(owner, 'remove(I)Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]);
      index(v, state, a[1] as int, vector: owner == 'Vector');
      return state.removeAt(v, a[1] as int);
    });
  }
  bind('Vector', 'addElement(Ljava/lang/Object;)V', (v, a) {
    _state(v, a[0]).add(v, a[1]);
    return null;
  });
  bind('Vector', 'elementAt(I)Ljava/lang/Object;', (v, a) {
    final state = _state(v, a[0]);
    index(v, state, a[1] as int, vector: true);
    return state.at(a[1] as int);
  });
  bind('Vector', 'setElementAt(Ljava/lang/Object;I)V', (v, a) {
    final state = _state(v, a[0]) as _ListState;
    index(v, state, a[2] as int, vector: true);
    state.set(v, a[2] as int, a[1]);
    return null;
  });
  bind('Vector', 'removeElementAt(I)V', (v, a) {
    final state = _state(v, a[0]);
    index(v, state, a[1] as int, vector: true);
    state.removeAt(v, a[1] as int);
    return null;
  });
  bind('Vector', 'removeAllElements()V', (v, a) {
    _state(v, a[0]).clear(v);
    return null;
  });
  for (final method in ['firstElement', 'lastElement']) {
    bind('Vector', '$method()Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]);
      if (state.length == 0) v.throwJava('Ljava/util/NoSuchElementException;');
      return state.at(method == 'firstElement' ? 0 : state.length - 1);
    });
  }
  bind(
    'Vector',
    'elements()Ljava/util/Enumeration;',
    (v, a) => DalvikObject(
      _enumeration,
      nativeValue: _Cursor(_state(v, a[0]), failFast: false),
    ),
  );
  bind('Stack', 'push(Ljava/lang/Object;)Ljava/lang/Object;', (v, a) {
    _state(v, a[0]).add(v, a[1]);
    return _nullable(v, a[1]);
  });
  for (final method in ['pop', 'peek']) {
    bind('Stack', '$method()Ljava/lang/Object;', (v, a) {
      final state = _state(v, a[0]);
      if (state.length == 0) v.throwJava('Ljava/util/EmptyStackException;');
      return method == 'pop'
          ? state.removeAt(v, state.length - 1)
          : state.at(state.length - 1);
    });
  }
  bind('Stack', 'empty()Z', (v, a) => _state(v, a[0]).length == 0 ? 1 : 0);
  bind('Stack', 'search(Ljava/lang/Object;)I', (v, a) {
    final state = _state(v, a[0]);
    for (var i = state.length - 1; i >= 0; i--) {
      if (_equal(v, a[1], state.at(i))) return state.length - i;
    }
    return -1;
  });
  bind('Iterator', 'hasNext()Z', (v, a) {
    final cursor = v.object(a[0]).nativeValue as _Cursor;
    return cursor.position < cursor.collection.length ? 1 : 0;
  });
  bind(
    'Iterator',
    'next()Ljava/lang/Object;',
    (v, a) => (v.object(a[0]).nativeValue as _Cursor).next(v),
  );
  bind('Iterator', 'remove()V', (v, a) {
    (v.object(a[0]).nativeValue as _Cursor).remove(v);
    return null;
  });
  bind('Enumeration', 'hasMoreElements()Z', (v, a) {
    final native = v.object(a[0]).nativeValue;
    if (native is _EnumerationDelegate) {
      return v.call('$_iterator->hasNext()Z', [
        native.iterator,
      ], kind: 'interface');
    }
    final cursor = native as _Cursor;
    return cursor.position < cursor.collection.length ? 1 : 0;
  });
  bind('Enumeration', 'nextElement()Ljava/lang/Object;', (v, a) {
    final native = v.object(a[0]).nativeValue;
    if (native is _EnumerationDelegate) {
      return v.call('$_iterator->next()Ljava/lang/Object;', [
        native.iterator,
      ], kind: 'interface');
    }
    return (native as _Cursor).next(v);
  });

  for (final owner in ['HashMap', 'Hashtable']) {
    bind(owner, '<init>()V', (v, a) {
      v.object(a[0]).nativeValue = _MapState(owner == 'HashMap');
      return null;
    });
  }
  for (final owner in ['HashMap', 'Hashtable', 'Map']) {
    _MapState map(DalvikRuntime v, List<Object?> a) =>
        v.object(a[0]).nativeValue as _MapState;
    bind(
      owner,
      'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',
      (v, a) => map(v, a).put(v, a[1], a[2]),
    );
    bind(owner, 'get(Ljava/lang/Object;)Ljava/lang/Object;', (v, a) {
      final state = map(v, a);
      final i = state.index(v, a[1]);
      return i < 0 ? null : state.entries[i].value;
    });
    bind(
      owner,
      'containsKey(Ljava/lang/Object;)Z',
      (v, a) => map(v, a).index(v, a[1]) >= 0 ? 1 : 0,
    );
    bind(
      owner,
      'containsValue(Ljava/lang/Object;)Z',
      (v, a) =>
          _MapView(map(v, a), _ViewType.mappedValues).indexOf(v, a[1]) >= 0
          ? 1
          : 0,
    );
    bind(
      owner,
      'remove(Ljava/lang/Object;)Ljava/lang/Object;',
      (v, a) => map(v, a).remove(v, a[1]),
    );
    bind(owner, 'size()I', (v, a) => map(v, a).entries.length);
    bind(owner, 'isEmpty()Z', (v, a) => map(v, a).entries.isEmpty ? 1 : 0);
    bind(owner, 'clear()V', (v, a) {
      map(v, a).clear();
      return null;
    });
    for (final type in _ViewType.values) {
      final method = type == _ViewType.keys
          ? 'keySet'
          : type == _ViewType.mappedValues
          ? 'values'
          : 'entrySet';
      final resultType = type == _ViewType.mappedValues
          ? _collection
          : 'Ljava/util/Set;';
      bind(
        owner,
        '$method()$resultType',
        (v, a) =>
            DalvikObject(resultType, nativeValue: _MapView(map(v, a), type)),
      );
    }
  }
  bind(
    'Hashtable',
    'contains(Ljava/lang/Object;)Z',
    (v, a) =>
        _MapView(
              v.object(a[0]).nativeValue as _MapState,
              _ViewType.mappedValues,
            ).indexOf(v, a[1]) >=
            0
        ? 1
        : 0,
  );
  for (final method in ['keys', 'elements']) {
    bind('Hashtable', '$method()Ljava/util/Enumeration;', (v, a) {
      final map = v.object(a[0]).nativeValue as _MapState;
      return DalvikObject(
        _enumeration,
        nativeValue: _Cursor(
          _MapView(
            map,
            method == 'keys' ? _ViewType.keys : _ViewType.mappedValues,
          ),
          failFast: false,
        ),
      );
    });
  }
  bind(
    'Map\$Entry',
    'getKey()Ljava/lang/Object;',
    (v, a) => (v.object(a[0]).nativeValue as _Entry).key,
  );
  bind(
    'Map\$Entry',
    'getValue()Ljava/lang/Object;',
    (v, a) => (v.object(a[0]).nativeValue as _Entry).value,
  );
  bind('Map\$Entry', 'setValue(Ljava/lang/Object;)Ljava/lang/Object;', (v, a) {
    final entry = v.object(a[0]).nativeValue as _Entry;
    if (!entry.allowNull && v.isNull(a[1])) {
      v.throwJava('Ljava/lang/NullPointerException;');
    }
    final old = entry.value;
    entry.value = _nullable(v, a[1]);
    return old;
  });
  bind('Map\$Entry', 'equals(Ljava/lang/Object;)Z', (v, a) {
    if (!v.instanceOf(a[1], 'Ljava/util/Map\$Entry;')) return 0;
    final entry = v.object(a[0]).nativeValue as _Entry;
    final key = v.call('Ljava/util/Map\$Entry;->getKey()Ljava/lang/Object;', [
      a[1],
    ], kind: 'interface');
    final value = v.call(
      'Ljava/util/Map\$Entry;->getValue()Ljava/lang/Object;',
      [a[1]],
      kind: 'interface',
    );
    return _equal(v, entry.key, key) && _equal(v, entry.value, value) ? 1 : 0;
  });
  bind('Map\$Entry', 'hashCode()I', (v, a) {
    final entry = v.object(a[0]).nativeValue as _Entry;
    return (_hash(v, entry.key) ^ _hash(v, entry.value)).toSigned(32);
  });
  for (final owner in ['ArrayList', 'Vector', 'List']) {
    bind(owner, 'equals(Ljava/lang/Object;)Z', (v, a) {
      if (identical(a[0], a[1])) return 1;
      if (!v.instanceOf(a[1], _list)) return 0;
      final lhs = _state(v, a[0]);
      final rhs = _elements(v, a[1]);
      if (lhs.length != rhs.length) return 0;
      for (var i = 0; i < rhs.length; i++) {
        if (!_equal(v, lhs.at(i), rhs[i])) return 0;
      }
      return 1;
    });
    bind(owner, 'hashCode()I', (v, a) {
      var hash = 1;
      final state = _state(v, a[0]);
      for (var i = 0; i < state.length; i++) {
        hash = (31 * hash + _hash(v, state.at(i))).toSigned(32);
      }
      return hash;
    });
  }
  for (final owner in ['Set', 'HashSet']) {
    bind(owner, 'equals(Ljava/lang/Object;)Z', (v, a) {
      if (identical(a[0], a[1])) return 1;
      if (!v.instanceOf(a[1], 'Ljava/util/Set;')) return 0;
      final state = _state(v, a[0]);
      final rhs = _elements(v, a[1]);
      if (state.length != rhs.length) return 0;
      try {
        return rhs.every((item) => state.indexOf(v, item) >= 0) ? 1 : 0;
      } on DalvikThrown catch (e) {
        if (e.object.className == 'Ljava/lang/NullPointerException;' ||
            e.object.className == 'Ljava/lang/ClassCastException;') {
          return 0;
        }
        rethrow;
      }
    });
    bind(owner, 'hashCode()I', (v, a) {
      var hash = 0;
      final state = _state(v, a[0]);
      for (var i = 0; i < state.length; i++) {
        hash = (hash + _hash(v, state.at(i))).toSigned(32);
      }
      return hash;
    });
  }
  for (final owner in ['HashMap', 'Hashtable', 'Map']) {
    bind(owner, 'equals(Ljava/lang/Object;)Z', (v, a) {
      if (identical(a[0], a[1])) return 1;
      if (!v.instanceOf(a[1], 'Ljava/util/Map;')) return 0;
      final state = v.object(a[0]).nativeValue as _MapState;
      if (state.entries.length !=
          v.call('Ljava/util/Map;->size()I', [a[1]], kind: 'interface')) {
        return 0;
      }
      try {
        for (final entry in state.entries) {
          final rhs = v.call(
            'Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;',
            [a[1], entry.key],
            kind: 'interface',
          );
          if (!_equal(v, entry.value, rhs)) return 0;
          if (v.isNull(rhs) &&
              v.call('Ljava/util/Map;->containsKey(Ljava/lang/Object;)Z', [
                    a[1],
                    entry.key,
                  ], kind: 'interface') !=
                  1) {
            return 0;
          }
        }
        return 1;
      } on DalvikThrown catch (e) {
        if (e.object.className == 'Ljava/lang/NullPointerException;' ||
            e.object.className == 'Ljava/lang/ClassCastException;') {
          return 0;
        }
        rethrow;
      }
    });
    bind(owner, 'hashCode()I', (v, a) {
      var hash = 0;
      final state = v.object(a[0]).nativeValue as _MapState;
      for (final entry in state.entries) {
        hash = (hash + (_hash(v, entry.key) ^ _hash(v, entry.value))).toSigned(
          32,
        );
      }
      return hash;
    });
  }
  bind(
    'Collections',
    'singletonList(Ljava/lang/Object;)Ljava/util/List;',
    (v, a) => DalvikObject(
      _list,
      nativeValue: _ListState([_nullable(v, a[0])], true, true),
    ),
  );
  bind(
    'Collections',
    'enumeration(Ljava/util/Collection;)Ljava/util/Enumeration;',
    (v, a) => DalvikObject(
      _enumeration,
      nativeValue: _EnumerationDelegate(
        v.call('$_collection->iterator()Ljava/util/Iterator;', [
          a[0],
        ], kind: 'interface'),
      ),
    ),
  );
  bind('Collections', 'list(Ljava/util/Enumeration;)Ljava/util/ArrayList;', (
    v,
    a,
  ) {
    final values = <Object?>[];
    while (v.call('$_enumeration->hasMoreElements()Z', [
          a[0],
        ], kind: 'interface') ==
        1) {
      values.add(
        v.call('$_enumeration->nextElement()Ljava/lang/Object;', [
          a[0],
        ], kind: 'interface'),
      );
    }
    return DalvikObject(
      'Ljava/util/ArrayList;',
      nativeValue: _ListState(values),
    );
  });
  bind(
    'Arrays',
    'asList([Ljava/lang/Object;)Ljava/util/List;',
    (v, a) => DalvikObject(
      _list,
      nativeValue: _ListState(
        v.asArray(a[0]).values,
        true,
        false,
        v.asArray(a[0]),
      ),
    ),
  );

  int now(DalvikRuntime v) {
    final clock = v.wallClockMillis;
    if (clock == null) throw MissingDalvikBridge('Date wall clock');
    return clock();
  }

  bind('Date', '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = now(v);
    return null;
  });
  bind('Date', '<init>(J)V', (v, a) {
    v.object(a[0]).nativeValue = JBits.wide(a, 1);
    return null;
  });
  bind('Date', 'getTime()J', (v, a) => v.object(a[0]).nativeValue as int);
  bind('Date', 'setTime(J)V', (v, a) {
    v.object(a[0]).nativeValue = JBits.wide(a, 1);
    return null;
  });
  JavaCalendarPlatform platform() =>
      calendarPlatform ??
      (throw MissingDalvikBridge('host Calendar and TimeZone rules'));
  bind(
    'Calendar',
    'getInstance()Ljava/util/Calendar;',
    (v, a) => DalvikObject(
      'Ljava/util/GregorianCalendar;',
      nativeValue: platform().createCalendar(now(v)),
    ),
  );
  bind('GregorianCalendar', '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = platform().createCalendar(now(v));
    return null;
  });
  bind(
    'Calendar',
    'get(I)I',
    (v, a) => platform().getField(v.object(a[0]).nativeValue!, a[1] as int),
  );
  bind('Calendar', 'set(II)V', (v, a) {
    platform().setField(v.object(a[0]).nativeValue!, a[1] as int, a[2] as int);
    return null;
  });
  bind('Calendar', 'add(II)V', (v, a) {
    final value = platform();
    if (value is! JavaCalendarArithmetic) {
      throw MissingDalvikBridge('Calendar.add with timezone rules');
    }
    (value as JavaCalendarArithmetic).addField(
      v.object(a[0]).nativeValue!,
      a[1] as int,
      a[2] as int,
    );
    return null;
  });
  bind(
    'Calendar',
    'getTimeInMillis()J',
    (v, a) => platform().getMillis(v.object(a[0]).nativeValue!),
  );
  bind('Calendar', 'setTimeInMillis(J)V', (v, a) {
    platform().setMillis(v.object(a[0]).nativeValue!, JBits.wide(a, 1));
    return null;
  });
  bind(
    'Calendar',
    'getTime()Ljava/util/Date;',
    (v, a) => DalvikObject(
      'Ljava/util/Date;',
      nativeValue: platform().getMillis(v.object(a[0]).nativeValue!),
    ),
  );
  bind('Calendar', 'setTime(Ljava/util/Date;)V', (v, a) {
    platform().setMillis(
      v.object(a[0]).nativeValue!,
      v.object(a[1]).nativeValue as int,
    );
    return null;
  });
  bind(
    'TimeZone',
    'getDefault()Ljava/util/TimeZone;',
    (v, a) => DalvikObject(
      'Ljava/util/TimeZone;',
      nativeValue: platform().defaultTimeZone(),
    ),
  );
  bind(
    'TimeZone',
    'getRawOffset()I',
    (v, a) => platform().rawOffset(v.object(a[0]).nativeValue!),
  );
}
