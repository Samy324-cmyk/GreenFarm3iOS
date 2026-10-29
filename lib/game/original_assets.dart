import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../engine/dalvik/android_context.dart';

/// Synchronously serves the original Java resource APIs after Flutter has
/// loaded the bundle. No Android archive code is executed by this loader.
class OriginalGameAssets {
  OriginalGameAssets._(this.resourceTable, this._original, this._raw);
  final AndroidResourceTable resourceTable;
  final Map<String, Uint8List> _original, _raw;

  static Future<OriginalGameAssets> load({AssetBundle? bundle}) async {
    final source = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(source);
    final original = <String, Uint8List>{};
    for (final key in manifest.listAssets()) {
      if (!key.startsWith('assets/original/')) continue;
      final data = await source.load(key);
      original[key.substring('assets/original/'.length)] = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final raw = <String, Uint8List>{};
    final rawManifest = jsonDecode(
      await source.loadString('assets/platform/raw/manifest.json'),
    ) as Map;
    for (final entry in rawManifest['resources'] as List) {
      final data = await source.load(entry['asset'] as String);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (sha256.convert(bytes).toString() != entry['sha256']) {
        throw StateError(
          'Original raw resource failed integrity: ${entry['resource']}',
        );
      }
      raw[entry['resource'] as String] = bytes;
    }
    return OriginalGameAssets._(
      AndroidResourceTable.fromJson(
        jsonDecode(
          await source.loadString('assets/platform/android_resources.json'),
        ) as Map<String, dynamic>,
      ),
      original,
      raw,
    );
  }

  List<int>? resource(String path) =>
      _original[path.startsWith('/') ? path.substring(1) : path];
  List<int>? rawResource(String path) => _raw[path];
  List<String> listAssets(String directory) {
    final path = directory.startsWith('/') ? directory.substring(1) : directory;
    final prefix = path.isEmpty ? '' : '$path/';
    return _original.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length).split('/').first)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }
}
