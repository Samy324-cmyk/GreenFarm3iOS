import 'dart:convert';
import 'dart:typed_data';

import 'asset_pack.dart';
import 'byte_reader.dart';

final class GameTextGroup {
  GameTextGroup._(this.id, this.values);
  final int id;
  final List<String> values;

  factory GameTextGroup.parse(Uint8List bytes) {
    final r = AssetReader(bytes);
    if (r.u8() != 2) r.fail('Unsupported text version');
    final id = r.u8();
    final count = r.u32();
    r.require(count * 4);
    final ends = List.generate(count, (_) => r.u32());
    final start = r.offset;
    if ((ends.isEmpty ? 0 : ends.last) != r.remaining) {
      r.fail('Text payload length differs from index');
    }
    final values = <String>[];
    var previous = 0;
    for (final end in ends) {
      if (end < previous || start + end > bytes.length) {
        r.fail('Invalid string boundary');
      }
      values.add(
        utf8.decode(
          bytes.sublist(start + previous, start + end),
          allowMalformed: false,
        ),
      );
      previous = end;
    }
    return GameTextGroup._(id, List.unmodifiable(values));
  }
}

final class GameTextCatalog {
  GameTextCatalog.fromGroups(Iterable<GameTextGroup> input) {
    for (final group in input) {
      if (_groups.containsKey(group.id)) {
        throw FormatException('Duplicate text group ${group.id}');
      }
      _groups[group.id] = group;
    }
  }
  factory GameTextCatalog.fromPack(GameAssetPack pack) =>
      GameTextCatalog.fromGroups(pack.entries.map(GameTextGroup.parse));
  final Map<int, GameTextGroup> _groups = {};
  Map<int, GameTextGroup> get groups => Map.unmodifiable(_groups);
  int get length =>
      _groups.values.fold(0, (count, group) => count + group.values.length);
  String get(int group, int index) {
    final value = _groups[group];
    if (value == null) throw RangeError('Unknown text group $group');
    return value.values[index];
  }

  String operator [](String key) {
    final ids = key.split(':');
    if (ids.length != 2) throw FormatException('Expected group:index', key);
    return get(int.parse(ids[0]), int.parse(ids[1]));
  }
}
