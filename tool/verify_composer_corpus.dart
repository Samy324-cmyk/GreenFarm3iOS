import 'dart:convert';
import 'dart:io';

import 'package:green_farm_port/engine/assets/sprite.dart';
import 'package:green_farm_port/engine/render/frame_composer.dart';

/// Checks every frame under all eight neutral-effect transforms. This checks
/// index validity and painter order; it is not a rendered-pixel parity claim.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/verify_composer_corpus.dart INPUT_DIR REPORT.json',
    );
    exitCode = 64;
    return;
  }
  final manifest = jsonDecode(
    File('test/assets/fixtures/corpus_manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final files = (manifest['sprites'] as List<dynamic>).map((entry) {
    final id = (entry['id'] as String).replaceFirst(':', '_');
    return File('${args[0]}/$id.bin');
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('No exported sprite binaries found');
  const composer = FrameComposer();
  var frameCount = 0;
  var commands = 0;
  var checks = 0;
  final invalidAnimationReferences = <Map<String, Object>>[];
  final moduleTypes = <String, int>{};
  final moduleFlags = <String, int>{};
  for (final file in files) {
    final sprite = GameSprite.parse(file.readAsBytesSync());
    final instance = SpriteInstance(sprite);
    frameCount += sprite.frames.length;
    for (final module in sprite.modules) {
      moduleTypes.update('${module.type}', (n) => n + 1, ifAbsent: () => 1);
    }
    for (final entry in sprite.frameModules) {
      moduleFlags.update('${entry.flags}', (n) => n + 1, ifAbsent: () => 1);
    }
    for (var frameIndex = 0; frameIndex < sprite.frames.length; frameIndex++) {
      final frame = sprite.frames[frameIndex];
      for (var flags = 0; flags < 8; flags++) {
        final result = composer.composeFrame(
          instance,
          frameIndex,
          flags: flags,
        );
        if (result.length != frame.count) {
          throw StateError('Painter count mismatch: ${file.path}:$frameIndex');
        }
        for (var n = 0; n < result.length; n++) {
          if (result[n].moduleIndex !=
              sprite.frameModules[frame.start + n].index) {
            throw StateError(
              'Painter order mismatch: ${file.path}:$frameIndex:$n',
            );
          }
        }
        commands += result.length;
        checks++;
      }
    }
    for (var n = 0; n < sprite.animationFrames.length; n++) {
      final frame = sprite.animationFrames[n].frame;
      if (frame >= sprite.frames.length) {
        invalidAnimationReferences.add({
          'sprite': file.uri.pathSegments.last,
          'animationFrame': n,
          'frame': frame,
        });
      }
    }
  }
  final report = {
    'source': 'Original APK exported ASprite binaries',
    'apkSha256': manifest['apk_sha256'],
    'mode': 'APK default configuration, neutral effects, all eight transforms',
    'spriteCount': files.length,
    'frameCount': frameCount,
    'frameTransformChecks': checks,
    'moduleCommands': commands,
    'moduleTypes': moduleTypes,
    'frameModuleFlags': moduleFlags,
    'invalidAnimationReferences': invalidAnimationReferences,
    'limitations': [
      'No original-runtime pixel differential is claimed.',
      'GLLib effects, clipping and vector rasterization belong to the renderer hook.',
      'Out-of-range animation frame references are preserved, never treated as invented sentinels.',
    ],
  };
  File(args[1]).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(
    '$checks frame/transform checks passed across ${files.length} sprites; ${invalidAnimationReferences.length} out-of-range animation references preserved.',
  );
}
