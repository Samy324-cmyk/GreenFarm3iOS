# Green Farm 3 en Java ME

Port de la campaña sin conexión de Green Farm 3 4.4.4 para Java ME táctil en español de México. Una partida nueva empieza en la carta de la herencia y se guarda localmente con RMS. El juego requiere MIDP 2.0 y CLDC 1.1.

La campaña incluye las 304 misiones del diario, 50 niveles y las nueve habitaciones de la mansión. Puedes cultivar, criar animales, cocinar las 104 recetas, pescar y visitar las granjas de los vecinos de la historia. Las compras con dinero real y las visitas a cuentas de otros jugadores necesitan los servicios de Gameloft en la edición Android.

## Compilar

Desde la rama `j2me`, abre la ejecución de **Compilar y probar Green Farm 3 en Java ME** en GitHub Actions. El artefacto `GreenFarm3-MX` seguido del número de ejecución contiene el juego y su descriptor de instalación. Para compilar en tu equipo, el script utiliza los dos archivos del repositorio y verifica sus huellas SHA-256 antes de leerlos.

| Archivo | SHA-256 |
| --- | --- |
| `inputs/green_farm_3_480x800_192541.jar` | `e4e8634fe47986211da9646c04b88b0bb9cc6917bada5c10fca567909a779617` |
| `assets/provenance/original.apk` | `3081eded66775b99790b35e2980057a9ac559afa08bba6daa94bc21fa325092d` |

En Ubuntu, instala un JDK 21, Python 3.10 o posterior, FFmpeg y libsndfile. Desde la raíz del proyecto ejecuta en Bash

```sh
midp_api=$(python3 tests/emulator/bench.py --prepare)
python3 build.py \
  --jar inputs/green_farm_3_480x800_192541.jar \
  --apk assets/provenance/original.apk \
  --api "$midp_api" --decoder libsndfile.so.1 --out build
```

La preparación descarga FreeJ2ME-Plus 1.53 una vez y comprueba su huella. La compilación genera `build/GreenFarm3-MX.jar`, el descriptor de instalación `build/GreenFarm3-MX.jad` y `build/build.json` con la procedencia de los recursos. Conserva el JAR y el JAD en la misma carpeta para instalarlos en un equipo compatible.

En una pantalla horizontal de 1280 × 720 o 1920 × 1080, el juego amplía la imagen original de 800 × 480 y centra la granja. Las pantallas verticales conservan la orientación del JAR táctil. El área visible y las coordenadas táctiles usan la misma escala.

Para alternar entre 50 % y 100 % en FreeJ2ME, abre **Pausa → Opciones → Alejar** o **Acercar** y regresa a la granja. En equipos con eventos multitáctiles Nokia, junta o separa dos dedos sobre la granja para elegir también los aumentos intermedios.

El MIDlet funciona sin cuenta y sin acceso a Internet. El banco de sonido se divide en recursos independientes por grabación, sin cambiar su PCM, para evitar la expansión de un único bloque de más de 32 MB en Manic y las interferencias con la carga de sprites. Conserva la resolución de los sprites del APK y las 82 grabaciones originales a 32 kHz. El icono de instalación es el original de 512 × 512.

El instalador identifica la edición como 4.4.4. El nombre de la aplicación, el proveedor de la edición táctil y el formato anterior de RecordStore se conservan para poder reabrir las partidas del JAR 1.0.6.

## Jugar en Manic EMU en iPhone

Importa `GreenFarm3-MX.jar` en la biblioteca de Manic EMU. El JAR declara la pantalla táctil de 480 × 800 que usa la edición original. Si ya guardaste una granja, conserva una copia de la partida y usa el mismo nombre de archivo al actualizar. El núcleo J2meJS incluye el nombre del JAR en la ruta de los datos guardados.

El plano de la mansión se abre al aceptar el encargo de Walt en el diario y tocar el edificio. Al tocar una habitación en el plano se abre su presupuesto. La prueba de regresión visita las seis pestañas del mercado y el granero antes de volver a la granja y abrir ese plano. Compara las ilustraciones visibles en cada paso.

La última pestaña del mercado ofrece dos o tres tarjetas diarias, renovadas a medianoche local con contador. Los paquetes de billetes usan el atlas 38 del panel 8 de Android. El signo + de billetes abre la tienda de recursos offline; sus seis precios en monedas son una adaptación local, no una cotización del antiguo servicio de compras. No usa dinero real.

La tienda nativa de monedas (pantalla 34) conserva su composición original; un selector lateral de billetes abre la tienda offline. Las compras usan zonas táctiles del propio diseño. La granja guarda cada 15 segundos mientras está activa y al salir mediante la rutina RMS existente.\n\nLa rueda de la suerte (edificio 1019) usa el panel 45, el marco y los cinco sectores del APK 4.4.4. El giro local cuesta 3 billetes del juego; los premios offline de monedas y billetes sustituyen el servicio de anuncios. Se guardan el pago y el premio en una sola escritura de la partida.

La interpolación se limita al desplazamiento real de la cámara en la granja. Los menús y las escenas estacionarias conservan el cuadro nativo, evitando emparejar imágenes repetidas como si fueran el mismo objeto.

El workflow prueba el mismo JAR con FreeJ2ME-Plus, el núcleo de Manic EMU 2.0.2 y un simulador de iPhone con WKWebView. El artefacto de Manic incluye el audio detectado y la medición del arrastre en 480 × 800 y 240 × 320. El artefacto de iPhone incluye capturas del juego y los intervalos medidos durante tres arrastres en el simulador. Las cifras dependen del dispositivo y del emulador.

## Probar en el emulador

Con Java 21 en el PATH, inicia la prueba desde una carpeta de salida nueva

```sh
python3 tests/emulator/bench.py build/GreenFarm3-MX.jar prueba-cosecha
```

La prueba inicia una partida, toca los controles de la carta y la cosecha, captura la pantalla y mide los cuadros presentados y los cambios visibles. El juego conserva los intervalos de la simulación original. El dibujo interpola desplazamientos entre actualizaciones con una meta de 60 cuadros por segundo. En `prueba-cosecha/report.json` aparecen ambas mediciones y la huella del JAR probado.

Para recorrer el tutorial sin conexión desde una partida vacía, ejecuta

```sh
python3 tests/introduction/check.py build/GreenFarm3-MX.jar "$midp_api" prueba-tutorial
```

El recorrido llega a la carta, cosecha el trigo, compra el becerro y vende tomates. Después cierra el juego y vuelve a abrir la partida en otro proceso. La prueba compara la mansión y la cerca de la primera cosecha con dos recortes dibujados por el motor Android del APK. Lee la captura ya guardada para que la medición no provoque un repintado. [Procedencia de los recortes](tests/introduction/art-reference/origin.json)

La prueba del diario recorre las 304 misiones usando los eventos de progreso del motor y comprueba que al cobrar la última se active el desenlace. Los recorridos por pantalla cubren el tutorial y actividades específicas. Puedes consultar los dos resultados por separado en `campaign-check/run.log` y `tutorial-completo/report.json`, dentro del artefacto de pruebas.

El workflow **Compilar y probar Green Farm 3 en Java ME** se inicia al subir cambios a la rama `j2me`. También admite ejecución manual en GitHub Actions. Busca los originales en `inputs/` o en la raíz y admite el APK que ya contiene el repositorio en `assets/provenance/original.apk`. Guarda las capturas, los registros de las pruebas y los archivos de instalación. Las pruebas de niveles avanzados utilizan partidas de control y especifican cuándo preparan un requisito de misión.

La prueba de carga compara 332,000 píxeles del logotipo, el fondo y el pie «© 2018 Gameloft.» con una captura del APK 4.4.4. La referencia se tomó antes del formulario de edad, en un emulador Android 7.0 de 800 × 480 sin conexión. La comparación admite una tolerancia de color por la pantalla de 16 bits de Android. La referencia muestra «Loading» en inglés. Para verificar «Cargando», la prueba comprueba los glifos de la fuente original del APK y exige que sus 2,296 píxeles opacos coincidan en color y posición en FreeJ2ME. [Captura de referencia](tests/loading/android-4.4.4.png)

Los recorridos de mascotas y apicultura cubren la adopción, el adiestramiento, el zorro de Harold, las colmenas y la venta de caramelo de miel. [Pruebas de las siete misiones](tests/neighbor/README.md)

En el mostrador, el emulador entrega un pedido y comprueba que un cliente descartado regresa en 30 minutos o por cuatro billetes. En el estanque, compra la Parcela tranquila, toca las ondas con las tres cañas y comprueba la entrega de premios y el tiempo de espera de la caña gratuita al reabrir la partida.

### Secuencias guiadas originales

Las filas 297–303 del catálogo Android 4.4.4 definen las misiones 9297, 9299, 9301 y 9302–9305. La primera adopción/defensa (9297) y la caseta/juguete (9299) son capítulos distintos. En `classes.dex`, `cGame.ea()` inicia las fases 1026 y 1060 al activar las misiones 9299 y 9304; `cGame.Yq()` dirige las fases 1026–1038 y confirma el objetivo 2992/44 al terminar el juego con el perro. `cGame.fH()` abre el mercado tras el diálogo 1035. `cGame.hk()` comprueba el nivel 15, la finalización de la misión 9299 y la ausencia de un encuentro vecinal activo antes de introducir la apicultura. El port mantiene estas condiciones de arranque en la granja, sin alterar objetivos ni recompensas del catálogo. Las pruebas de sprites comparan todos los cuadros de las ocho hojas de mascota; las pruebas de interacción deben confirmar la ejecución real en los emuladores.
