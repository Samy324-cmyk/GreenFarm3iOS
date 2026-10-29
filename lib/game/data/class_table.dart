import 'dart:typed_data';

import '../../engine/assets/asset_pack.dart';
import '../../engine/storage/binary.dart';

/// The Pack_ReadData type byte precedes all supplied non-sprite entries.
Uint8List gameDataPayload(Uint8List entry) {
  if (entry.isEmpty || entry.first != 2) {
    throw const FormatException('Expected uncompressed data entry (type 2)');
  }
  return Uint8List.sublistView(entry, 1);
}

/// Port of c.c.a.a.a.w.g.b/c: signed numeric class table from pack 13.
/// Column widths are encoded in the asset, rather than inferred from values.
class GameClassTable {
  GameClassTable._(this.id, this.columnWidths, this.rows);

  factory GameClassTable.fromEntry(int id, Uint8List entry) =>
      GameClassTable.fromPayload(id, gameDataPayload(entry));

  factory GameClassTable.fromPayload(int id, Uint8List payload) {
    final input = BinaryReader(payload);
    final rowCount = input.readInt32();
    final columnCount = input.readInt32();
    if (rowCount < 0 || columnCount <= 0 || columnCount > input.remaining) {
      throw FormatException('Invalid class table $id dimensions');
    }
    final widths = input.readBytes(columnCount);
    if (widths.any((width) => width != 1 && width != 2 && width != 4)) {
      throw FormatException('Unsupported class table $id field width');
    }
    final rowBytes = widths.fold<int>(0, (sum, width) => sum + width);
    if (rowCount * rowBytes != input.remaining) {
      throw FormatException(
        'Class table $id byte length does not match dimensions',
      );
    }
    final rows = List<List<int>>.generate(rowCount, (_) {
      return List<int>.unmodifiable(
        widths.map(
          (width) => switch (width) {
            1 => input.readInt8(),
            2 => input.readInt16(),
            4 => input.readInt32(),
            _ => throw StateError('Validated field width changed'),
          },
        ),
      );
    }, growable: false);
    return GameClassTable._(
      id,
      List<int>.unmodifiable(widths),
      List<List<int>>.unmodifiable(rows),
    );
  }

  final int id;
  final List<int> columnWidths;
  final List<List<int>> rows;
  int get rowCount => rows.length;
  int get columnCount => columnWidths.length;
  List<int> operator [](int index) => rows[index];
}

class GameClassTables {
  GameClassTables._(this.tables);

  factory GameClassTables.fromPack(GameAssetPack pack) =>
      GameClassTables.fromEntries(pack.entries);

  factory GameClassTables.fromEntries(List<Uint8List> entries) {
    if (entries.length != 34) {
      throw FormatException(
        'Green Farm 3 expects 34 class tables; received ${entries.length}',
      );
    }
    return GameClassTables._(
      List<GameClassTable>.unmodifiable(
        List.generate(34, (id) => GameClassTable.fromEntry(id, entries[id])),
      ),
    );
  }

  final List<GameClassTable> tables;
  GameClassTable operator [](int id) => tables[id];
}
