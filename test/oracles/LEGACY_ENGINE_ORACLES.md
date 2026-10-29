# Original engine reference vectors

`LegacyPathfindingOracle.java` reconstructs the original `GLLibPathFinding`
methods from the DEX fallback instruction listing. Normal JADX output has broken
control flow in its search and insertion methods. The reconstruction keeps the
instruction branches and Java `byte`, `short` and `int` behavior. It does not run
the APK or native Android libraries.

`LegacySpritePlayerOracle.java` isolates the original instance animation state
from `GLLibPlayer`. Its input duration/frame tables in
`test/render/fixtures/animation_units.txt` are taken from original sprite `9:187`.
The APK is the same SHA-256 recorded in the asset fixture README.

The generated vectors are checked in so Flutter tests do not require a local
JVM. Regenerate with Java 11 or later, from the project root:

```powershell
java test/oracles/LegacyPathfindingOracle.java | Set-Content -Encoding utf8 test/world/fixtures/pathfinding.json
java test/oracles/LegacySpritePlayerOracle.java | Set-Content -Encoding utf8 test/render/fixtures/player.json
flutter test test/world/legacy_pathfinding_test.dart test/render/legacy_sprite_player_test.dart
```

On macOS/Linux, use ordinary `>` redirection instead of `Set-Content`.

The 89 pathfinding vectors cover fixed and seeded maps, equal-score ordering,
four/eight directions, turn penalties, corner collisions, subregions, negative
region clipping, directional bitmasks, soft walls, unreachable targets and
signed-short cost overflow. Original quirks remain explicit in the Dart source:
vertical movement is classified as direction 1 after popping a node, and
directional-map access uses local coordinates even with a nonzero subregion.

The nine animation traces cover finite/infinite loops, custom total duration,
same-animation calls, modulo frame selection, transform mapping, one-step
updates, integer overflow, zero-unit duration, stopping and completion. The
original update consumes previous elapsed time before adding this call's delta.

These are differential checks against a reconstructed Java reference, not a
claim that the entire original game has been executed or reproduced.
