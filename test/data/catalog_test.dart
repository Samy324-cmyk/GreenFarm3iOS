import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/game/data/data.dart';
import 'package:green_farm_port/engine/storage/binary.dart';
import 'package:green_farm_port/engine/assets/assets.dart';

Uint8List entry(int pack, int id) =>
    File('test/data/fixtures/${pack}_${id.toString().padLeft(3, '0')}.bin')
        .readAsBytesSync();

void main() {
  final oracle = (jsonDecode(
    File('test/data/fixtures/tables_oracle.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final tables = GameClassTables.fromEntries(
    List.generate(34, (i) => entry(13, i)),
  );

  for (final language in ['EN', 'ES', 'LATAM']) {
    test('original $language text IDs localize the original catalog', () {
      final texts = GameTextCatalog.fromPack(
        GameAssetPack.parse(
          File('test/assets/fixtures/pack_$language.bin').readAsBytesSync(),
        ),
      );
      final catalog = GameCatalog(tables);
      expect(
        catalog.cropById(3004).localizedName(texts),
        language == 'EN' ? 'Wheat' : 'Trigo',
      );
      if (language == 'EN') {
        expect(catalog.products.first.localizedName(texts), 'Water');
        expect(catalog.recipes.first.localizedName(texts), 'Porridge');
        expect(catalog.feedRecipes.first.localizedName(texts), 'Cow Feed');
      }
    });
  }

  group('All original pack13 class tables', () {
    for (var id = 0; id < 34; id++) {
      test('table $id matches independent Python signed-field oracle', () {
        final table = tables[id];
        expect(table.id, id);
        expect(table.columnWidths, oracle[id]['widths']);
        expect(table.rows, oracle[id]['rows']);
        expect(() => table.rows.add([]), throwsUnsupportedError);
        expect(() => table.rows.first[0] = 123, throwsUnsupportedError);
      });
    }
    test('source catalog counts and crop/recipe columns are preserved', () {
      final catalog = GameCatalog(tables);
      expect(catalog.animals.length, 76);
      expect(catalog.products.length, 141);
      expect(catalog.crops.length, 24);
      expect(catalog.buildings.length, 30);
      expect(catalog.decorations.length, 69);
      expect(catalog.missions.length, 304);
      expect(catalog.recipes.length, 104);
      expect(catalog.feedRecipes.length, 7);
      final wheat = catalog.cropById(3004);
      expect(wheat.nameTextId, tables[2][4][2]);
      expect(wheat.unlockLevel, tables[2][4][19]);
      expect(wheat.baseGrowthTimer, tables[2][4][22]);
      expect(wheat.generatedProductIndex, tables[2][4][24]);
      expect(catalog.recipes.first.outputProductIndex, 27);
      expect(catalog.recipes.first.durationSeconds, 60);
      expect(catalog.products.first.unlockLevel, isNull);
      expect(catalog.missions.first.id, 9000);
      expect(() => catalog.cropById(999999), throwsRangeError);
    });
    test(
      'rejects truncation, trailing data, unsupported width and wrong type',
      () {
        final original = entry(13, 2);
        expect(
          () => GameClassTable.fromEntry(
            2,
            Uint8List.sublistView(original, 0, original.length - 1),
          ),
          throwsFormatException,
        );
        expect(
          () =>
              GameClassTable.fromEntry(2, Uint8List.fromList([...original, 0])),
          throwsFormatException,
        );
        final badWidth = Uint8List.fromList(original)..[9] = 3;
        expect(
          () => GameClassTable.fromEntry(2, badWidth),
          throwsFormatException,
        );
        final badType = Uint8List.fromList(original)..[0] = 0;
        expect(
          () => GameClassTable.fromEntry(2, badType),
          throwsFormatException,
        );
        expect(
          () => GameClassTables.fromEntries([original]),
          throwsFormatException,
        );
      },
    );
  });

  group('Original map placement streams', () {
    final expectedCounts = [
      [301, 271, 296, 513, 678, 816, 618, 465, 577, 322, 188, 461, 4, 3, 5],
      [163, 269, 160, 452, 643, 808, 604, 431, 562, 272, 172, 426, 4, 3, 5],
    ];
    final entryIds = [...List.generate(12, (i) => i + 3), 16, 18, 20];
    for (final pack in [14, 15]) {
      for (var i = 0; i < entryIds.length; i++) {
        final id = entryIds[i];
        test(
          'pack $pack entry $id preserves every byte, including ignored markers',
          () {
            final bytes = entry(pack, id);
            final stream = MapPlacementStream.fromEntry(bytes);
            expect(stream.placements.length, expectedCounts[pack - 14][i]);
            final writer = BinaryWriter()..writeByte(2);
            for (final command in stream.commands) {
              expect(command.offset, writer.length - 1);
              switch (command) {
                case MapObjectPlacement():
                  writer.writeByte(50);
                  writer.writeInt16(command.objectId);
                  writer.writeInt16(command.x);
                  writer.writeInt16(command.y);
                  writer.writeByte(command.unusedByte);
                  writer.writeByte(command.objectType);
                  writer.writeByte(command.variant);
                  writer.writeInt16(command.unusedShort);
                case MapExpansionGate():
                  writer.writeByte(54);
                  writer.writeByte(command.unusedByte);
                  writer.writeInt16(command.expansionMask);
                  writer.writeByte(command.requiredLevel);
                case IgnoredMapByte():
                  writer.writeByte(command.value);
              }
            }
            expect(writer.toBytes(), bytes);
          },
        );
      }
    }
    test(
      'known coordinates and signed sentinel survive original placement fields',
      () {
        final base = MapPlacementStream.fromEntry(entry(14, 3))
            .placements
            .first;
        expect(
          [
            base.objectId,
            base.x,
            base.y,
            base.unusedByte,
            base.objectType,
            base.variant,
            base.unusedShort,
          ],
          [12, 1700, 0, 5, 13, -1, 110],
        );
        final neighbor = MapPlacementStream.fromEntry(entry(14, 6));
        expect(neighbor.placements.first.y, -72);
        expect(neighbor.expansionGates.first.requiredLevel, 20);
        expect(neighbor.commandsUntilLevel(19), isEmpty);
        expect(neighbor.commandsUntilLevel(20).first, isA<MapExpansionGate>());
        expect(neighbor.expansionGates.first.expansions, [
          true,
          true,
          true,
          true,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
          false,
        ]);
        expect(
          () => MapPlacementStream.fromEntry(Uint8List.fromList([2, 50, 1, 2])),
          throwsFormatException,
        );
      },
    );
  });

  group('Non-sprite resource evidence', () {
    test(
      'all 131 original resources have an explicit format classification',
      () {
        final index = jsonDecode(
          File('test/data/fixtures/index.json').readAsStringSync(),
        ) as List;
        final counts = <GameResourceKind, int>{};
        for (final row in index) {
          final ids = (row['id'] as String).split(':').map(int.parse).toList();
          final kind = resourceKind(ids[0], ids[1]);
          expect(kind, isNot(GameResourceKind.unknown));
          counts.update(kind, (count) => count + 1, ifAbsent: () => 1);
        }
        expect(counts[GameResourceKind.fontCharacterMap], 5);
        expect(counts[GameResourceKind.classTable], 34);
        expect(counts[GameResourceKind.guiLayout], 50);
        expect(counts[GameResourceKind.mapCommands], 36);
        expect(counts[GameResourceKind.tileIndices], 2);
        expect(counts[GameResourceKind.tileTransforms], 2);
        expect(counts[GameResourceKind.tileDimensions], 2);
      },
    );
    test('all five real font arrays are decoded with strict EOF handling', () {
      final ids = [(2, 7), (3, 5), (4, 7), (5, 3), (6, 3)];
      final expectedLengths = [761, 639, 703, 2631, 3237];
      for (var i = 0; i < ids.length; i++) {
        final bytes = entry(ids[i].$1, ids[i].$2);
        final values = decodeFontCharacterMap(bytes);
        expect(values.length, expectedLengths[i]);
        expect(
          () => decodeFontCharacterMap(
            Uint8List.sublistView(bytes, 0, bytes.length - 1),
          ),
          throwsFormatException,
        );
      }
    });
    test(
      'both tile layers preserve actual 58 by 58 byte grids and descriptor',
      () {
        for (final pack in [14, 15]) {
          final layer = OriginalTileLayer.fromEntries(
            entry(pack, 0),
            entry(pack, 1),
            entry(pack, 2),
          );
          expect(layer.width, 58);
          expect(layer.height, 58);
          expect(layer.tileIds, entry(pack, 0).sublist(1));
          expect(layer.transforms, entry(pack, 1).sublist(1));
          expect(layer.descriptorTail, [0, 0]);
          expect(layer.tileAt(0, 0), 255);
          expect(() => layer.tileAt(58, 0), throwsRangeError);
        }
      },
    );
    test(
      'unported GUI/map instructions retain raw bytes and throw explicitly',
      () {
        for (final resource in [(10, 0), (14, 15), (15, 19)]) {
          final bytes = entry(resource.$1, resource.$2);
          expect(
            () => decodeKnownGameResource(resource.$1, resource.$2, bytes),
            throwsA(
              isA<UnsupportedGameResource>().having(
                (e) => e.rawEntry,
                'unchanged source',
                bytes,
              ),
            ),
          );
        }
        expect(resourceKind(999, 0), GameResourceKind.unknown);
      },
    );
  });
}
