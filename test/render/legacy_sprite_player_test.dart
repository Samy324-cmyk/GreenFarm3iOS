import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/assets/assets.dart';
import 'package:green_farm_port/engine/render/legacy_sprite_player.dart';

void main() {
  final sprite = GameSprite.parse(
    File('test/assets/fixtures/9_187.bin').readAsBytesSync(),
  );
  final cases = jsonDecode(
    File('test/render/fixtures/player.json').readAsStringSync(),
  ) as List<dynamic>;
  for (final c in cases) {
    test('Java sprite player oracle: ${c['name']}', () {
      final player = LegacySpritePlayer(
        sprite: sprite,
        singleStepPerUpdate: c['single'],
      );
      for (final step in c['steps'] as List) {
        final p = (step['op'] as String).split(':');
        switch (p[0]) {
          case 'set':
            player.setAnimation(
              int.parse(p[1]),
              loops: int.parse(p[2]),
              totalDuration: int.parse(p[3]),
            );
          case 'update':
            player.update(int.parse(p[1]));
          case 'frame':
            player.setFrame(int.parse(p[1]));
          case 'transform':
            player.setTransform(int.parse(p[1]));
        }
        expect(
          [
            player.animation,
            player.animationFrame,
            player.elapsed,
            player.unitDuration,
            player.loopsRemaining,
            player.completed ? 1 : 0,
            player.currentFrame,
            player.transform,
          ],
          step['state'],
          reason: step['op'],
        );
      }
    });
  }
  test('invalid calls reject negative delta and zero loops; render completion follows original flag', () {
    final player = LegacySpritePlayer(sprite: sprite);
    expect(() => player.update(-1), throwsRangeError);
    expect(() => player.setAnimation(0, loops: 0), throwsArgumentError);
    player.setAnimation(0, loops: 1);
    expect(player.shouldPaint, true);
    player.update(100000);
    player.update(0);
    expect(player.isOver, true);
    expect(player.shouldPaint, false);
    final retained =
        LegacySpritePlayer(sprite: sprite, paintAfterCompletion: true)
          ..setAnimation(0, loops: 1)
          ..update(100000)
          ..update(0);
    expect(retained.shouldPaint, true);
  });
}
