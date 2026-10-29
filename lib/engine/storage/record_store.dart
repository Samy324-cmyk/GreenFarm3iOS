import 'dart:io';
import 'dart:typed_data';

import 'binary.dart';

/// Filesystem implementation of d.b.d.b / RecordStore's normal local mode.
///
/// Names, record ids, headers, CRC byte order, revision cap and promotion match
/// the recovered code. Filesystem failures are surfaced, and truncated records
/// are rejected instead of exposing the original's zero-filled partial reads.
/// Use one instance per store in the owning isolate; this is not a database
/// with cross-process locking. The caller supplies its app documents directory.
class RecordStore {
  RecordStore._(
    this.directory,
    this.name,
    this.backupLimit,
    this.maxRecordBytes,
  );

  factory RecordStore.open(
    Directory directory,
    String name, {
    bool createIfMissing = false,
    int backupLimit = 0,
    int maxRecordBytes = 64 * 1024 * 1024,
  }) {
    final normalized = name.replaceAll('/', 'S');
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.contains(RegExp(r'[\\:\x00]'))) {
      throw ArgumentError.value(name, 'name', 'Unsafe record-store name');
    }
    if (backupLimit < 0 || maxRecordBytes < 0) {
      throw ArgumentError('Store limits must not be negative');
    }
    final store = RecordStore._(
      directory,
      normalized,
      backupLimit,
      maxRecordBytes,
    );
    if (!store._file(normalized).existsSync()) {
      if (!createIfMissing) {
        throw FileSystemException(
          'Record store does not exist',
          store._file(normalized).path,
        );
      }
      directory.createSync(recursive: true);
      _writeAtomic(store._file(normalized), const [0]);
    }
    return store;
  }

  final Directory directory;
  final String name;
  final int backupLimit;
  final int maxRecordBytes;

  File _file(String filename) =>
      File('${directory.path}${Platform.pathSeparator}$filename');
  String _base(int id) => '${name}_$id';

  /// Original n()/m(): count the contiguous ids, not the header's signed byte.
  int get recordCount {
    var count = 0;
    while (_file(_base(count + 1)).existsSync() ||
        _file('${_base(count + 1)}_CRC1').existsSync()) {
      count++;
    }
    return count;
  }

  int addRecord(List<int> data, {int offset = 0, int? length}) {
    final id = recordCount + 1;
    _writeRecord(id, _slice(data, offset, length));
    _writeAtomic(_file(name), [id & 0xff]);
    return id;
  }

  void setRecord(int id, List<int> data, {int offset = 0, int? length}) {
    if (id <= 0 || id > recordCount) {
      throw RangeError.value(id, 'id', 'Record does not exist');
    }
    _writeRecord(id, _slice(data, offset, length));
    _writeAtomic(_file(name), [recordCount & 0xff]);
  }

  Uint8List _slice(List<int> data, int offset, int? length) {
    final count = length ?? data.length - offset;
    RangeError.checkValidRange(offset, offset + count, data.length);
    if (count > maxRecordBytes) {
      throw ArgumentError('Record exceeds size limit');
    }
    return Uint8List.fromList(data.sublist(offset, offset + count));
  }

  List<int> _revisions(int id) {
    final expression = RegExp('^${RegExp.escape(_base(id))}_CRC([0-9]+)\$');
    final result = <int>[];
    for (final file in directory.listSync(followLinks: false)) {
      if (file is! File) continue;
      final match = expression.firstMatch(file.uri.pathSegments.last);
      final revision = match == null ? null : int.tryParse(match.group(1)!);
      if (revision != null && revision >= 1 && revision <= 10000) {
        result.add(revision);
      }
    }
    result.sort();
    return result;
  }

  int _nextRevision(int id) {
    for (final revision in _revisions(id).reversed) {
      if (_file('${_base(id)}_saved$revision').existsSync() &&
          _file('${_base(id)}_CRC$revision').lengthSync() == 8) {
        return revision < 10000 ? revision + 1 : 10000;
      }
    }
    return 1;
  }

  void _writeRecord(int id, Uint8List bytes) {
    final revision = _nextRevision(id);
    final checksum = BinaryWriter(endian: Endian.big)..writeInt64(crc32(bytes));
    final record = BinaryWriter(endian: Endian.big)
      ..writeByte(id)
      ..writeInt32(bytes.length)
      ..writeBytes(bytes);
    // The original writes CRC first. An incomplete new revision is skipped on
    // read, so the previous valid revision remains available after interruption.
    _writeAtomic(_file('${_base(id)}_CRC$revision'), checksum.toBytes());
    _writeAtomic(_file('${_base(id)}_saved$revision'), record.toBytes());
    if (backupLimit > 0 && revision - backupLimit > 0) {
      _deleteIfPresent(_file('${_base(id)}_saved${revision - backupLimit}'));
    }
    if (backupLimit > 0 && revision % 625 == 0 && revision < 10000) {
      final first = (revision - 625 - backupLimit).clamp(1, 10000);
      for (var old = first; old < revision - backupLimit; old++) {
        if (old % 625 != 0 && (old - 1) % 625 != 0) {
          _deleteIfPresent(_file('${_base(id)}_CRC$old'));
        }
      }
    }
  }

  /// Newest valid journal is promoted to the base file and journals are cleared.
  /// Falls back to the base record, which has no CRC in the Android format.
  Uint8List? getRecord(int id) {
    if (id <= 0) throw RangeError.value(id, 'id');
    for (final revision in _revisions(id).reversed) {
      final file = _file('${_base(id)}_saved$revision');
      final data = _readRecord(file, id);
      if (data == null) continue;
      final crcFile = _file('${_base(id)}_CRC$revision');
      if (crcFile.lengthSync() != 8) continue;
      final storedCrc = BinaryReader(
        crcFile.readAsBytesSync(),
        endian: Endian.big,
      ).readInt64();
      if (storedCrc != crc32(data)) continue;
      _writeAtomic(_file(_base(id)), file.readAsBytesSync());
      _clearJournals(id);
      return data;
    }
    _clearJournals(id);
    return _readRecord(_file(_base(id)), id);
  }

  Uint8List? _readRecord(File file, int id) {
    if (!file.existsSync()) return null;
    final fileSize = file.lengthSync();
    if (fileSize < 5 || fileSize > maxRecordBytes + 5) return null;
    final reader = BinaryReader(file.readAsBytesSync(), endian: Endian.big);
    final storedId = reader.readUint8();
    final length = reader.readInt32();
    if (storedId != (id & 0xff) || length < 0 || length != reader.remaining) {
      return null;
    }
    return reader.readBytes(length);
  }

  void _clearJournals(int id) {
    final expression = RegExp(
      '^${RegExp.escape(_base(id))}_(CRC|saved)[0-9]+\$',
    );
    for (final file in directory.listSync(followLinks: false)) {
      if (file is File && expression.hasMatch(file.uri.pathSegments.last)) {
        file.deleteSync();
      }
    }
  }

  void deleteRecord(int id) {
    if (id <= 0) throw RangeError.value(id, 'id');
    _clearJournals(id);
    _deleteIfPresent(_file(_base(id)));
  }

  void deleteStore() {
    final count = recordCount;
    for (var id = 1; id <= count; id++) {
      deleteRecord(id);
    }
    _deleteIfPresent(_file(name));
  }

  /// Android f() has no persistent handle to close.
  void close() {}

  static void _deleteIfPresent(File file) {
    if (file.existsSync()) file.deleteSync();
  }

  static void _writeAtomic(File destination, List<int> bytes) {
    final temporary = File('${destination.path}.writing');
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(destination.path);
  }
}
