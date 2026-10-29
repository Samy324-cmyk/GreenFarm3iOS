import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../storage/binary.dart' show crc32;
import 'java_collections.dart' show javaEnumeration;
import 'java_files.dart' show JavaFilePath;
import 'java_io.dart' show javaByteArrayInputStream, javaInflateRaw;
import 'runtime.dart';

const _zipFile = 'Ljava/util/zip/ZipFile;';
const _zipEntry = 'Ljava/util/zip/ZipEntry;';
const _enumeration = 'Ljava/util/Enumeration;';
const _zipEnumeration = 'Lport/ZipEnumeration;';
const _zipStream = 'Lport/ZipEntryInputStream;';
const _input = 'Ljava/io/InputStream;';

/// Metadata read from an actual ZIP central-directory entry.
class JavaZipEntry {
  const JavaZipEntry(
    this.name, {
    this.size = -1,
    this.compressedSize = -1,
    this.crc = -1,
    this.method = -1,
    this.flags = 0,
    this.localOffset = -1,
    this.comment,
  });
  final String name;
  final int size, compressedSize, crc, method, flags, localOffset;
  final String? comment;
}

String _utf8(List<int> bytes) {
  // Java's UTF-8 String constructor retains a leading BOM.
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return '\ufeff${utf8.decode(bytes.sublist(3), allowMalformed: true)}';
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Reads stored/deflated, single-disk ZIP32 archives, including data descriptors.
/// APK bytes remain data; none of the Android executable entries are executed.
class JavaZipArchive {
  JavaZipArchive._(this._bytes, this.entries, this.comment, this.centralOffset);
  final Uint8List _bytes;
  final List<JavaZipEntry> entries;
  final String? comment;
  final int centralOffset;
  late final Map<String, JavaZipEntry> _byName = {
    for (final entry in entries) entry.name: entry,
  };

  factory JavaZipArchive.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    void require(int offset, int size, String field) {
      if (offset < 0 || size < 0 || offset > bytes.length - size) {
        throw FormatException('Truncated ZIP $field');
      }
    }

    int u16(int offset) => data.getUint16(offset, Endian.little);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    require(0, 22, 'end record');
    if (u32(0) == 0x06054b50) {
      throw const FormatException('Empty zip archive not supported');
    }
    if (u32(0) != 0x04034b50) {
      throw const FormatException('Not a zip archive');
    }
    var end = -1;
    final minimum = bytes.length - 22 - 65535;
    for (
      var offset = bytes.length - 22;
      offset >= 0 && offset >= minimum;
      offset--
    ) {
      if (u32(offset) == 0x06054b50 &&
          offset + 22 + u16(offset + 20) == bytes.length) {
        end = offset;
        break;
      }
    }
    if (end < 0) throw const FormatException('ZIP end record not found');
    final count = u16(end + 10);
    final centralSize = u32(end + 12), centralOffset = u32(end + 16);
    if (count == 0xffff ||
        centralSize == 0xffffffff ||
        centralOffset == 0xffffffff) {
      throw const FormatException('ZIP64 archives are not supported');
    }
    if (u16(end + 4) != 0 || u16(end + 6) != 0 || u16(end + 8) != count) {
      throw const FormatException('Spanned archives not supported');
    }
    require(centralOffset, centralSize, 'central directory');
    if (centralOffset + centralSize != end) {
      throw const FormatException('ZIP central-directory bounds mismatch');
    }
    final commentLength = u16(end + 20);
    final comment = commentLength == 0 ? null : _utf8(bytes.sublist(end + 22));
    final entries = <JavaZipEntry>[];
    final names = <String>{};
    var offset = centralOffset;
    for (var index = 0; index < count; index++) {
      require(offset, 46, 'central entry');
      if (offset + 46 > end || u32(offset) != 0x02014b50) {
        throw const FormatException('ZIP central entry signature not found');
      }
      final flags = u16(offset + 8), method = u16(offset + 10);
      final crc = u32(offset + 16), compressed = u32(offset + 20);
      final size = u32(offset + 24), local = u32(offset + 42);
      if (flags & 1 != 0) {
        throw FormatException('Invalid General Purpose Bit Flag: $flags');
      }
      if (compressed == 0xffffffff ||
          size == 0xffffffff ||
          local == 0xffffffff) {
        throw const FormatException('ZIP64 entry is not supported');
      }
      if (u16(offset + 34) != 0) {
        throw const FormatException('Spanned ZIP entry not supported');
      }
      if (local >= centralOffset) {
        throw const FormatException(
          'Local file header offset is after central directory',
        );
      }
      final nameLength = u16(offset + 28), extraLength = u16(offset + 30);
      final commentLength = u16(offset + 32);
      final next = offset + 46 + nameLength + extraLength + commentLength;
      if (next > end) throw const FormatException('Truncated ZIP entry fields');
      final nameBytes = bytes.sublist(offset + 46, offset + 46 + nameLength);
      if (nameBytes.contains(0)) {
        throw const FormatException('Filename contains NUL byte');
      }
      final name = _utf8(nameBytes);
      if (!names.add(name)) {
        throw FormatException('Duplicate entry name: $name');
      }
      entries.add(
        JavaZipEntry(
          name,
          size: size,
          compressedSize: compressed,
          crc: crc,
          method: method,
          flags: flags,
          localOffset: local,
          comment: commentLength == 0
              ? null
              : _utf8(bytes.sublist(next - commentLength, next)),
        ),
      );
      offset = next;
    }
    if (offset != end) {
      throw const FormatException('ZIP central-directory entry count mismatch');
    }
    return JavaZipArchive._(
      bytes,
      List.unmodifiable(entries),
      comment,
      centralOffset,
    );
  }

  JavaZipEntry? getEntry(String name) => _byName[name] ?? _byName['$name/'];

  Uint8List read(JavaZipEntry requested) {
    final entry = getEntry(requested.name);
    if (entry == null) {
      throw ArgumentError.value(requested.name, 'entry', 'Not in archive');
    }
    final offset = entry.localOffset;
    final data = ByteData.sublistView(_bytes);
    if (offset < 0 ||
        offset > centralOffset - 30 ||
        data.getUint32(offset, Endian.little) != 0x04034b50) {
      throw const FormatException('ZIP local file header signature not found');
    }
    final flags = data.getUint16(offset + 6, Endian.little);
    if (flags & 1 != 0) {
      throw FormatException('Invalid General Purpose Bit Flag: $flags');
    }
    final nameLength = data.getUint16(offset + 26, Endian.little);
    final extraLength = data.getUint16(offset + 28, Endian.little);
    final start = offset + 30 + nameLength + extraLength;
    if (start > centralOffset || entry.compressedSize > centralOffset - start) {
      throw const FormatException('Truncated ZIP entry payload');
    }
    final compressed = Uint8List.sublistView(
      _bytes,
      start,
      start + entry.compressedSize,
    );
    late List<int> decoded;
    if (entry.method == 0) {
      decoded = compressed;
      if (crc32(decoded) != entry.crc) {
        throw FormatException('ZIP entry CRC mismatch: ${entry.name}');
      }
    } else if (entry.method == 8) {
      decoded = javaInflateRaw(compressed, crc32: entry.crc, size: entry.size);
    } else {
      throw FormatException(
        'Unsupported ZIP compression method: ${entry.method}',
      );
    }
    if (decoded.length != entry.size) {
      throw FormatException('ZIP entry size mismatch: ${entry.name}');
    }
    return Uint8List.fromList(decoded);
  }
}

class _ZipState {
  _ZipState(this.name, this.archive);
  final String name;
  final JavaZipArchive archive;
  bool closed = false;
  late final Map<String, DalvikObject> entries = {
    for (final entry in archive.entries)
      entry.name: DalvikObject(_zipEntry, nativeValue: entry),
  };
  void ensureOpen(DalvikRuntime vm) {
    if (closed) {
      vm.throwJava('Ljava/lang/IllegalStateException;', 'Zip file closed');
    }
  }
}

class _ZipCursor {
  _ZipCursor(this.owner, this.delegate);
  final _ZipState owner;
  final DalvikObject delegate;
}

class _ZipStream {
  _ZipStream(this.owner, this.delegate);
  final _ZipState owner;
  final DalvikObject delegate;
  bool closed = false;
  void ensureOpen(DalvikRuntime vm) {
    if (closed || owner.closed) {
      vm.throwJava('Ljava/io/IOException;', 'Stream closed');
    }
  }
}

void registerJavaZip(DalvikRuntime vm, {String? workingDirectory}) {
  vm.registerExternalClass(_zipFile, interfaces: ['Ljava/io/Closeable;']);
  vm.registerExternalClass(_zipEntry, interfaces: ['Ljava/lang/Cloneable;']);
  vm.registerExternalClass(_zipEnumeration, interfaces: [_enumeration]);
  vm.registerExternalClass(_zipStream, superclass: _input);
  vm.registerExternalClass(
    'Ljava/util/zip/ZipException;',
    superclass: 'Ljava/io/IOException;',
  );
  _ZipState state(Object? value) => vm.object(value).nativeValue as _ZipState;
  JavaZipEntry entry(Object? value) =>
      vm.object(value).nativeValue as JavaZipEntry;
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  T zipOperation<T>(T Function() action) {
    try {
      return action();
    } on FormatException catch (error) {
      vm.throwJava('Ljava/util/zip/ZipException;', error.message);
    } on FileSystemException catch (error) {
      vm.throwJava(
        error.osError?.errorCode == 2
            ? 'Ljava/io/FileNotFoundException;'
            : 'Ljava/io/IOException;',
        error.message,
      );
    }
  }

  void construct(Object? receiver, String name) {
    var absolute = name;
    if (!File(name).isAbsolute) {
      if (workingDirectory == null || !Directory(workingDirectory).isAbsolute) {
        throw MissingDalvikBridge(
          'Relative ZipFile path requires a host workingDirectory: $name',
        );
      }
      absolute = '$workingDirectory/$name';
    }
    final archive = zipOperation(
      () => JavaZipArchive.parse(File(absolute).readAsBytesSync()),
    );
    vm.object(receiver).nativeValue = _ZipState(name, archive);
  }

  native(_zipFile, '<init>(Ljava/lang/String;)V', (v, a) {
    construct(a[0], v.string(a[1]));
    return null;
  });
  native(_zipFile, '<init>(Ljava/io/File;)V', (v, a) {
    construct(a[0], (v.object(a[1]).nativeValue as JavaFilePath).path);
    return null;
  });
  native(_zipFile, 'close()V', (v, a) {
    state(a[0]).closed = true;
    return null;
  });
  native(_zipFile, 'size()I', (v, a) {
    final s = state(a[0]);
    s.ensureOpen(v);
    return s.entries.length;
  });
  native(
    _zipFile,
    'getName()Ljava/lang/String;',
    (v, a) => v.intern(state(a[0]).name),
  );
  native(_zipFile, 'getComment()Ljava/lang/String;', (v, a) {
    final s = state(a[0]);
    s.ensureOpen(v);
    return s.archive.comment == null ? null : v.intern(s.archive.comment!);
  });
  native(_zipFile, 'getEntry(Ljava/lang/String;)Ljava/util/zip/ZipEntry;', (
    v,
    a,
  ) {
    final s = state(a[0]);
    s.ensureOpen(v);
    final name = v.string(a[1]);
    return s.entries[name] ?? s.entries['$name/'];
  });
  native(_zipFile, 'entries()Ljava/util/Enumeration;', (v, a) {
    final s = state(a[0]);
    s.ensureOpen(v);
    return DalvikObject(
      _zipEnumeration,
      nativeValue: _ZipCursor(s, javaEnumeration(s.entries.values)),
    );
  });
  for (final signature in [
    'hasMoreElements()Z',
    'nextElement()Ljava/lang/Object;',
  ]) {
    native(_zipEnumeration, signature, (v, a) {
      final cursor = v.object(a[0]).nativeValue as _ZipCursor;
      cursor.owner.ensureOpen(v);
      return v.call('$_enumeration->$signature', [
        cursor.delegate,
      ], kind: 'interface');
    });
  }
  native(
    _zipFile,
    'getInputStream(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;',
    (v, a) {
      final s = state(a[0]);
      s.ensureOpen(v);
      final found = s.archive.getEntry(entry(a[1]).name);
      if (found == null) return null;
      final bytes = zipOperation(() => s.archive.read(found));
      return DalvikObject(
        _zipStream,
        nativeValue: _ZipStream(s, javaByteArrayInputStream(v, bytes)),
      );
    },
  );
  for (final signature in ['read()I', 'read([BII)I', 'read([B)I', 'skip(J)J']) {
    native(_zipStream, signature, (v, a) {
      final stream = v.object(a[0]).nativeValue as _ZipStream;
      stream.ensureOpen(v);
      return v.call('$_input->$signature', [
        stream.delegate,
        ...a.skip(1),
      ], kind: 'virtual');
    });
  }
  native(_zipStream, 'available()I', (v, a) {
    final stream = v.object(a[0]).nativeValue as _ZipStream;
    if (stream.closed) return 0;
    stream.ensureOpen(v);
    return v.call('$_input->available()I', [stream.delegate], kind: 'virtual');
  });
  native(_zipStream, 'close()V', (v, a) {
    (v.object(a[0]).nativeValue as _ZipStream).closed = true;
    return null;
  });
  native(_zipEntry, '<init>(Ljava/lang/String;)V', (v, a) {
    final name = v.string(a[1]);
    if (utf8.encode(name).length > 65535) {
      v.throwJava('Ljava/lang/IllegalArgumentException;', 'name too long');
    }
    v.object(a[0]).nativeValue = JavaZipEntry(name);
    return null;
  });
  native(
    _zipEntry,
    'getName()Ljava/lang/String;',
    (v, a) => v.intern(entry(a[0]).name),
  );
  native(_zipEntry, 'getSize()J', (v, a) => entry(a[0]).size);
  native(
    _zipEntry,
    'getCompressedSize()J',
    (v, a) => entry(a[0]).compressedSize,
  );
  native(_zipEntry, 'getCrc()J', (v, a) => entry(a[0]).crc);
  native(_zipEntry, 'getMethod()I', (v, a) => entry(a[0]).method);
  native(
    _zipEntry,
    'isDirectory()Z',
    (v, a) => entry(a[0]).name.endsWith('/') ? 1 : 0,
  );
  native(
    _zipEntry,
    'toString()Ljava/lang/String;',
    (v, a) => v.intern(entry(a[0]).name),
  );
  native(
    _zipEntry,
    'hashCode()I',
    (v, a) => v.call('Ljava/lang/String;->hashCode()I', [
      v.intern(entry(a[0]).name),
    ], kind: 'virtual'),
  );
  native(
    _zipEntry,
    'getComment()Ljava/lang/String;',
    (v, a) =>
        entry(a[0]).comment == null ? null : v.intern(entry(a[0]).comment!),
  );
}
