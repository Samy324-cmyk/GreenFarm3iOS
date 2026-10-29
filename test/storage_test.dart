import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/storage/storage.dart';

void main() {
  final vectors = (jsonDecode(
    File('test/fixtures/storage_vectors.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  group('Original Java codec differential fixtures', () {
    for (final vector in vectors) {
      test('case ${vector['case']}: gzip bytes, XXTEA bytes and CRC', () {
        final raw = base64Decode(vector['raw'] as String);
        final key = base64Decode(vector['key'] as String);
        final compressed = base64Decode(vector['gzip'] as String);
        final encrypted = base64Decode(vector['encrypted'] as String);
        expect(crc32(raw), vector['crc32']);
        expect(LegacyGzip.encode(raw), compressed);
        expect(LegacyGzip.decode(compressed), raw);
        expect(LegacyXxtea.encrypt(compressed, key), encrypted);
        expect(LegacyXxtea.decrypt(encrypted, key), compressed);
      });
    }
    test('CRC can continue from a previous segment', () {
      expect(
        crc32(ascii.encode('56789'), previous: crc32(ascii.encode('1234'))),
        0xcbf43926,
      );
    });
    test('gzip bounds output and rejects corrupted trailer', () {
      final compressed = LegacyGzip.encode(List<int>.filled(10000, 65));
      expect(
        () => LegacyGzip.decode(compressed, maxOutputBytes: 9999),
        throwsFormatException,
      );
      compressed[compressed.length - 8] ^= 1;
      expect(() => LegacyGzip.decode(compressed), throwsFormatException);
    });
    test('XXTEA rejects malformed ciphertext and wrong key', () {
      expect(() => LegacyXxtea.decrypt([1, 2, 3], [1]), throwsFormatException);
      final vector = vectors[1];
      expect(
        () => LegacyXxtea.decrypt(base64Decode(vector['encrypted'] as String), [
          99,
        ]),
        throwsFormatException,
      );
    });
  });

  group('GLLib binary fields', () {
    test(
      'known signed values use little endian and wrap Java-sized fields',
      () {
        final writer = BinaryWriter()
          ..writeByte(-1)
          ..writeInt16(-32768)
          ..writeInt32(0x12345678)
          ..writeInt32(0xffffffff)
          ..writeInt64(-0x0123456789abcdef);
        expect(writer.toBytes().sublist(0, 11), [
          255,
          0,
          128,
          120,
          86,
          52,
          18,
          255,
          255,
          255,
          255,
        ]);
        final reader = BinaryReader(writer.toBytes());
        expect(reader.readInt8(), -1);
        expect(reader.readInt16(), -32768);
        expect(reader.readInt32(), 0x12345678);
        expect(reader.readInt32(), -1);
        expect(reader.readInt64(), -0x0123456789abcdef);
        expect(reader.remaining, 0);
        expect(reader.readUint8, throwsFormatException);
      },
    );
    test('big endian record length and truncated reads', () {
      final reader = BinaryReader([0, 0, 1, 2], endian: Endian.big);
      expect(reader.readInt32(), 258);
      expect(() => BinaryReader([0, 0]).readInt32(), throwsFormatException);
      expect(() => BinaryReader([0]).readBytes(-1), throwsFormatException);
    });
  });

  group('SaveGameManager local envelope', () {
    test('single envelope matches independently generated Java payload', () {
      final vector = vectors[1];
      final raw = base64Decode(vector['raw'] as String);
      final key = base64Decode(vector['key'] as String);
      final encrypted = base64Decode(vector['encrypted'] as String);
      final expected = BinaryWriter()
        ..writeInt32(0x10203040)
        ..writeInt32(vector['crc32'] as int)
        ..writeInt32(encrypted.length)
        ..writeBytes(encrypted)
        ..writeInt32(1);
      final encoded = SaveGameCodec.encode([
        SaveBlock(0x10203040, raw),
      ], key: key);
      expect(encoded, expected.toBytes());
      final decoded = SaveGameCodec.decode(encoded, key: key);
      expect(decoded.single.type, 0x10203040);
      expect(decoded.single.data.bytes, raw);
    });
    test(
      'multiple blocks preserve signed types and independent byte copies',
      () {
        final source = [1, 2, 3];
        final block = SaveBlock(-1, source);
        source[0] = 77;
        final encoded = SaveGameCodec.encode(
          [
            block,
            SaveBlock(2, [4, 5]),
          ],
          key: [12],
        );
        final blocks = SaveGameCodec.decode(encoded, key: [12]);
        expect(blocks.map((b) => b.type), [-1, 2]);
        expect(blocks[0].data.bytes, [1, 2, 3]);
        expect(() => blocks[0].data.bytes[0] = 44, throwsUnsupportedError);
        expect(
          () => SaveGameCodec.decode(encoded, key: [12], maxDecodedBytes: 4),
          throwsFormatException,
        );
      },
    );
    test('rejects bad CRC, inconsistent count, truncation and empty block', () {
      final encoded = SaveGameCodec.encode(
        [
          SaveBlock(0, [1, 2, 3]),
        ],
        key: [1],
      );
      final corrupt = Uint8List.fromList(encoded)..[4] ^= 1;
      expect(
        () => SaveGameCodec.decode(corrupt, key: [1]),
        throwsFormatException,
      );
      final count = Uint8List.fromList(encoded)..[encoded.length - 4] = 0;
      expect(
        () => SaveGameCodec.decode(count, key: [1]),
        throwsFormatException,
      );
      expect(
        () => SaveGameCodec.decode(encoded.sublist(0, 15), key: [1]),
        throwsFormatException,
      );
      expect(
        () => SaveGameCodec.encode([SaveBlock(0, [])], key: []),
        throwsArgumentError,
      );
      expect(SaveGameCodec.decode([0, 0, 0, 0], key: []), isEmpty);
    });
  });

  group('RecordStore file compatibility and recovery', () {
    late Directory directory;
    late RecordStore store;
    setUp(() {
      directory = Directory.systemTemp.createTempSync(
        'green-farm-storage-test-',
      );
      store = RecordStore.open(directory, 'farm/save', createIfMissing: true);
    });
    tearDown(() => directory.deleteSync(recursive: true));
    File file(String name) =>
        File('${directory.path}${Platform.pathSeparator}$name');

    test('writes exact Android names, header and big endian CRC sidecar', () {
      expect(store.name, 'farmSsave');
      expect(store.addRecord(ascii.encode('123456789')), 1);
      expect(file('farmSsave').readAsBytesSync(), [1]);
      expect(file('farmSsave_1_saved1').readAsBytesSync(), [
        1,
        0,
        0,
        0,
        9,
        ...ascii.encode('123456789'),
      ]);
      expect(file('farmSsave_1_CRC1').readAsBytesSync(), [
        0,
        0,
        0,
        0,
        0xcb,
        0xf4,
        0x39,
        0x26,
      ]);
      expect(store.recordCount, 1);
      expect(store.getRecord(1), ascii.encode('123456789'));
      expect(file('farmSsave_1').existsSync(), isTrue);
      expect(file('farmSsave_1_CRC1').existsSync(), isFalse);
      expect(file('farmSsave_1_saved1').existsSync(), isFalse);
    });
    test('newest good revision wins; corrupt newest falls back', () {
      store.addRecord([1, 2]);
      store.setRecord(1, [3, 4]);
      file('farmSsave_1_saved2').writeAsBytesSync([1, 0, 0, 0, 2, 99, 99]);
      expect(store.getRecord(1), [1, 2]);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toSet(),
        {'farmSsave', 'farmSsave_1'},
      );
      store.setRecord(1, [5]);
      expect(store.getRecord(1), [5]);
    });
    test('incomplete journal falls back to durable base', () {
      store.addRecord([7]);
      store.getRecord(1);
      file('farmSsave_1_CRC1').writeAsBytesSync(List<int>.filled(8, 0));
      expect(store.getRecord(1), [7]);
      expect(file('farmSsave_1_CRC1').existsSync(), isFalse);
    });
    test('offset uses CRC of written slice and rejects impossible lengths', () {
      store.addRecord([88, 1, 2, 3, 99], offset: 1, length: 3);
      expect(store.getRecord(1), [1, 2, 3]);
      expect(() => store.addRecord([1], offset: 2), throwsRangeError);
      file('farmSsave_1').writeAsBytesSync([1, 255, 255, 255, 255]);
      expect(store.getRecord(1), isNull);
      file('farmSsave_1').writeAsBytesSync([1, 0, 0, 0, 7, 0]);
      expect(store.getRecord(1), isNull);
    });
    test('retention keeps newest saved files with original CRC markers', () {
      final limited = RecordStore.open(
        directory,
        'limited',
        createIfMissing: true,
        backupLimit: 2,
      );
      limited.addRecord([0]);
      for (var n = 1; n < 5; n++) {
        limited.setRecord(1, [n]);
      }
      expect(file('limited_1_saved3').existsSync(), isFalse);
      expect(file('limited_1_saved4').existsSync(), isTrue);
      expect(file('limited_1_saved5').existsSync(), isTrue);
      expect(file('limited_1_CRC1').existsSync(), isTrue);
      expect(limited.getRecord(1), [4]);
    });
    test('revision 10000 saturates and promotion preserves readable data', () {
      store.addRecord([1]);
      file('farmSsave_1_saved1')
          .renameSync(file('farmSsave_1_saved10000').path);
      file('farmSsave_1_CRC1').copySync(file('farmSsave_1_CRC10000').path);
      store.setRecord(1, [9]);
      expect(file('farmSsave_1_saved10000').readAsBytesSync().last, 9);
      expect(store.getRecord(1), [9]);
    });
    test(
      'reopen reads consecutive record ids and deletion keeps unrelated files',
      () {
        store.addRecord([1]);
        store.addRecord([2]);
        store.getRecord(1);
        store.getRecord(2);
        file('other').writeAsStringSync('preserve');
        final reopened = RecordStore.open(directory, 'farm/save');
        expect(reopened.recordCount, 2);
        expect(reopened.getRecord(2), [2]);
        reopened.deleteStore();
        expect(file('other').readAsStringSync(), 'preserve');
        expect(file('farmSsave').existsSync(), isFalse);
      },
    );
    test('rejects missing stores and unsafe names', () {
      expect(
        () => RecordStore.open(directory, 'missing'),
        throwsA(isA<FileSystemException>()),
      );
      for (final name in ['', '..', r'..\escape', 'a:b']) {
        expect(
          () => RecordStore.open(directory, name, createIfMissing: true),
          throwsArgumentError,
        );
      }
    });
  });
}
