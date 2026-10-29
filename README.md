# Green Farm 3 — port del original a Flutter / iOS

Objetivo: conservar el juego suministrado en su versión Android 4.4.4 y producir un IPA sin firma mediante GitHub Actions, para firmarlo después.

**Estado: port en desarrollo. Todavía no se ha verificado un juego completo y jugable en iOS.** Se conservan los recursos originales y las instrucciones de las clases seleccionadas del APK. La integración de plataforma, los flujos completos del juego y la fidelidad visual requieren verificación. Las pruebas de módulos no equivalen a una comprobación 1:1 del juego completo.

## Código original reproducible

`game_source/program.json.gz` contiene exactamente los bytes del IR extraído de `classes.dex` y `classes2.dex`: 511 clases seleccionadas del juego y sus entradas Android, 6.973 métodos declarados y 6.893 cuerpos de método. También conserva el catálogo de tipos disponibles del APK. `game_source/provenance.json` registra las sumas SHA-256 del APK, del IR y del gzip, sus tamaños y recuentos. Incluye las clases seleccionadas por `tool/dex_ir.py`; no pretende contener los cuerpos de todas las clases Android y de SDK publicitarios del APK.

`tool/prepare_original.py` verifica primero los archivos y recuentos, después utiliza `tool/dex_to_dart.py` para generar métodos Dart estáticos en `lib/generated/`. Ese directorio se regenera y está excluido de Git. Flutter compila el Dart generado; el APK no se ejecuta durante la preparación ni se instala dentro de la app iOS.

Con Flutter **3.47.8** y Python 3:

```sh
python3 tool/prepare_original.py
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --reporter expanded
```

La generación puede comprobarse sin reescribir Dart con `python3 tool/prepare_original.py --verify-only`. El compilador de fuente y los puentes de compatibilidad se versionan junto al IR para que cada commit identifique los insumos de la compilación.

## GitHub Actions

**Verify original-game source port** se ejecuta con los cambios de código. Comprueba la preparación, genera las fuentes, analiza Dart y ejecuta las pruebas. Los errores del analizador fallan la ejecución; los avisos de lint del código generado permanecen visibles. Este workflow no produce un IPA.

**Compile iOS native host (probe only)** compila el host Swift/C y AppDelegate en macOS con `tool/native_compile_probe.dart`. Esta entrada inicializa Flutter y no inicia el juego. Es una comprobación de compilación; no empaqueta ni publica un IPA.

**Build unsigned iOS IPA** se ejecuta manualmente desde Actions. Requiere una entrada real `lib/main.dart`, el proyecto iOS, las fuentes y las pruebas. Si todavía falta la integración, falla con una explicación y no crea un IPA vacío. Cuando la compilación completa funcione, el artifact contendrá `GreenFarm-Flutter-unsigned.ipa` y su suma SHA-256. El IPA necesita una firma y un perfil válidos antes de instalarse en un dispositivo Apple.

## Recursos y procedencia

Los recursos suministrados se conservan en `assets/original/`. Los avisos y licencias de componentes de terceros están en `third_party/`; esos avisos no conceden una licencia sobre los recursos originales del juego.

APK de origen, SHA-256: `3081eded66775b99790b35e2980057a9ac559afa08bba6daa94bc21fa325092d`.

## Snapshot para sincronizar el repositorio

`tool/repository_manifest.py` crea una copia verificable separada del proyecto activo, excluye cachés y compilaciones y registra SHA-256, SHA de blob Git, tamaños y modos. No conecta con GitHub ni publica cambios.

```sh
python3 tool/repository_manifest.py snapshot --source . --destination ../source-checkpoint
python3 tool/repository_manifest.py verify --manifest ../source-checkpoint/manifest.json
python3 tool/repository_manifest.py plan --manifest ../source-checkpoint/manifest.json --output ../source-checkpoint/upload-plan.json
```

Para reutilizar blobs existentes, `plan` acepta `--remote-tree` con la respuesta JSON completa del árbol remoto. La sincronización debe usar la copia revisada, después de probarla y verificar de nuevo su manifiesto.
