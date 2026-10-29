import 'dart:typed_data';

import 'byte_reader.dart';

/// Indexed resource archive, including the numbered .1, .2, ... shards.
/// Entry IDs are the original global IDs, not per-shard IDs.
final class GameAssetPack {
  GameAssetPack._(this.entries);
  final List<Uint8List> entries;
  int get length => entries.length;
  Uint8List operator [](int index) => entries[index];

  factory GameAssetPack.parse(
    Uint8List first, {
    Map<int, Uint8List> shards = const {},
  }) {
    final r = AssetReader(first);
    final count = r.u16();
    final shardCount = r.u16();
    if (shardCount == 0 || shardCount > count + 1) {
      r.fail('Invalid shard count');
    }
    final starts = List.generate(shardCount, (_) => r.u16());
    if (starts.first != 0) r.fail('First shard must start at entry zero');
    for (var i = 1; i < starts.length; i++) {
      if (starts[i] < starts[i - 1] || starts[i] > count) {
        r.fail('Invalid shard entry ranges');
      }
    }
    starts.add(count);
    if (shards.length != shardCount - 1 ||
        shards.keys.any((i) => i < 1 || i >= shardCount)) {
      r.fail('Expected exactly ${shardCount - 1} numbered shards');
    }
    final entries = <Uint8List>[];
    for (var shard = 0; shard < shardCount; shard++) {
      final data = shard == 0 ? first : shards[shard];
      if (data == null) r.fail('Missing shard $shard');
      final sr = shard == 0 ? r : AssetReader(data);
      final n = starts[shard + 1] - starts[shard];
      sr.require((n + 1) * 4);
      final offsets = List.generate(n + 1, (_) => sr.u32());
      if (offsets.first != sr.offset || offsets.last != data.length) {
        sr.fail('Pack index boundaries differ from payload');
      }
      for (var i = 0; i < n; i++) {
        if (offsets[i] > offsets[i + 1] || offsets[i + 1] > data.length) {
          sr.fail('Unordered pack offsets');
        }
        entries.add(
          Uint8List.fromList(data.sublist(offsets[i], offsets[i + 1])),
        );
      }
    }
    return GameAssetPack._(List.unmodifiable(entries));
  }
}
