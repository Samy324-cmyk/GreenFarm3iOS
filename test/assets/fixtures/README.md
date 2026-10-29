# Original asset fixtures

The `.bin` files are unmodified entries or complete resource packs from the supplied
`com.gameloft.android.ANMP.GloftGF2F_4.4.4.apk`.

APK SHA-256: `3081eded66775b99790b35e2980057a9ac559afa08bba6daa94bc21fa325092d`.

`9_187.bin` means global entry 187 in resource pack `assets/800x480/9`, including
that pack's numbered shards. IDs were not renumbered during extraction.
`pack_EN.bin`, `pack_ES.bin`, `pack_LATAM.bin` and `pack_12.bin` are complete packs.

`sprites.json` records reference metadata. Each `.rgba` file is the decoded
straight RGBA pixel buffer for the corresponding original atlas/palette, compared
byte for byte in Flutter tests. The selection covers all seven image encodings
found in the APK. The eighth supported encoding (packed one-bit pixels) is tested
with a fixed bit-order vector because it does not occur in this APK.

`11_028.bin` preserves an unusual original asset: its animation table contains
frame ID 255 despite having only six frame records. Tests preserve that value;
the parser does not invent rendering behavior for it.

`corpus_manifest.json` covers every original sprite and contains CRC-32 values
calculated from the RGBA buffers of 516 independently exported reference PNGs.
Run from the project root:

```powershell
flutter test test/assets
dart run tool/verify_asset_corpus.dart PATH_TO_RECOVERY/recovered/original/assets/800x480
```

The corpus verifier checks all 352 sprite records, all 516 atlas/palette results
(161,077,760 RGBA bytes), and all 14 language packs (62,720 strings). Exact small
RGBA fixtures complement the full-corpus checksums. These checks establish asset
decoding parity; they do not establish gameplay or renderer parity.
