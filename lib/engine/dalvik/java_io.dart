import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'numbers.dart';
import 'runtime.dart';

const _input = 'Ljava/io/InputStream;';
const _output = 'Ljava/io/OutputStream;';
const _byteInput = 'Ljava/io/ByteArrayInputStream;';
const _byteOutput = 'Ljava/io/ByteArrayOutputStream;';
const _dataInput = 'Ljava/io/DataInputStream;';
const _dataOutput = 'Ljava/io/DataOutputStream;';
const _bufferedInput = 'Ljava/io/BufferedInputStream;';
const _bufferedOutput = 'Ljava/io/BufferedOutputStream;';
const _gzipInput = 'Ljava/util/zip/GZIPInputStream;';

int _int(Object? n) => JBits.int32(n);
Object? _call(
  DalvikRuntime vm,
  DalvikObject receiver,
  String owner,
  String member, [
  List<Object?> arguments = const [],
]) => vm.call('$owner->$member', [receiver, ...arguments], kind: 'virtual');
int _read(DalvikRuntime vm, DalvikObject stream) =>
    _call(vm, stream, _input, 'read()I') as int;
int _readBytes(
  DalvikRuntime vm,
  DalvikObject stream,
  DalvikArray bytes,
  int offset,
  int length,
) => _call(vm, stream, _input, 'read([BII)I', [bytes, offset, length]) as int;
void _write(DalvikRuntime vm, DalvikObject stream, int value) =>
    _call(vm, stream, _output, 'write(I)V', [value]);
void _writeBytes(
  DalvikRuntime vm,
  DalvikObject stream,
  DalvikArray bytes,
  int offset,
  int length,
) => _call(vm, stream, _output, 'write([BII)V', [bytes, offset, length]);

DalvikArray _bytes(DalvikRuntime vm, Object? value) {
  final array = vm.asArray(value);
  if (array.className != '[B') throw StateError('Expected Java byte[]');
  return array;
}

void _bounds(DalvikRuntime vm, DalvikArray array, int offset, int length) {
  if (offset < 0 || length < 0 || offset > array.values.length - length) {
    vm.throwJava('Ljava/lang/IndexOutOfBoundsException;');
  }
}

DalvikArray _copyBytes(DalvikRuntime vm, Iterable<int> values) {
  final list = values.toList(growable: false);
  final array = vm.array('[B', list.length);
  for (var n = 0; n < list.length; n++) {
    array.values[n] = list[n].toSigned(8);
  }
  return array;
}

/// Resource/platform bridges use this to expose real bytes through Java I/O.
DalvikObject javaByteArrayInputStream(DalvikRuntime vm, List<int> bytes) {
  final object = vm.allocate(_byteInput);
  final array = _copyBytes(vm, bytes);
  object.nativeValue = _ByteInput(array, 0, array.values.length);
  return object;
}

class _ByteInput {
  _ByteInput(this.bytes, this.position, this.end) : mark = position;
  final DalvikArray bytes;
  int position, mark;
  final int end;
}

class _ByteOutput {
  final List<int> bytes = [];
}

class _FilterInput {
  _FilterInput(this.stream);
  final DalvikObject stream;
}

class _FilterOutput {
  _FilterOutput(this.stream);
  final DalvikObject stream;
  int written = 0;
  void count(int length) => written = math.min(0x7fffffff, written + length);
}

class _BufferedInput extends _FilterInput {
  _BufferedInput(super.stream, int size) : buffer = DalvikArray('[B', size);
  DalvikArray buffer;
  int position = 0, end = 0, mark = -1, markLimit = 0;
  bool closed = false;
  void ensureOpen(DalvikRuntime vm) {
    if (closed) vm.throwJava('Ljava/io/IOException;', 'Stream closed');
  }

  void fill(DalvikRuntime vm) {
    if (mark < 0) {
      position = 0;
    } else if (position >= buffer.values.length) {
      if (mark > 0) {
        final length = position - mark;
        buffer.values.setRange(0, length, buffer.values, mark);
        position = length;
        mark = 0;
      } else if (buffer.values.length >= markLimit) {
        mark = -1;
        position = 0;
      } else {
        final replacement = DalvikArray(
          '[B',
          math.min(position * 2, markLimit),
        );
        replacement.values.setRange(0, position, buffer.values);
        buffer = replacement;
      }
    }
    end = position;
    final n = _readBytes(
      vm,
      stream,
      buffer,
      position,
      buffer.values.length - position,
    );
    if (n > 0) end = position + n;
  }

  int readOne(DalvikRuntime vm) {
    ensureOpen(vm);
    if (position >= end) fill(vm);
    return position >= end ? -1 : _int(buffer.values[position++]) & 255;
  }

  int readPart(DalvikRuntime vm, DalvikArray target, int offset, int length) {
    if (position >= end) {
      if (length >= buffer.values.length && mark < 0) {
        return _readBytes(vm, stream, target, offset, length);
      }
      fill(vm);
      if (position >= end) return -1;
    }
    final count = math.min(length, end - position);
    target.values.setRange(offset, offset + count, buffer.values, position);
    position += count;
    return count;
  }

  int readMany(DalvikRuntime vm, DalvikArray target, int offset, int length) {
    ensureOpen(vm);
    _bounds(vm, target, offset, length);
    if (length == 0) return 0;
    var total = 0;
    while (true) {
      final count = readPart(vm, target, offset + total, length - total);
      if (count <= 0) return total == 0 ? count : total;
      total += count;
      if (total >= length ||
          (_call(vm, stream, _input, 'available()I') as int) <= 0) {
        return total;
      }
    }
  }
}

class _BufferedOutput extends _FilterOutput {
  _BufferedOutput(super.stream, int size) : buffer = DalvikArray('[B', size);
  final DalvikArray buffer;
  int length = 0;
  void flushBuffer(DalvikRuntime vm) {
    if (length == 0) return;
    _writeBytes(vm, stream, buffer, 0, length);
    length = 0;
  }
}

class _Crc32 {
  static final table = List.generate(256, (value) {
    for (var n = 0; n < 8; n++) {
      value = value & 1 != 0 ? (value >> 1) ^ 0xedb88320 : value >> 1;
    }
    return value;
  });
  int state = 0xffffffff;
  int get value => (state ^ 0xffffffff) & 0xffffffff;
  void update(int byte) => state = table[(state ^ byte) & 255] ^ (state >> 8);
}

class _ChunkOutput implements Sink<List<int>> {
  final List<int> pending = [];
  @override
  void add(List<int> bytes) => pending.addAll(bytes);
  @override
  void close() {}
}

class _CompressedEof implements Exception {}

class _DeflateBits {
  _DeflateBits(this.bytes);
  final List<int> bytes;
  int bit = 0;
  int read(int count) {
    if (bit + count > bytes.length * 8) throw _CompressedEof();
    var value = 0;
    for (var n = 0; n < count; n++, bit++) {
      value |= ((bytes[bit >> 3] >> (bit & 7)) & 1) << n;
    }
    return value;
  }

  void skip(int count) {
    if (bit + count > bytes.length * 8) throw _CompressedEof();
    bit += count;
  }

  void align() => bit = (bit + 7) & ~7;
}

class _DeflateHuffman {
  _DeflateHuffman(List<int> lengths) {
    final counts = List<int>.filled(16, 0);
    for (final length in lengths) {
      if (length < 0 || length > 15) {
        throw const FormatException('Invalid Huffman length');
      }
      if (length != 0) counts[length]++;
    }
    final next = List<int>.filled(16, 0);
    var code = 0;
    for (var length = 1; length <= 15; length++) {
      code = (code + counts[length - 1]) << 1;
      next[length] = code;
    }
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      final length = lengths[symbol];
      if (length == 0) continue;
      final code = next[length]++;
      var reversed = 0;
      for (var n = 0; n < length; n++) {
        reversed = (reversed << 1) | ((code >> n) & 1);
      }
      tables[length][reversed] = symbol;
    }
  }
  final tables = List.generate(16, (_) => <int, int>{});
  int symbol(_DeflateBits bits) {
    var code = 0;
    for (var length = 1; length <= 15; length++) {
      code |= bits.read(1) << (length - 1);
      final symbol = tables[length][code];
      if (symbol != null) return symbol;
    }
    throw const FormatException('Invalid Huffman code');
  }
}

// Dart's ZLibDecoder accepts a missing gzip trailer at input EOF. Locate each
// RFC1951 end-of-block and require its RFC1952 eight-byte trailer explicitly.
// zlib independently validates decompression, CRC32 and uncompressed size.
/// Strict raw-DEFLATE bridge for ZIP entries. The synthetic gzip envelope lets
/// zlib check the central-directory CRC and size; the existing bit validator
/// rejects incomplete final blocks that a plain raw decoder may accept.
List<int> javaInflateRaw(
  List<int> compressed, {
  required int crc32,
  required int size,
}) {
  final wrapped = Uint8List(compressed.length + 18);
  wrapped.setRange(0, 10, [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255]);
  wrapped.setRange(10, 10 + compressed.length, compressed);
  final data = ByteData.sublistView(wrapped);
  data.setUint32(wrapped.length - 8, crc32, Endian.little);
  data.setUint32(wrapped.length - 4, size, Endian.little);
  try {
    if (_validateGzipBoundaries(wrapped) != wrapped.length) {
      throw const FormatException('Trailing bytes after raw DEFLATE stream');
    }
  } on _CompressedEof {
    throw const FormatException('Truncated raw DEFLATE stream');
  }
  return ZLibDecoder(gzip: true).convert(wrapped);
}

int _validateGzipBoundaries(List<int> compressed) {
  final bits = _DeflateBits(compressed);
  void header() {
    if (bits.read(16) != 0x8b1f || bits.read(8) != 8) {
      throw const FormatException('Invalid gzip header');
    }
    final flags = bits.read(8);
    bits.skip(48);
    if (flags & 4 != 0) bits.skip(bits.read(16) * 8);
    if (flags & 8 != 0) {
      while (bits.read(8) != 0) {}
    }
    if (flags & 16 != 0) {
      while (bits.read(8) != 0) {}
    }
    if (flags & 2 != 0) bits.skip(16);
  }

  header();
  while (true) {
    var last = false;
    while (!last) {
      last = bits.read(1) != 0;
      final type = bits.read(2);
      if (type == 0) {
        bits.align();
        final length = bits.read(16), inverse = bits.read(16);
        if (length ^ inverse != 65535) {
          throw const FormatException('Invalid stored block length');
        }
        bits.skip(length * 8);
        continue;
      }
      if (type == 3) throw const FormatException('Reserved deflate block type');
      late _DeflateHuffman literals, distances;
      if (type == 1) {
        literals = _DeflateHuffman(
          List.generate(
            288,
            (n) => n < 144
                ? 8
                : n < 256
                ? 9
                : n < 280
                ? 7
                : 8,
          ),
        );
        distances = _DeflateHuffman(List.filled(32, 5));
      } else {
        final literalCount = bits.read(5) + 257;
        final distanceCount = bits.read(5) + 1;
        final codeCount = bits.read(4) + 4;
        const order = [
          16,
          17,
          18,
          0,
          8,
          7,
          9,
          6,
          10,
          5,
          11,
          4,
          12,
          3,
          13,
          2,
          14,
          1,
          15,
        ];
        final codeLengths = List<int>.filled(19, 0);
        for (var n = 0; n < codeCount; n++) {
          codeLengths[order[n]] = bits.read(3);
        }
        final codes = _DeflateHuffman(codeLengths), lengths = <int>[];
        while (lengths.length < literalCount + distanceCount) {
          final code = codes.symbol(bits);
          if (code < 16) {
            lengths.add(code);
            continue;
          }
          if (code == 16 && lengths.isEmpty) {
            throw const FormatException('Huffman repeat without predecessor');
          }
          final count = code == 16
              ? bits.read(2) + 3
              : code == 17
              ? bits.read(3) + 3
              : bits.read(7) + 11;
          final value = code == 16 ? lengths.last : 0;
          lengths.addAll(List.filled(count, value));
          if (lengths.length > literalCount + distanceCount) {
            throw const FormatException('Huffman repeat overflow');
          }
        }
        literals = _DeflateHuffman(lengths.sublist(0, literalCount));
        distances = _DeflateHuffman(lengths.sublist(literalCount));
      }
      while (true) {
        final code = literals.symbol(bits);
        if (code < 256) continue;
        if (code == 256) break;
        if (code > 285) throw const FormatException('Reserved length code');
        if (code >= 265 && code != 285) bits.skip((code - 261) ~/ 4);
        final distance = distances.symbol(bits);
        if (distance >= 30) {
          throw const FormatException('Reserved distance code');
        }
        if (distance >= 4) bits.skip((distance ~/ 2) - 1);
      }
    }
    bits.align();
    bits.skip(64);
    final validLength = bits.bit ~/ 8;
    if (bits.bit >= compressed.length * 8) return validLength;
    // Java GZIPInputStream permits trailing non-member data after a valid trailer.
    try {
      header();
    } on _CompressedEof {
      return validLength;
    } on FormatException {
      return validLength;
    }
  }
}

class _GzipInput extends _FilterInput {
  _GzipInput(super.stream, this.bufferSize);
  final int bufferSize;
  final output = _ChunkOutput();
  final List<int> compressed = [];
  late ByteConversionSink decoder;
  DalvikThrown? error;
  bool ended = false, closed = false;
  int position = 0, returned = 0;

  void initialize(DalvikRuntime vm) {
    final header = <int>[];
    final crc = _Crc32();
    int next() {
      final byte = _read(vm, stream);
      if (byte < 0) vm.throwJava('Ljava/io/EOFException;');
      header.add(byte);
      crc.update(byte);
      return byte;
    }

    final magic = next() | (next() << 8);
    if (magic != 0x8b1f) {
      vm.throwJava('Ljava/util/zip/ZipException;', 'Not in GZIP format');
    }
    if (next() != 8) {
      vm.throwJava(
        'Ljava/util/zip/ZipException;',
        'Unsupported compression method',
      );
    }
    final flags = next();
    for (var n = 0; n < 6; n++) {
      next();
    }
    if (flags & 4 != 0) {
      final length = next() | (next() << 8);
      for (var n = 0; n < length; n++) {
        next();
      }
    }
    if (flags & 8 != 0) {
      while (next() != 0) {}
    }
    if (flags & 16 != 0) {
      while (next() != 0) {}
    }
    if (flags & 2 != 0) {
      final expected = crc.value & 65535;
      final actual = next() | (next() << 8);
      if (actual != expected) {
        vm.throwJava('Ljava/util/zip/ZipException;', 'Corrupt GZIP header');
      }
    }
    decoder = ZLibDecoder(gzip: true).startChunkedConversion(output);
    compressed.addAll(header);
    try {
      decoder.add(header);
    } catch (exception) {
      vm.throwJava('Ljava/util/zip/ZipException;', '$exception');
    }
  }

  void ensureOpen(DalvikRuntime vm) {
    if (closed) vm.throwJava('Ljava/io/IOException;', 'Stream closed');
  }

  int readMany(DalvikRuntime vm, DalvikArray target, int offset, int length) {
    ensureOpen(vm);
    if (ended && position >= output.pending.length && error == null) return -1;
    _bounds(vm, target, offset, length);
    if (length == 0) return 0;
    while (position >= output.pending.length) {
      if (error != null) throw error!;
      if (ended) return -1;
      output.pending.clear();
      position = 0;
      final buffer = DalvikArray('[B', bufferSize);
      final count = _readBytes(vm, stream, buffer, 0, bufferSize);
      if (count == 0) {
        vm.throwJava(
          'Ljava/io/IOException;',
          'InputStream returned zero bytes for a nonempty read',
        );
      }
      try {
        if (count < 0) {
          ended = true;
          _validateGzipBoundaries(compressed);
          decoder.close();
        } else {
          final chunk = buffer.values
              .take(count)
              .map((n) => _int(n) & 255)
              .toList();
          compressed.addAll(chunk);
          decoder.add(chunk);
        }
      } catch (exception) {
        // The platform zlib chunk converter can reject a concatenated member
        // crossing a chunk boundary although its complete-input converter is
        // valid. Recover using the original compressed bytes and only return
        // bytes not already delivered. The independent parser also identifies
        // trailing non-member bytes, which Java GZIPInputStream ignores.
        try {
          while (!ended) {
            final n = _readBytes(vm, stream, buffer, 0, bufferSize);
            if (n < 0) {
              ended = true;
              break;
            }
            if (n == 0) {
              vm.throwJava(
                'Ljava/io/IOException;',
                'InputStream returned zero bytes',
              );
            }
            compressed.addAll(buffer.values.take(n).map((n) => _int(n) & 255));
          }
          final validLength = _validateGzipBoundaries(compressed);
          final decoded = ZLibDecoder(gzip: true)
              .convert(compressed.sublist(0, validLength));
          output.pending
            ..clear()
            ..addAll(decoded.skip(returned));
          position = 0;
        } on DalvikThrown {
          rethrow;
        } catch (failure) {
          error = DalvikThrown(
            DalvikObject(
              failure is _CompressedEof
                  ? 'Ljava/io/EOFException;'
                  : 'Ljava/util/zip/ZipException;',
              nativeValue: '$failure',
            ),
          );
        }
      }
    }
    final count = math.min(length, output.pending.length - position);
    for (var n = 0; n < count; n++) {
      target.values[offset + n] = output.pending[position + n].toSigned(8);
    }
    position += count;
    returned += count;
    return count;
  }
}

void registerJavaIo(DalvikRuntime vm) {
  for (final name in [
    'Closeable',
    'Flushable',
    'DataInput',
    'DataOutput',
    'Serializable',
  ]) {
    vm.registerExternalClass('Ljava/io/$name;');
  }
  vm.registerExternalClass(_input, interfaces: ['Ljava/io/Closeable;']);
  vm.registerExternalClass(
    _output,
    interfaces: ['Ljava/io/Closeable;', 'Ljava/io/Flushable;'],
  );
  vm.registerExternalClass(_byteInput, superclass: _input);
  vm.registerExternalClass(_byteOutput, superclass: _output);
  vm.registerExternalClass('Ljava/io/FilterInputStream;', superclass: _input);
  vm.registerExternalClass('Ljava/io/FilterOutputStream;', superclass: _output);
  vm.registerExternalClass(
    _dataInput,
    superclass: 'Ljava/io/FilterInputStream;',
    interfaces: ['Ljava/io/DataInput;'],
  );
  vm.registerExternalClass(
    _dataOutput,
    superclass: 'Ljava/io/FilterOutputStream;',
    interfaces: ['Ljava/io/DataOutput;'],
  );
  vm.registerExternalClass(
    _bufferedInput,
    superclass: 'Ljava/io/FilterInputStream;',
  );
  vm.registerExternalClass(
    _bufferedOutput,
    superclass: 'Ljava/io/FilterOutputStream;',
  );
  vm.registerExternalClass(
    'Ljava/util/zip/InflaterInputStream;',
    superclass: 'Ljava/io/FilterInputStream;',
  );
  vm.registerExternalClass(
    _gzipInput,
    superclass: 'Ljava/util/zip/InflaterInputStream;',
  );
  vm.registerExternalClass('Ljava/util/zip/Checksum;');
  vm.registerExternalClass(
    'Ljava/util/zip/CRC32;',
    interfaces: ['Ljava/util/zip/Checksum;'],
  );
  for (final entry in {
    'Ljava/io/IOException;': 'Ljava/lang/Exception;',
    'Ljava/io/EOFException;': 'Ljava/io/IOException;',
    'Ljava/io/UTFDataFormatException;': 'Ljava/io/IOException;',
    'Ljava/io/UnsupportedEncodingException;': 'Ljava/io/IOException;',
    'Ljava/util/zip/ZipException;': 'Ljava/io/IOException;',
  }.entries) {
    vm.registerExternalClass(entry.key, superclass: entry.value);
    vm.registerNative('${entry.key}-><init>()V', (v, a) => null);
    vm.registerNative('${entry.key}-><init>(Ljava/lang/String;)V', (v, a) {
      v.object(a[0]).nativeValue = v.isNull(a[1]) ? null : v.string(a[1]);
      return null;
    });
  }
  void input(String owner, String signature, DalvikBody body) =>
      vm.registerNative('$owner->$signature', body);
  input(_input, '<init>()V', (v, a) => null);
  input(_input, 'read([B)I', (v, a) {
    final b = _bytes(v, a[1]);
    return _readBytes(v, v.object(a[0]), b, 0, b.values.length);
  });
  input(_input, 'read([BII)I', (v, a) {
    final stream = v.object(a[0]), b = _bytes(v, a[1]);
    final offset = _int(a[2]), length = _int(a[3]);
    _bounds(v, b, offset, length);
    if (length == 0) return 0;
    final first = _read(v, stream);
    if (first < 0) return -1;
    b.values[offset] = first.toSigned(8);
    var count = 1;
    try {
      while (count < length) {
        final byte = _read(v, stream);
        if (byte < 0) break;
        b.values[offset + count++] = byte.toSigned(8);
      }
    } on DalvikThrown catch (error) {
      if (!v.instanceOf(error.object, 'Ljava/io/IOException;')) rethrow;
    }
    return count;
  });
  input(_input, 'skip(J)J', (v, a) {
    var remaining = JBits.wide(a, 1);
    if (remaining <= 0) return 0;
    final requested = remaining;
    final scratch = DalvikArray('[B', math.min(remaining, 2048));
    while (remaining > 0) {
      final n = _readBytes(
        v,
        v.object(a[0]),
        scratch,
        0,
        math.min(scratch.values.length, remaining),
      );
      if (n < 0) break;
      remaining -= n;
    }
    return requested - remaining;
  });
  input(_input, 'available()I', (v, a) => 0); // Java InputStream default.
  input(_input, 'close()V', (v, a) => null); // Java InputStream default.
  input(_input, 'mark(I)V', (v, a) => null); // Java InputStream default.
  input(_input, 'markSupported()Z', (v, a) => 0);
  input(
    _input,
    'reset()V',
    (v, a) => v.throwJava('Ljava/io/IOException;', 'mark/reset not supported'),
  );
  input(_byteInput, '<init>([B)V', (v, a) {
    final b = _bytes(v, a[1]);
    v.object(a[0]).nativeValue = _ByteInput(b, 0, b.values.length);
    return null;
  });
  input(_byteInput, '<init>([BII)V', (v, a) {
    final b = _bytes(v, a[1]), offset = _int(a[2]), length = _int(a[3]);
    v.object(a[0]).nativeValue = _ByteInput(
      b,
      offset,
      math.min((offset + length).toSigned(32), b.values.length),
    );
    return null;
  });
  input(_byteInput, 'read()I', (v, a) {
    final s = v.object(a[0]).nativeValue as _ByteInput;
    return s.position < s.end
        ? _int(v.arrayGet(s.bytes, s.position++)) & 255
        : -1;
  });
  input(_byteInput, 'read([BII)I', (v, a) {
    final s = v.object(a[0]).nativeValue as _ByteInput, b = _bytes(v, a[1]);
    final offset = _int(a[2]), length = _int(a[3]);
    _bounds(v, b, offset, length);
    if (s.position >= s.end) return -1;
    final count = math.min(length, s.end - s.position);
    if (count <= 0) return 0;
    if (s.position < 0) {
      v.throwJava('Ljava/lang/ArrayIndexOutOfBoundsException;');
    }
    b.values.setRange(offset, offset + count, s.bytes.values, s.position);
    s.position += count;
    return count;
  });
  input(_byteInput, 'skip(J)J', (v, a) {
    final s = v.object(a[0]).nativeValue as _ByteInput;
    final count = math.max(0, math.min(JBits.wide(a, 1), s.end - s.position));
    s.position += count;
    return count;
  });
  input(_byteInput, 'available()I', (v, a) {
    final s = v.object(a[0]).nativeValue as _ByteInput;
    return s.end - s.position;
  });
  input(_byteInput, 'mark(I)V', (v, a) {
    final s = v.object(a[0]).nativeValue as _ByteInput;
    s.mark = s.position;
    return null;
  });
  input(_byteInput, 'reset()V', (v, a) {
    final s = v.object(a[0]).nativeValue as _ByteInput;
    s.position = s.mark;
    return null;
  });
  input(_byteInput, 'markSupported()Z', (v, a) => 1);
  _registerOutput(vm);
  _registerFilters(vm);
  _registerData(vm);
  _registerCompression(vm);
  _registerResources(vm);
}

void _registerOutput(DalvikRuntime vm) {
  void put(String owner, String signature, DalvikBody body) =>
      vm.registerNative('$owner->$signature', body);
  put(_output, '<init>()V', (v, a) => null);
  put(_output, 'write([B)V', (v, a) {
    final b = _bytes(v, a[1]);
    _writeBytes(v, v.object(a[0]), b, 0, b.values.length);
    return null;
  });
  put(_output, 'write([BII)V', (v, a) {
    final b = _bytes(v, a[1]), offset = _int(a[2]), length = _int(a[3]);
    _bounds(v, b, offset, length);
    for (var n = 0; n < length; n++) {
      _write(v, v.object(a[0]), _int(b.values[offset + n]));
    }
    return null;
  });
  put(_output, 'flush()V', (v, a) => null); // Java OutputStream default.
  put(_output, 'close()V', (v, a) => null); // Java OutputStream default.
  put(_byteOutput, '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = _ByteOutput();
    return null;
  });
  put(_byteOutput, '<init>(I)V', (v, a) {
    if (_int(a[1]) < 0) {
      v.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Negative initial size',
      );
    }
    v.object(a[0]).nativeValue = _ByteOutput();
    return null;
  });
  put(_byteOutput, 'write(I)V', (v, a) {
    (v.object(a[0]).nativeValue as _ByteOutput).bytes.add(_int(a[1]) & 255);
    return null;
  });
  put(_byteOutput, 'write([BII)V', (v, a) {
    final b = _bytes(v, a[1]), offset = _int(a[2]), length = _int(a[3]);
    _bounds(v, b, offset, length);
    (v.object(a[0]).nativeValue as _ByteOutput).bytes.addAll(
      b.values.skip(offset).take(length).map((n) => _int(n) & 255),
    );
    return null;
  });
  put(
    _byteOutput,
    'toByteArray()[B',
    (v, a) => _copyBytes(v, (v.object(a[0]).nativeValue as _ByteOutput).bytes),
  );
  put(
    _byteOutput,
    'size()I',
    (v, a) => (v.object(a[0]).nativeValue as _ByteOutput).bytes.length,
  );
  put(_byteOutput, 'reset()V', (v, a) {
    (v.object(a[0]).nativeValue as _ByteOutput).bytes.clear();
    return null;
  });
  put(_byteOutput, 'toString()Ljava/lang/String;', (v, a) {
    final bytes = _copyBytes(
      v,
      (v.object(a[0]).nativeValue as _ByteOutput).bytes,
    );
    final string = v.allocate('Ljava/lang/String;');
    v.call('Ljava/lang/String;-><init>([B)V', [string, bytes], kind: 'direct');
    return string;
  });
  put(_byteOutput, 'toString(Ljava/lang/String;)Ljava/lang/String;', (v, a) {
    final bytes = _copyBytes(
      v,
      (v.object(a[0]).nativeValue as _ByteOutput).bytes,
    );
    final string = v.allocate('Ljava/lang/String;');
    v.call('Ljava/lang/String;-><init>([BLjava/lang/String;)V', [
      string,
      bytes,
      a[1],
    ], kind: 'direct');
    return string;
  });
  put(_byteOutput, 'writeTo(Ljava/io/OutputStream;)V', (v, a) {
    final bytes = _copyBytes(
      v,
      (v.object(a[0]).nativeValue as _ByteOutput).bytes,
    );
    _writeBytes(v, v.object(a[1]), bytes, 0, bytes.values.length);
    return null;
  });
}

void _registerFilters(DalvikRuntime vm) {
  for (final owner in ['Ljava/io/FilterInputStream;', _dataInput]) {
    vm.registerNative('$owner-><init>(Ljava/io/InputStream;)V', (v, a) {
      v.object(a[0]).nativeValue = _FilterInput(v.object(a[1]));
      return null;
    });
  }
  for (final signature in [
    'read()I',
    'read([BII)I',
    'skip(J)J',
    'available()I',
    'close()V',
    'mark(I)V',
    'reset()V',
    'markSupported()Z',
  ]) {
    vm.registerNative(
      'Ljava/io/FilterInputStream;->$signature',
      (v, a) => _call(
        v,
        (v.object(a[0]).nativeValue as _FilterInput).stream,
        _input,
        signature,
        a.sublist(1),
      ),
    );
  }
  for (final owner in ['Ljava/io/FilterOutputStream;', _dataOutput]) {
    vm.registerNative('$owner-><init>(Ljava/io/OutputStream;)V', (v, a) {
      v.object(a[0]).nativeValue = _FilterOutput(v.object(a[1]));
      return null;
    });
  }
  vm.registerNative('Ljava/io/FilterOutputStream;->write(I)V', (v, a) {
    _write(v, (v.object(a[0]).nativeValue as _FilterOutput).stream, _int(a[1]));
    return null;
  });
  vm.registerNative(
    'Ljava/io/FilterOutputStream;->flush()V',
    (v, a) => _call(
      v,
      (v.object(a[0]).nativeValue as _FilterOutput).stream,
      _output,
      'flush()V',
    ),
  );
  vm.registerNative('Ljava/io/FilterOutputStream;->close()V', (v, a) {
    try {
      _call(v, v.object(a[0]), _output, 'flush()V');
    } finally {
      _call(
        v,
        (v.object(a[0]).nativeValue as _FilterOutput).stream,
        _output,
        'close()V',
      );
    }
    return null;
  });
  for (final withSize in [false, true]) {
    vm.registerNative(
      '$_bufferedInput-><init>(Ljava/io/InputStream;${withSize ? 'I' : ''})V',
      (v, a) {
        final size = withSize ? _int(a[2]) : 8192;
        if (size <= 0) {
          v.throwJava(
            'Ljava/lang/IllegalArgumentException;',
            'Buffer size <= 0',
          );
        }
        v.object(a[0]).nativeValue = _BufferedInput(v.object(a[1]), size);
        return null;
      },
    );
    vm.registerNative(
      '$_bufferedOutput-><init>(Ljava/io/OutputStream;${withSize ? 'I' : ''})V',
      (v, a) {
        final size = withSize ? _int(a[2]) : 8192;
        if (size <= 0) {
          v.throwJava(
            'Ljava/lang/IllegalArgumentException;',
            'Buffer size <= 0',
          );
        }
        v.object(a[0]).nativeValue = _BufferedOutput(v.object(a[1]), size);
        return null;
      },
    );
  }
  vm.registerNative(
    '$_bufferedInput->read()I',
    (v, a) => (v.object(a[0]).nativeValue as _BufferedInput).readOne(v),
  );
  vm.registerNative(
    '$_bufferedInput->read([BII)I',
    (v, a) => (v.object(a[0]).nativeValue as _BufferedInput).readMany(
      v,
      _bytes(v, a[1]),
      _int(a[2]),
      _int(a[3]),
    ),
  );
  vm.registerNative('$_bufferedInput->available()I', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedInput;
    s.ensureOpen(v);
    return math.min(
      0x7fffffff,
      s.end - s.position + (_call(v, s.stream, _input, 'available()I') as int),
    );
  });
  vm.registerNative('$_bufferedInput->mark(I)V', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedInput;
    s.markLimit = _int(a[1]);
    s.mark = s.position;
    return null;
  });
  vm.registerNative('$_bufferedInput->reset()V', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedInput;
    s.ensureOpen(v);
    if (s.mark < 0) {
      v.throwJava('Ljava/io/IOException;', 'Resetting to invalid mark');
    }
    s.position = s.mark;
    return null;
  });
  vm.registerNative('$_bufferedInput->markSupported()Z', (v, a) => 1);
  vm.registerNative('$_bufferedInput->close()V', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedInput;
    if (!s.closed) {
      s.closed = true;
      _call(v, s.stream, _input, 'close()V');
    }
    return null;
  });
  vm.registerNative('$_bufferedInput->skip(J)J', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedInput;
    s.ensureOpen(v);
    final n = JBits.wide(a, 1);
    if (n <= 0) return 0;
    if (s.position >= s.end) {
      if (s.mark < 0) {
        return _call(v, s.stream, _input, 'skip(J)J', a.sublist(1));
      }
      s.fill(v);
      if (s.position >= s.end) return 0;
    }
    final count = math.min(n, s.end - s.position);
    s.position += count;
    return count;
  });
  vm.registerNative('$_bufferedOutput->write(I)V', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedOutput;
    if (s.length >= s.buffer.values.length) s.flushBuffer(v);
    s.buffer.values[s.length++] = _int(a[1]).toSigned(8);
    return null;
  });
  vm.registerNative('$_bufferedOutput->write([BII)V', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedOutput,
        b = _bytes(v, a[1]);
    final offset = _int(a[2]), length = _int(a[3]);
    _bounds(v, b, offset, length);
    if (length >= s.buffer.values.length) {
      s.flushBuffer(v);
      _writeBytes(v, s.stream, b, offset, length);
      return null;
    }
    if (length > s.buffer.values.length - s.length) s.flushBuffer(v);
    s.buffer.values.setRange(s.length, s.length + length, b.values, offset);
    s.length += length;
    return null;
  });
  vm.registerNative('$_bufferedOutput->flush()V', (v, a) {
    final s = v.object(a[0]).nativeValue as _BufferedOutput;
    s.flushBuffer(v);
    return _call(v, s.stream, _output, 'flush()V');
  });
}

void _registerData(DalvikRuntime vm) {
  int unsigned(DalvikRuntime v, DalvikObject s) {
    final n = _read(v, s);
    if (n < 0) v.throwJava('Ljava/io/EOFException;');
    return n;
  }

  int number(DalvikRuntime v, DalvikObject s, int count) {
    var result = 0;
    for (var n = 0; n < count; n++) {
      result = (result << 8) | unsigned(v, s);
    }
    return result;
  }

  void put(String signature, DalvikBody body) =>
      vm.registerNative('$_dataInput->$signature', body);
  put('readBoolean()Z', (v, a) => unsigned(v, v.object(a[0])) == 0 ? 0 : 1);
  put('readByte()B', (v, a) => unsigned(v, v.object(a[0])).toSigned(8));
  put('readUnsignedByte()I', (v, a) => unsigned(v, v.object(a[0])));
  put('readShort()S', (v, a) => number(v, v.object(a[0]), 2).toSigned(16));
  put('readUnsignedShort()I', (v, a) => number(v, v.object(a[0]), 2));
  put('readChar()C', (v, a) => number(v, v.object(a[0]), 2));
  put('readInt()I', (v, a) => number(v, v.object(a[0]), 4).toSigned(32));
  put('readLong()J', (v, a) => number(v, v.object(a[0]), 8));
  put('readFloat()F', (v, a) => number(v, v.object(a[0]), 4).toSigned(32));
  put('readDouble()D', (v, a) => number(v, v.object(a[0]), 8));
  for (final sliced in [false, true]) {
    put('readFully([B${sliced ? 'II' : ''})V', (v, a) {
      final b = _bytes(v, a[1]),
          offset = sliced ? _int(a[2]) : 0,
          length = sliced ? _int(a[3]) : b.values.length;
      if (length < 0) v.throwJava('Ljava/lang/IndexOutOfBoundsException;');
      var count = 0;
      while (count < length) {
        final n = _readBytes(
          v,
          v.object(a[0]),
          b,
          offset + count,
          length - count,
        );
        if (n < 0) v.throwJava('Ljava/io/EOFException;');
        count += n;
      }
      return null;
    });
  }
  put('skipBytes(I)I', (v, a) {
    final requested = _int(a[1]);
    var total = 0;
    while (total < requested) {
      final args = <Object?>[0, 0];
      JBits.setWide(args, 0, requested - total);
      final n = _call(v, v.object(a[0]), _input, 'skip(J)J', args) as int;
      if (n <= 0) break;
      total += n;
    }
    return total;
  });
  put('readUTF()Ljava/lang/String;', (v, a) {
    final s = v.object(a[0]), count = number(v, v.object(a[0]), 2);
    final bytes = List.generate(count, (_) => unsigned(v, s));
    final chars = <int>[];
    var position = 0;
    while (position < count) {
      final first = bytes[position++];
      if (first < 128) {
        chars.add(first);
        continue;
      }
      final n = first & 0xe0 == 0xc0
          ? 1
          : first & 0xf0 == 0xe0
          ? 2
          : -1;
      if (n < 0 || position + n > count) {
        v.throwJava(
          'Ljava/io/UTFDataFormatException;',
          'Malformed modified UTF-8',
        );
      }
      var value = first & (n == 1 ? 31 : 15);
      for (var i = 0; i < n; i++) {
        final byte = bytes[position++];
        if (byte & 0xc0 != 0x80) {
          v.throwJava('Ljava/io/UTFDataFormatException;');
        }
        value = (value << 6) | (byte & 63);
      }
      chars.add(value);
    }
    return v.newString(String.fromCharCodes(chars));
  });
  void out(String signature, DalvikBody body) =>
      vm.registerNative('$_dataOutput->$signature', body);
  out('write(I)V', (v, a) {
    final s = v.object(a[0]).nativeValue as _FilterOutput;
    _write(v, s.stream, _int(a[1]));
    s.count(1);
    return null;
  });
  out('write([BII)V', (v, a) {
    final s = v.object(a[0]).nativeValue as _FilterOutput;
    _writeBytes(v, s.stream, _bytes(v, a[1]), _int(a[2]), _int(a[3]));
    s.count(_int(a[3]));
    return null;
  });
  out(
    'size()I',
    (v, a) => (v.object(a[0]).nativeValue as _FilterOutput).written,
  );
  void writeNumber(DalvikRuntime v, DalvikObject s, int value, int bytes) {
    for (var shift = (bytes - 1) * 8; shift >= 0; shift -= 8) {
      _write(v, s, (value >> shift) & 255);
    }
  }

  out('writeBoolean(Z)V', (v, a) {
    _write(v, v.object(a[0]), _int(a[1]) == 0 ? 0 : 1);
    return null;
  });
  for (final entry in {
    'writeByte(I)V': 1,
    'writeShort(I)V': 2,
    'writeChar(I)V': 2,
    'writeInt(I)V': 4,
    'writeFloat(F)V': 4,
    'writeLong(J)V': 8,
    'writeDouble(D)V': 8,
  }.entries) {
    out(entry.key, (v, a) {
      var bits = entry.value == 8 ? JBits.wide(a, 1) : _int(a[1]);
      // DataOutputStream uses floatToIntBits/doubleToLongBits, which canonicalize NaNs.
      if (entry.key == 'writeFloat(F)V' && JBits.float(a, 1).isNaN) {
        bits = 0x7fc00000;
      }
      if (entry.key == 'writeDouble(D)V' && JBits.doubleValue(a, 1).isNaN) {
        bits = 0x7ff8000000000000;
      }
      writeNumber(v, v.object(a[0]), bits, entry.value);
      return null;
    });
  }
  out('writeBytes(Ljava/lang/String;)V', (v, a) {
    for (final unit in v.string(a[1]).codeUnits) {
      _write(v, v.object(a[0]), unit);
    }
    return null;
  });
  out('writeChars(Ljava/lang/String;)V', (v, a) {
    for (final unit in v.string(a[1]).codeUnits) {
      writeNumber(v, v.object(a[0]), unit, 2);
    }
    return null;
  });
  out('writeUTF(Ljava/lang/String;)V', (v, a) {
    final bytes = <int>[];
    for (final unit in v.string(a[1]).codeUnits) {
      if (unit > 0 && unit < 128) {
        bytes.add(unit);
      } else if (unit <= 2047) {
        bytes.addAll([0xc0 | (unit >> 6), 0x80 | (unit & 63)]);
      } else {
        bytes.addAll([
          0xe0 | (unit >> 12),
          0x80 | ((unit >> 6) & 63),
          0x80 | (unit & 63),
        ]);
      }
    }
    if (bytes.length > 65535) {
      v.throwJava(
        'Ljava/io/UTFDataFormatException;',
        'Encoded string exceeds 65535 bytes',
      );
    }
    writeNumber(v, v.object(a[0]), bytes.length, 2);
    final array = _copyBytes(v, bytes);
    _writeBytes(v, v.object(a[0]), array, 0, bytes.length);
    return null;
  });
}

void _registerCompression(DalvikRuntime vm) {
  const crc = 'Ljava/util/zip/CRC32;';
  vm.registerNative('$crc-><init>()V', (v, a) {
    v.object(a[0]).nativeValue = _Crc32();
    return null;
  });
  vm.registerNative(
    '$crc->getValue()J',
    (v, a) => (v.object(a[0]).nativeValue as _Crc32).value,
  );
  vm.registerNative('$crc->reset()V', (v, a) {
    (v.object(a[0]).nativeValue as _Crc32).state = 0xffffffff;
    return null;
  });
  vm.registerNative('$crc->update(I)V', (v, a) {
    (v.object(a[0]).nativeValue as _Crc32).update(_int(a[1]));
    return null;
  });
  for (final sliced in [false, true]) {
    vm.registerNative('$crc->update([B${sliced ? 'II' : ''})V', (v, a) {
      final b = _bytes(v, a[1]),
          offset = sliced ? _int(a[2]) : 0,
          length = sliced ? _int(a[3]) : b.values.length;
      _bounds(v, b, offset, length);
      final s = v.object(a[0]).nativeValue as _Crc32;
      for (var n = 0; n < length; n++) {
        s.update(_int(b.values[offset + n]));
      }
      return null;
    });
  }
  for (final withSize in [false, true]) {
    vm.registerNative(
      '$_gzipInput-><init>(Ljava/io/InputStream;${withSize ? 'I' : ''})V',
      (v, a) {
        final size = withSize ? _int(a[2]) : 512;
        if (size <= 0) {
          v.throwJava(
            'Ljava/lang/IllegalArgumentException;',
            'Buffer size <= 0',
          );
        }
        final s = _GzipInput(v.object(a[1]), size);
        v.object(a[0]).nativeValue = s;
        s.initialize(v);
        return null;
      },
    );
  }
  vm.registerNative(
    '$_gzipInput->read([BII)I',
    (v, a) => (v.object(a[0]).nativeValue as _GzipInput).readMany(
      v,
      _bytes(v, a[1]),
      _int(a[2]),
      _int(a[3]),
    ),
  );
  vm.registerNative('$_gzipInput->read()I', (v, a) {
    final byte = DalvikArray('[B', 1);
    final n = (v.object(a[0]).nativeValue as _GzipInput).readMany(
      v,
      byte,
      0,
      1,
    );
    return n < 0 ? -1 : _int(byte.values[0]) & 255;
  });
  vm.registerNative('$_gzipInput->available()I', (v, a) {
    final s = v.object(a[0]).nativeValue as _GzipInput;
    s.ensureOpen(v);
    return s.ended && s.position >= s.output.pending.length ? 0 : 1;
  });
  vm.registerNative('$_gzipInput->markSupported()Z', (v, a) => 0);
  vm.registerNative('$_gzipInput->mark(I)V', (v, a) => null);
  vm.registerNative(
    '$_gzipInput->reset()V',
    (v, a) => v.throwJava('Ljava/io/IOException;', 'mark/reset not supported'),
  );
  vm.registerNative('$_gzipInput->skip(J)J', (v, a) {
    if (JBits.wide(a, 1) < 0) {
      v.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'negative skip length',
      );
    }
    return v.nativeMethods['$_input->skip(J)J']!(v, a);
  });
  vm.registerNative('$_gzipInput->close()V', (v, a) {
    final s = v.object(a[0]).nativeValue as _GzipInput;
    if (!s.closed) {
      s.closed = true;
      if (!s.ended) {
        try {
          s.decoder.close();
        } catch (_) {
          /* Closing does not validate unread compressed bytes. */
        }
      }
      _call(v, s.stream, _input, 'close()V');
    }
    return null;
  });
}

void _registerResources(DalvikRuntime vm) {
  DalvikObject? load(DalvikRuntime v, String path) {
    final loader = v.resourceLoader;
    if (loader == null) {
      throw MissingDalvikBridge('APK resource loader for $path');
    }
    final bytes = loader(path);
    return bytes == null ? null : javaByteArrayInputStream(v, bytes);
  }

  vm.registerNative(
    'Ljava/lang/Class;->getResourceAsStream(Ljava/lang/String;)Ljava/io/InputStream;',
    (v, a) {
      var path = v.string(a[1]);
      if (path.startsWith('/')) {
        path = path.substring(1);
      } else {
        var type = v.object(a[0]).nativeValue as String;
        while (type.startsWith('[')) {
          type = type.substring(1);
        }
        final separator = type.lastIndexOf('/');
        if (separator >= 0) {
          path =
              '${type.substring(type.startsWith('L') ? 1 : 0, separator + 1)}$path';
        }
      }
      return load(v, path);
    },
  );
  vm.registerExternalClass('Ljava/lang/ClassLoader;');
  vm.registerExternalClass(
    'Ldalvik/system/BaseDexClassLoader;',
    superclass: 'Ljava/lang/ClassLoader;',
  );
  vm.registerExternalClass(
    'Ldalvik/system/PathClassLoader;',
    superclass: 'Ldalvik/system/BaseDexClassLoader;',
  );
  vm.registerNative(
    'Ljava/lang/ClassLoader;->getResourceAsStream(Ljava/lang/String;)Ljava/io/InputStream;',
    (v, a) => load(v, v.string(a[1])),
  );
}
