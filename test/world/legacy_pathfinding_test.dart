import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/world/legacy_pathfinding.dart';

void main() {
  final cases = jsonDecode(
    File('test/world/fixtures/pathfinding.json').readAsStringSync(),
  ) as List<dynamic>;
  for (final c in cases) {
    test('Java pathfinding oracle: ${c['name']}', () {
      final engine = LegacyPathfinding(
        width: c['width'],
        height: c['height'],
        collision: Uint8List.fromList((c['map'] as List).cast<int>()),
        straightCost: c['straight'],
        diagonalCost: c['diagonal'],
        turnCost: c['turn'],
        directionCount: c['dirs'],
        blockedMask: c['mask'],
        softWalls: c['soft'],
      );
      final path = engine.find(
        startX: c['start'][0],
        startY: c['start'][1],
        initialDirection: c['direction'],
        targetX: c['target'][0],
        targetY: c['target'][1],
        regionX: c['region'][0],
        regionY: c['region'][1],
        regionWidth: c['region'][2],
        regionHeight: c['region'][3],
        directionMaskMode: c['directional'],
      );
      expect(path.reverseIndices, c['reverse']);
      expect(path.forwardIndices, (c['reverse'] as List).reversed.toList());
      expect(path.found, (c['reverse'] as List).isNotEmpty);
    });
  }
  test('map changes remain visible and node capacity is enforced', () {
    final map = Uint8List(9);
    final engine = LegacyPathfinding(
      width: 3,
      height: 3,
      collision: map,
      straightCost: 10,
      diagonalCost: 14,
      turnCost: 0,
      directionCount: 4,
    );
    LegacyPath route() => engine.find(
      startX: 0,
      startY: 0,
      initialDirection: 0,
      targetX: 2,
      targetY: 2,
    );
    expect(route().found, true);
    map[1] = 1;
    map[3] = 1;
    expect(route().found, false);
    final small = LegacyPathfinding(
      width: 3,
      height: 3,
      collision: map,
      straightCost: 10,
      diagonalCost: 14,
      turnCost: 0,
      directionCount: 4,
      capacity: 4,
    );
    expect(
      () => small.find(
        startX: 0,
        startY: 0,
        initialDirection: 0,
        targetX: 2,
        targetY: 2,
      ),
      throwsArgumentError,
    );
  });
}
