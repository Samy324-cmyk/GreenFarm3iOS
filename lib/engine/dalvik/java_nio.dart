import 'dart:typed_data';

import 'runtime.dart';

/// Shared byte-addressed backing storage. Wrapped primitive arrays remain live.
final class _Storage {
  _Storage(this.array);
  final DalvikArray array;
  int get width => _size(array.component);
  int read(int byte) {
    final shift =
        (Endian.host == Endian.little
            ? byte % width
            : width - 1 - byte % width) *
        8;
    return ((array.values[byte ~/ width] as int) >>> shift) & 255;
  }

  void write(int byte, int value) {
    final i = byte ~/ width,
        shift =
            (Endian.host == Endian.little
                ? byte % width
                : width - 1 - byte % width) *
            8;
    final raw = array.values[i] as int;
    array.values[i] = ((raw & ~(255 << shift)) | ((value & 255) << shift))
        .toSigned(width * 8);
  }
}

int _size(String type) => switch (type) {
  'B' => 1,
  'S' => 2,
  'I' || 'F' => 4,
  _ => throw ArgumentError.value(type, 'buffer type'),
};

/// A Java NIO buffer, sharing data with all views and its wrapped Dalvik array.
/// Float elements are represented by their original raw 32-bit IEEE words.
final class JavaNioBuffer {
  JavaNioBuffer._(
    this._storage,
    this.type,
    this.byteOffset,
    this.capacity, {
    required this.order,
    this.direct = false,
    this.readOnly = false,
    int? position,
    int? limit,
    this.mark = -1,
  }) : position = position ?? 0,
       limit = limit ?? capacity;
  final _Storage _storage;
  final String type;
  final int byteOffset, capacity;
  final bool direct, readOnly;
  Endian order;
  int position, limit, mark;
  int get elementSize => _size(type);
  int get remaining => limit - position;
  bool get hasArray => !direct && !readOnly && _storage.array.component == type;
  int get arrayOffset => byteOffset ~/ elementSize;

  /// Absolute element access within the current Java limit; position unchanged.
  int readRaw(int index) {
    if (index < 0 || index >= limit) {
      throw RangeError.index(index, this, 'index', null, limit);
    }
    return _readAt(index * elementSize, elementSize);
  }

  void writeRaw(int index, int value) {
    if (readOnly) throw StateError('Read-only Java NIO buffer');
    if (index < 0 || index >= limit) {
      throw RangeError.index(index, this, 'index', null, limit);
    }
    _writeAt(index * elementSize, elementSize, value);
  }

  int _readAt(int byte, int width) {
    var value = 0;
    for (var i = 0; i < width; i++) {
      value |=
          _storage.read(byteOffset + byte + i) <<
          ((order == Endian.little ? i : width - 1 - i) * 8);
    }
    return value.toSigned(width * 8);
  }

  void _writeAt(int byte, int width, int value) {
    for (var i = 0; i < width; i++) {
      _storage.write(
        byteOffset + byte + i,
        value >>> ((order == Endian.little ? i : width - 1 - i) * 8),
      );
    }
  }

  /// Upload snapshot in buffer byte order. Positions are not changed. Snapshot
  /// semantics work consistently for both byte storage and wrapped int arrays.
  Uint8List copyBytes({bool remaining = true}) {
    final first = remaining ? position : 0, last = remaining ? limit : capacity;
    return Uint8List.fromList(
      List.generate(
        (last - first) * elementSize,
        (i) => _storage.read(byteOffset + first * elementSize + i),
      ),
    );
  }
}

JavaNioBuffer javaNioBuffer(DalvikRuntime vm, Object? value) {
  final native = vm.object(value).nativeValue;
  if (native is! JavaNioBuffer) {
    throw MissingDalvikBridge(
      'Expected a Java NIO buffer, got ${vm.object(value).className}',
    );
  }
  return native;
}

void registerJavaNio(DalvikRuntime vm) {
  const base = 'Ljava/nio/Buffer;',
      byte = 'Ljava/nio/ByteBuffer;',
      orderClass = 'Ljava/nio/ByteOrder;';
  const names = {'B': 'Byte', 'S': 'Short', 'I': 'Int', 'F': 'Float'};
  int integer(Object? v) => (v as int).toSigned(32);
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  Never error(String name) =>
      vm.throwJava('Ljava/${name.contains('/') ? name : 'nio/$name'};');
  void check(int at, int length, int total) {
    if (at < 0 || length < 0 || at + length > total) {
      error('lang/IndexOutOfBoundsException');
    }
  }

  void writable(JavaNioBuffer b) {
    if (b.readOnly) error('ReadOnlyBufferException');
  }

  JavaNioBuffer buf(Object? value) => javaNioBuffer(vm, value);
  DalvikObject wrap(JavaNioBuffer b) =>
      DalvikObject('Ljava/nio/${names[b.type]}Buffer;', nativeValue: b);
  vm.registerExternalClass(base);
  vm.registerExternalClass(orderClass);
  for (final name in names.values) {
    vm.registerExternalClass(
      'Ljava/nio/${name}Buffer;',
      superclass: base,
      interfaces: ['Ljava/lang/Comparable;'],
    );
  }
  for (final name in ['BufferUnderflowException', 'BufferOverflowException']) {
    vm.registerExternalClass(
      'Ljava/nio/$name;',
      superclass: 'Ljava/lang/RuntimeException;',
    );
  }
  vm.registerExternalClass(
    'Ljava/nio/InvalidMarkException;',
    superclass: 'Ljava/lang/IllegalStateException;',
  );
  vm.registerExternalClass(
    'Ljava/nio/ReadOnlyBufferException;',
    superclass: 'Ljava/lang/UnsupportedOperationException;',
  );
  final big = DalvikObject(orderClass, nativeValue: Endian.big),
      little = DalvikObject(orderClass, nativeValue: Endian.little);
  vm.classes[orderClass]!.staticFields['$orderClass->BIG_ENDIAN:$orderClass'] =
      big;
  vm
          .classes[orderClass]!
          .staticFields['$orderClass->LITTLE_ENDIAN:$orderClass'] =
      little;
  native(
    orderClass,
    'nativeOrder()$orderClass',
    (_, a) => Endian.host == Endian.little ? little : big,
  );
  native(
    orderClass,
    'toString()Ljava/lang/String;',
    (_, a) => vm.newString(
      vm.object(a[0]).nativeValue == Endian.little
          ? 'LITTLE_ENDIAN'
          : 'BIG_ENDIAN',
    ),
  );
  for (final field in ['position', 'limit', 'capacity']) {
    native(base, '$field()I', (_, a) {
      final b = buf(a[0]);
      return switch (field) {
        'position' => b.position,
        'limit' => b.limit,
        _ => b.capacity,
      };
    });
  }
  native(base, 'remaining()I', (_, a) => buf(a[0]).remaining);
  native(base, 'hasRemaining()Z', (_, a) => buf(a[0]).remaining > 0 ? 1 : 0);
  for (final property in ['isReadOnly', 'isDirect', 'hasArray']) {
    native(base, '$property()Z', (_, a) {
      final b = buf(a[0]);
      return (switch (property) {
            'isReadOnly' => b.readOnly,
            'isDirect' => b.direct,
            _ => b.hasArray,
          })
          ? 1
          : 0;
    });
  }
  native(base, 'arrayOffset()I', (_, a) {
    final b = buf(a[0]);
    if (b.readOnly) error('ReadOnlyBufferException');
    if (!b.hasArray) error('lang/UnsupportedOperationException');
    return b.arrayOffset;
  });
  Object? array(DalvikRuntime _, List<Object?> a) {
    final b = buf(a[0]);
    if (b.readOnly) error('ReadOnlyBufferException');
    if (!b.hasArray) error('lang/UnsupportedOperationException');
    return b._storage.array;
  }

  native(base, 'array()Ljava/lang/Object;', array);
  for (final owner in [
    base,
    ...names.values.map((n) => 'Ljava/nio/${n}Buffer;'),
  ]) {
    // Java 8 declares state mutators on Buffer and returns Buffer; newer JVMs
    // also expose covariant typed returns. The APK calls the Buffer signatures.
    final returns = owner == base ? [base] : [base, owner];
    for (final ret in returns) {
      native(owner, 'position(I)$ret', (_, a) {
        final b = buf(a[0]), p = integer(a[1]);
        if (p < 0 || p > b.limit) error('lang/IllegalArgumentException');
        b.position = p;
        if (b.mark > p) b.mark = -1;
        return a[0];
      });
      native(owner, 'limit(I)$ret', (_, a) {
        final b = buf(a[0]), n = integer(a[1]);
        if (n < 0 || n > b.capacity) error('lang/IllegalArgumentException');
        b.limit = n;
        if (b.position > n) b.position = n;
        if (b.mark > n) b.mark = -1;
        return a[0];
      });
      for (final operation in ['mark', 'reset', 'clear', 'flip', 'rewind']) {
        native(owner, '$operation()$ret', (_, a) {
          final b = buf(a[0]);
          switch (operation) {
            case 'mark':
              b.mark = b.position;
            case 'reset':
              if (b.mark < 0) error('InvalidMarkException');
              b.position = b.mark;
            case 'clear':
              b.position = 0;
              b.limit = b.capacity;
              b.mark = -1;
            case 'flip':
              b.limit = b.position;
              b.position = 0;
              b.mark = -1;
            case 'rewind':
              b.position = 0;
              b.mark = -1;
          }
          return a[0];
        });
      }
    }
  }
  for (final entry in names.entries) {
    final type = entry.key, owner = 'Ljava/nio/${entry.value}Buffer;';
    native(owner, 'allocate(I)$owner', (_, a) {
      final size = integer(a[0]);
      if (size < 0) error('lang/IllegalArgumentException');
      return wrap(
        JavaNioBuffer._(
          _Storage(vm.array('[$type', size)),
          type,
          0,
          size,
          order: type == 'B' ? Endian.big : Endian.host,
        ),
      );
    });
    for (final ranged in [false, true]) {
      native(owner, 'wrap([$type${ranged ? 'II' : ''})$owner', (_, a) {
        final values = vm.asArray(a[0]);
        final offset = ranged ? integer(a[1]) : 0,
            count = ranged ? integer(a[2]) : values.values.length;
        check(offset, count, values.values.length);
        return wrap(
          JavaNioBuffer._(
            _Storage(values),
            type,
            0,
            values.values.length,
            order: type == 'B' ? Endian.big : Endian.host,
            position: offset,
            limit: offset + count,
          ),
        );
      });
    }
    native(owner, 'array()[$type', array);
    native(
      owner,
      'order()$orderClass',
      (_, a) => buf(a[0]).order == Endian.little ? little : big,
    );
    for (final absolute in [false, true]) {
      native(owner, 'get(${absolute ? 'I' : ''})$type', (_, a) {
        final b = buf(a[0]), at = absolute ? integer(a[1]) : buf(a[0]).position;
        if (absolute) {
          check(at, 1, b.limit);
        } else if (b.remaining < 1) {
          error('BufferUnderflowException');
        }
        final value = b.readRaw(at);
        if (!absolute) b.position++;
        return value;
      });
      native(owner, 'put(${absolute ? 'I' : ''}$type)$owner', (_, a) {
        final b = buf(a[0]);
        writable(b);
        final at = absolute ? integer(a[1]) : b.position;
        if (absolute) {
          check(at, 1, b.limit);
        } else if (b.remaining < 1) {
          error('BufferOverflowException');
        }
        b.writeRaw(at, integer(a[absolute ? 2 : 1]));
        if (!absolute) b.position++;
        return a[0];
      });
    }
    for (final put in [false, true]) {
      for (final ranged in [false, true]) {
        native(
          owner,
          '${put ? 'put' : 'get'}([$type${ranged ? 'II' : ''})$owner',
          (_, a) {
            final b = buf(a[0]);
            if (put) writable(b);
            final values = vm.asArray(a[1]),
                offset = ranged ? integer(a[2]) : 0,
                count = ranged ? integer(a[3]) : values.values.length;
            check(offset, count, values.values.length);
            if (count > b.remaining) {
              error(
                put ? 'BufferOverflowException' : 'BufferUnderflowException',
              );
            }
            final snapshot = List<int>.generate(
              count,
              (i) => put
                  ? values.values[offset + i] as int
                  : b.readRaw(b.position + i),
            );
            for (var i = 0; i < count; i++) {
              if (put) {
                b.writeRaw(b.position + i, snapshot[i]);
              } else {
                vm.arrayPut(values, offset + i, snapshot[i]);
              }
            }
            b.position += count;
            return a[0];
          },
        );
      }
    }
    native(owner, 'put($owner)$owner', (_, a) {
      if (identical(a[0], a[1])) error('lang/IllegalArgumentException');
      final to = buf(a[0]), from = buf(a[1]);
      writable(to);
      final count = from.remaining;
      if (count > to.remaining) error('BufferOverflowException');
      final values = List.generate(
        count,
        (i) => from.readRaw(from.position + i),
      );
      for (var i = 0; i < count; i++) {
        to.writeRaw(to.position + i, values[i]);
      }
      to.position += count;
      from.position += count;
      return a[0];
    });
    for (final operation in ['slice', 'duplicate', 'asReadOnlyBuffer']) {
      native(owner, '$operation()$owner', (_, a) {
        final b = buf(a[0]), slice = operation == 'slice';
        return wrap(
          JavaNioBuffer._(
            b._storage,
            type,
            b.byteOffset + (slice ? b.position * b.elementSize : 0),
            slice ? b.remaining : b.capacity,
            order: type == 'B' ? Endian.big : b.order,
            direct: b.direct,
            readOnly: b.readOnly || operation == 'asReadOnlyBuffer',
            position: slice ? 0 : b.position,
            limit: slice ? b.remaining : b.limit,
            mark: slice ? -1 : b.mark,
          ),
        );
      });
    }
    native(owner, 'compact()$owner', (_, a) {
      final b = buf(a[0]);
      writable(b);
      final count = b.remaining;
      final values = List.generate(count, (i) => b.readRaw(b.position + i));
      for (var i = 0; i < count; i++) {
        b._writeAt(i * b.elementSize, b.elementSize, values[i]);
      }
      b.position = count;
      b.limit = b.capacity;
      b.mark = -1;
      return a[0];
    });
  }
  native(byte, 'allocateDirect(I)$byte', (_, a) {
    final size = integer(a[0]);
    if (size < 0) error('lang/IllegalArgumentException');
    return wrap(
      JavaNioBuffer._(
        _Storage(vm.array('[B', size)),
        'B',
        0,
        size,
        order: Endian.big,
        direct: true,
      ),
    );
  });
  native(byte, 'order($orderClass)$byte', (_, a) {
    final b = buf(a[0]);
    b.order = vm.isNull(a[1]) || vm.object(a[1]).nativeValue == Endian.little
        ? Endian.little
        : Endian.big;
    return a[0];
  });
  for (final type in ['S', 'I', 'F']) {
    final typed = 'Ljava/nio/${names[type]}Buffer;', width = _size(type);
    native(byte, 'as${names[type]}Buffer()$typed', (_, a) {
      final b = buf(a[0]);
      return wrap(
        JavaNioBuffer._(
          b._storage,
          type,
          b.byteOffset + b.position,
          b.remaining ~/ width,
          order: b.order,
          direct: b.direct,
          readOnly: b.readOnly,
        ),
      );
    });
    for (final absolute in [false, true]) {
      native(byte, 'get${names[type]}(${absolute ? 'I' : ''})$type', (_, a) {
        final b = buf(a[0]), at = absolute ? integer(a[1]) : buf(a[0]).position;
        if (absolute) {
          check(at, width, b.limit);
        } else if (b.remaining < width) {
          error('BufferUnderflowException');
        }
        final result = b._readAt(at, width);
        if (!absolute) b.position += width;
        return result;
      });
      native(byte, 'put${names[type]}(${absolute ? 'I' : ''}$type)$byte', (
        _,
        a,
      ) {
        final b = buf(a[0]);
        writable(b);
        final at = absolute ? integer(a[1]) : b.position;
        if (absolute) {
          check(at, width, b.limit);
        } else if (b.remaining < width) {
          error('BufferOverflowException');
        }
        b._writeAt(at, width, integer(a[absolute ? 2 : 1]));
        if (!absolute) b.position += width;
        return a[0];
      });
    }
  }
}
