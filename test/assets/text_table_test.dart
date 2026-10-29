import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:green_farm_port/engine/assets/assets.dart';

void main() {
  for (final language in ['EN', 'ES', 'LATAM']) {
    test('original $language text pack preserves all4480 string IDs', () {
      final pack = GameAssetPack.parse(
        File('test/assets/fixtures/pack_$language.bin').readAsBytesSync(),
      );
      final catalog = GameTextCatalog.fromPack(pack);
      expect(catalog.groups.length, 13);
      expect(catalog.length, 4480);
      expect(catalog['8:5'], language == 'EN' ? 'Wheat' : 'Trigo');
      expect(catalog['0:121'], language == 'EN' ? 'Market' : 'Mercado');
      expect(catalog['0:129'], language == 'EN' ? 'Seeds' : 'Semillas');
      expect(() => catalog['99:0'], throwsRangeError);
      expect(() => catalog['8:99999'], throwsRangeError);
      expect(
        () => GameTextCatalog.fromGroups([
          catalog.groups[0]!,
          catalog.groups[0]!,
        ]),
        throwsFormatException,
      );
    });
  }
  test('text table rejects invalid UTF-8 and out-of-order boundaries', () {
    expect(
      () => GameTextGroup.parse(
        Uint8List.fromList([2, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0xff]),
      ),
      throwsFormatException,
    );
    expect(
      () => GameTextGroup.parse(
        Uint8List.fromList([2, 0, 2, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 65]),
      ),
      throwsFormatException,
    );
    expect(
      () => GameTextGroup.parse(Uint8List.fromList([2, 0, 255, 255, 255, 255])),
      throwsFormatException,
    );
  });
}
