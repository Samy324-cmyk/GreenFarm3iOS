import 'dart:typed_data';

import '../../engine/storage/binary.dart';
import 'class_table.dart';

/// Byte-consumption behavior of cGame.Lv. This reader describes placements;
/// it does not implement cGame.Aq, s1.s1 or the actors' runtime behavior.
class MapPlacementStream {
  MapPlacementStream._(this.commands);

  factory MapPlacementStream.fromEntry(Uint8List entry) {
    final input = BinaryReader(gameDataPayload(entry));
    final commands = <MapPlacementCommand>[];
    while (input.remaining > 0) {
      final offset = input.position;
      final opcode = input.readInt8();
      if (opcode == 50) {
        commands.add(
          MapObjectPlacement(
            offset: offset,
            objectId: input.readInt16(),
            x: input.readInt16(),
            y: input.readInt16(),
            unusedByte: input.readInt8(),
            objectType: input.readInt8(),
            variant: input.readInt8(),
            unusedShort: input.readInt16(),
          ),
        );
      } else if (opcode == 54) {
        commands.add(
          MapExpansionGate(
            offset: offset,
            unusedByte: input.readInt8(),
            expansionMask: input.readInt16(),
            requiredLevel: input.readInt8(),
          ),
        );
      } else {
        // The recovered Lv loop consumes one byte for every unrecognized
        // marker, including the exporter byte after each placement.
        commands.add(IgnoredMapByte(offset: offset, value: opcode));
      }
    }
    return MapPlacementStream._(List.unmodifiable(commands));
  }

  final List<MapPlacementCommand> commands;

  Iterable<MapObjectPlacement> get placements =>
      commands.whereType<MapObjectPlacement>();
  Iterable<MapExpansionGate> get expansionGates =>
      commands.whereType<MapExpansionGate>();

  /// Lv stops reading at the first gate above the selected neighbor's level.
  /// Successful gates overwrite all 13 expansion booleans before later actors.
  Iterable<MapPlacementCommand> commandsUntilLevel(int neighborLevel) sync* {
    for (final command in commands) {
      if (command is MapExpansionGate &&
          command.requiredLevel > neighborLevel) {
        return;
      }
      yield command;
    }
  }
}

sealed class MapPlacementCommand {
  const MapPlacementCommand({required this.offset});

  /// Offset in the uncompressed payload, excluding the pack type byte.
  final int offset;
}

class MapObjectPlacement extends MapPlacementCommand {
  const MapObjectPlacement({
    required super.offset,
    required this.objectId,
    required this.x,
    required this.y,
    required this.unusedByte,
    required this.objectType,
    required this.variant,
    required this.unusedShort,
  });
  final int objectId;
  final int x;
  final int y;
  final int unusedByte;
  final int objectType;
  final int variant;
  final int unusedShort;
}

class MapExpansionGate extends MapPlacementCommand {
  const MapExpansionGate({
    required super.offset,
    required this.unusedByte,
    required this.expansionMask,
    required this.requiredLevel,
  });
  final int unusedByte;
  final int expansionMask;
  final int requiredLevel;
  List<bool> get expansions => List<bool>.unmodifiable(
    List.generate(13, (i) => expansionMask >> i & 1 != 0),
  );
}

class IgnoredMapByte extends MapPlacementCommand {
  const IgnoredMapByte({required super.offset, required this.value});

  /// Original signed byte. It has no branch in cGame.Lv.
  final int value;
}
