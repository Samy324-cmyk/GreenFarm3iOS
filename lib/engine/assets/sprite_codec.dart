import 'dart:typed_data';

import 'byte_reader.dart';
import 'sprite.dart';

final class SpriteIndices {
  const SpriteIndices(this.indices, this.alpha);
  final Uint8List indices;
  final Uint8List? alpha;
}

final class SpritePixels {
  const SpritePixels(this.width, this.height, this.rgba);
  final int width, height;

  /// Straight (not premultiplied) RGBA bytes, in row-major order.
  final Uint8List rgba;
}

/// Exact palette/index algorithms in the original ASprite.j decoder.
abstract final class SpriteCodec {
  static const supportedEncodings = {
    0x0200,
    0x0400,
    0x1600,
    0x5602,
    0x64f0,
    0x27f1,
    0x56f2,
    0xa562,
  };

  static SpriteIndices decodeIndices(
    Uint8List data, {
    required int encoding,
    required int pixelCount,
    required int colorCount,
  }) {
    if (pixelCount < 0 ||
        pixelCount > 16777216 ||
        colorCount < 1 ||
        colorCount > 256) {
      throw const FormatException('Invalid image limits');
    }
    if (!supportedEncodings.contains(encoding)) {
      throw FormatException(
        'Unsupported sprite encoding 0x${encoding.toRadixString(16)}',
      );
    }
    final r = AssetReader(data);
    final out = Uint8List(pixelCount);
    Uint8List? alpha;
    var written = 0;
    void append(int value, int count) {
      if (value >= colorCount || count < 0 || count > pixelCount - written) {
        r.fail('Image run or palette index outside bounds');
      }
      out.fillRange(written, written + count, value);
      written += count;
    }

    if (encoding == 0x5602) {
      while (written < pixelCount) {
        append(r.u8(), 1);
      }
    } else if (encoding == 0xa562) {
      alpha = Uint8List(pixelCount);
      while (written < pixelCount) {
        alpha[written] = r.u8();
        append(r.u8(), 1);
      }
    } else if (encoding == 0x0200 || encoding == 0x0400 || encoding == 0x1600) {
      final bits = encoding == 0x0200
          ? 1
          : encoding == 0x0400
          ? 2
          : 4;
      final mask = (1 << bits) - 1;
      while (written < pixelCount) {
        final value = r.u8();
        for (
          var shift = 8 - bits;
          shift >= 0 && written < pixelCount;
          shift -= bits
        ) {
          append((value >> shift) & mask, 1);
        }
      }
    } else if (encoding == 0x64f0) {
      final bits = (colorCount - 1).bitLength;
      final mask = (1 << bits) - 1;
      while (written < pixelCount) {
        final value = r.u8();
        append(value & mask, (value >> bits) + 1);
      }
    } else if (encoding == 0x27f1) {
      while (written < pixelCount) {
        final value = r.u8();
        if (value > 127) {
          append(r.u8(), value - 128);
        } else {
          append(value, 1);
        }
      }
    } else if (encoding == 0x56f2) {
      while (written < pixelCount) {
        final value = r.u8();
        if (value >= 128) {
          // Original decoder uses a do/while, so 0x80 still copies one pixel.
          final count = value == 128 ? 1 : value - 128;
          if (count > pixelCount - written) r.fail('Literal run outside image');
          for (var i = 0; i < count; i++) {
            append(r.u8(), 1);
          }
        } else {
          append(r.u8(), value == 0 ? 1 : value);
        }
      }
    }
    r.end();
    return SpriteIndices(out, alpha);
  }

  /// Returns original straight ARGB colors, with RGB magenta treated as clear.
  static List<int> decodePalette(
    SpriteAtlas atlas,
    int pixelFormat,
    int palette,
  ) {
    if (palette < 0 || palette >= atlas.paletteCount) {
      throw RangeError.range(palette, 0, atlas.paletteCount - 1, 'palette');
    }
    final bytes = switch (pixelFormat) {
      0x8888 => 4,
      0x8808 => 3,
      0x4444 || 0x5515 => 2,
      _ => throw FormatException('Unknown palette format $pixelFormat'),
    };
    final start = palette * atlas.colorCount * bytes;
    final r = AssetReader(
      Uint8List.sublistView(
        atlas.paletteData,
        start,
        start + atlas.colorCount * bytes,
      ),
    );
    final colors = <int>[];
    for (var i = 0; i < atlas.colorCount; i++) {
      int color;
      if (pixelFormat == 0x8888) {
        color = r.u32();
      } else if (pixelFormat == 0x8808) {
        final blue = r.u8(), green = r.u8(), red = r.u8();
        color = (red << 16) | (green << 8) | blue;
        if (color != 0xff00ff) color |= 0xff000000;
      } else if (pixelFormat == 0x4444) {
        final value = r.u16();
        final a = ((value >> 12) & 15) * 17, red = ((value >> 8) & 15) * 17;
        final green = ((value >> 4) & 15) * 17, blue = (value & 15) * 17;
        color = (a << 24) | (red << 16) | (green << 8) | blue;
      } else {
        final value = r.u16();
        color =
            (value & 0x8000 != 0 ? 0xff000000 : 0) |
            ((value & 0x7c00) << 9) |
            ((value & 0x3e0) << 6) |
            ((value & 31) << 3);
        if (color == 16253176) color = 0xff00ff;
      }
      colors.add(color);
    }
    r.end();
    return List.unmodifiable(colors);
  }

  static SpritePixels decodeAtlas(
    GameSprite sprite,
    int image, {
    int palette = 0,
  }) {
    final atlas = sprite.atlases[image];
    final indices = decodeIndices(
      atlas.encodedPixels,
      encoding: sprite.encoding,
      pixelCount: atlas.width * atlas.height,
      colorCount: atlas.colorCount,
    );
    final colors = decodePalette(atlas, sprite.pixelFormat, palette);
    final rgba = Uint8List(indices.indices.length * 4);
    for (var i = 0; i < indices.indices.length; i++) {
      final color = colors[indices.indices[i]];
      final p = i * 4;
      rgba[p] = (color >> 16) & 255;
      rgba[p + 1] = (color >> 8) & 255;
      rgba[p + 2] = color & 255;
      rgba[p + 3] = indices.alpha?[i] ?? ((color >> 24) & 255);
    }
    return SpritePixels(atlas.width, atlas.height, rgba);
  }
}
