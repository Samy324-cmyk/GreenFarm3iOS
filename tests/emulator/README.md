# Medición de movimiento

Desde la raíz del proyecto, ejecuta la prueba de paneo con el JAR compilado y una carpeta nueva.

```sh
python3 tests/emulator/bench.py build/GreenFarm3-MX.jar prueba-paneo \
  --rms-from tests/emulator/fixtures/level3 \
  --script tests/emulator/verify-pan.txt --audio
```

FreeJ2ME-Plus abre una granja de nivel 3 a 480 × 800, con su límite de cuadros desactivado. La opción `--audio` activa los reproductores MMAPI y dirige el PCM a un mezclador en memoria. Para medir con el dispositivo de audio desactivado, repite el comando en otra carpeta y omite esa opción.

El escenario `static` mantiene fija la cámara durante 3.5 segundos. En `pan`, la prueba arrastra un punto de terreno libre en ocho tramos durante 6.8 segundos. Lee la posición de la cámara dentro del MIDlet y compara la imagen completa cada vez que el emulador presenta un cuadro. Las plantas y los animales pueden seguir animados mientras la cámara está fija.

En `report.json`, `presentedFps` cuenta las presentaciones, `changedFps` cuenta las imágenes distintas consecutivas y `simulationTicks` cuenta las actualizaciones originales. `p50Ms` y `p95Ms` son la mediana y el percentil 95 del intervalo entre cuadros. Los archivos `frames-static.csv` y `frames-pan.csv` contienen los tiempos individuales y las huellas de la pantalla.

Antes de iniciar la partida, la prueba también compara 204 posiciones intermedias de un terreno que cruza los bordes horizontal y vertical de la caché. Comprueba todos los píxeles del terreno y la posición fija de un control superpuesto.

## Horizonte de la granja

La prueba carga una granja de nivel 3 y cambia el zoom desde **Pausa → Opciones → Alejar**. La opción cambia a **Acercar** para volver al tamaño anterior. Después captura el suelo y la partida con sus controles.

```sh
python3 tests/catalog/check_market.py build/GreenFarm3-MX.jar "$MIDP_API" horizonte --probe horizon --rms-from tests/emulator/fixtures/level3
python3 tests/sprites/verify_horizon.py "$SOURCE_APK" horizonte
```

El mapa Android de 58 × 58 deja transparentes las primeras 18 filas. En las filas 16 y 17 el JAR táctil colocaba 116 casillas de pasto. Los tres planos de fondo de Android ocupan ese espacio hasta la coordenada vertical 648. Las nubes permanecen fijas en el eje horizontal, las montañas siguen un dieciseisavo del avance horizontal de la cámara y los árboles se desplazan con la granja.

El comparador obtiene los colores, las piezas y sus posiciones del APK 4.4.4. Verifica los 384 000 píxeles de trece vistas por zoom, incluidos cinco movimientos consecutivos con actualización incremental. Para el zoom al 50 % usa el muestreo del motor táctil. Las seis imágenes cuyo nombre empieza con `farm-` muestran la granja con actores y controles. La prueba compara el terreno con una reconstrucción de la composición Android. Una captura del APK ejecutado en las mismas coordenadas permitiría comparar también el resultado de su controlador OpenGL.


## Objetos estáticos durante el paneo

En el paso 8 del tutorial, la cámara se mueve al terreno de siembra. La prueba detiene los cambios de simulación durante dos repintados y compara los 384 000 píxeles de la capa de terreno, flores, árboles, silo y granero. Un segundo recorrido repite la comparación en veinte posiciones, desde el horizonte y la unión con el pasto hasta las cuatro esquinas de la zona visible. Ante una diferencia se guardan dos PNG con el mismo encuadre.

```sh
python3 tests/catalog/check_market.py build/GreenFarm3-MX.jar "$MIDP_API" bordes --probe scenery --rms-from tests/emulator/fixtures/level3
```

## Comparación de escenas en la granja

| Escena | Referencia y comprobación | Diferencia que conserva el port |
| --- | --- | --- |
| Granja de nivel 3 después del tutorial | El medidor de experiencia, el diario, la pausa y los indicadores económicos usan las poses del APK. En FreeJ2ME se comprobó que el espacio junto a esos controles queda libre para tocar la granja. | En equipos con eventos multitáctiles Nokia, el MIDlet admite la pinza entre 50 % y 100 %. En equipos con un solo puntero, las opciones de pausa alternan entre los dos extremos. |
| Tarjeta al subir de nivel | El panel usa los controles de recompensa del APK, incluida la zona visible de 450 × 300. Al volver del molino recupera las hojas de la cabeza y el cuerpo del personaje. La prueba del tutorial toma la foto después de que aparezcan el título y los desbloqueos. | El texto se dibuja con la fuente del juego en español de México. |
| Primera cosecha, siembra y desplazamiento | La prueba juega la primera cosecha con toques y verifica en el LCD cuatro máscaras de colores del granero, la mansión, la cerca y un árbol, derivadas del dibujo original de Android. También comprueba los repintados de la siembra y el horizonte durante un arrastre. | Al 50 % se aplica el muestreo del motor J2ME. |

Estas comprobaciones contrastan los recursos, la geometría y la lógica del APK con una ejecución del JAR en FreeJ2ME-Plus. La comparación directa con un teléfono Android, en exactamente las mismas posiciones y estados, queda pendiente.

La prueba de zoom usa el menú táctil en FreeJ2ME. También entrega al Canvas dos secuencias de contactos identificados con la propiedad Nokia para comprobar la pinza. En un emulador compatible, el descriptor `Nokia-UI-Enhancement: EnableMultiPointTouchEvents` habilita esos eventos y la opción adicional de pausa queda oculta. [Entrega de eventos en J2ME Loader](https://github.com/nikita36078/J2ME-Loader/blob/master/app/src/main/java/javax/microedition/lcdui/Canvas.java) · [Identificador del contacto](https://github.com/nikita36078/J2ME-Loader/blob/master/app/src/main/java/javax/microedition/shell/MidletSystem.java)

```sh
python3 tests/catalog/check_market.py build/GreenFarm3-MX.jar "$MIDP_API" movimiento --probe motion --rms-from tests/emulator/fixtures/level3
```

Para medir la cadencia al 75 %, usa un perfil nuevo. El informe separa 3.5 segundos con la cámara quieta y ocho paneos continuos de 850 ms.

```sh
python3 tests/catalog/check_market.py build/GreenFarm3-MX.jar "$MIDP_API" paneo-75 --probe zoom --pan --rms-from tests/emulator/fixtures/level3
```

La referencia `tests/catalog/zoom-ground.rgb` guarda muestras de 3,212 píxeles por escala. Se capturaron en un AVD Android 7.0 mediante el decodificador del APK y su renderizador OpenGL ES (`t.f0`, `t.h0`, `t.l0` y `t.W`), con origen de cámara (1400, 864). El orden es 100, 67 y 75 %. Cada plano contiene tríos RGB leídos de izquierda a derecha desde (2, 4) a intervalos de 11 píxeles. En el control al 100 % coinciden los 3,212 colores. Al 75 % todos difieren por un nivel RGB o menos. La coordenada vertical 578.88 del 67 % se redondea a 579 en el búfer MIDP. En la prueba, 11 muestras superaron tres niveles RGB y la mayor diferencia fue 24. El oráculo cubre el suelo; las pruebas de cosecha y HUD miden el comportamiento del juego compuesto.

## Pausa y opciones

El recorrido abre la pausa con un toque desde una partida de nivel 3. Comprueba los cuatro enlaces del menú sin conexión, el texto completo de los créditos de 4.4.4, los dos interruptores de sonido, los 21 temas de ayuda del perfil local y el regreso a la misma granja. Las capturas se guardan en horizontal a 800 × 480.

```sh
python3 tests/catalog/check_market.py build/GreenFarm3-MX.jar "$MIDP_API" pausa --probe pause --rms-from tests/emulator/fixtures/level3
```

El selector muestra el paquete latinoamericano instalado, adaptado al español de México. Los enlaces presentan el aviso de conexión con la fuente del sistema. La pantalla de contactos también lo usa en el port. Android abre el navegador para ese enlace. La tipografía del aviso depende del emulador o del dispositivo. El perfil local conserva los ajustes de música y efectos del MIDlet.
