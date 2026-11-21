# Audio de Green Farm 3

El archivo `assets/800x480/8` del APK 4.4.4 contiene 82 grabaciones a 32 kHz. Hay 62 archivos Vorbis mono y 20 archivos AAC estéreo. El compilador conserva la frecuencia y los canales de cada grabación y entrega WAV PCM de 16 bits al reproductor MMAPI. Algunos efectos ocupan dos entradas idénticas porque el juego alterna entre dos reproductores cuando se repite un sonido. La sección `media.apkAudio` de `build.json` indica la grabación de origen, la entrada del JAR, la duración en muestras y las sumas SHA-256.

En la granja, el canal MIDP 1 reproduce la música y el canal 2 repite el ambiente de campo del APK (grabación 24). Los efectos de controles, cosecha, ganado y pedidos se alternan entre cinco canales, del 3 al 7, como en `cGame.oz` de Android. El canal 0 queda disponible para las llamadas directas del motor táctil. La música incluye el tema principal y nueve piezas que el juego intercala durante la partida.

| Evento | Índice de audio en el APK |
| --- | --- |
| Sonidos de los animales de corral | 14–20 |
| Tema al aparecer un depredador y tema de la visita guiada a Harold | 62, 63 |
| Ladridos, encuentros con depredadores y pelea | 64, 65, 68–71 |
| Subir de nivel al perro | 11 |
| Comer, jugar y descansar | 64, 67, 72, 75, 78 |
| Tecla del collar | 73 |
| Colmena y acciones del extractor | 79–81 |

`verify_bank.py` comprueba el banco final contra los 82 archivos del APK. Usa FFmpeg para obtener una segunda lectura del audio y compara los canales, la duración, los valores PCM compartidos y las copias de reproducción. En Vorbis, la duración del JAR procede de la última posición de muestra del archivo original.

Los 20 MP4 HE-AAC guardan la ventana de reproducción en `iTunSMPB` con un reloj de 16 kHz. Su salida estéreo es de 32 kHz. El compilador decodifica todos los paquetes, verifica la duración total contra `mdhd` y recorta el retraso inicial y el relleno final según la escala del contenedor. Antes de este ajuste, FFmpeg 6.1.1 dejaba 66 ms de retraso inicial en los WAV. El ladrido 64 duraba 446 ms. Su duración de reproducción es 369.69 ms. El oráculo parte de los mismos paquetes exportados a ADTS y verifica el primer y el último fotograma de los WAV, además de las muestras intermedias.

`check_audio.py --pets` ejecuta el MIDlet en FreeJ2ME-Plus y captura la salida de Java Sound en memoria. Reconoce por sus muestras las grabaciones que arrancan al jugar el comienzo de la campaña. Luego llama al reproductor del juego para probar la mezcla simultánea, los efectos del perro, el collar, la pelea, el extractor y las repeticiones. La presencia de los 82 audios en el banco se comprueba por separado de que cada escena los dispare durante una partida completa.

`tests/manic/audio.py` inicia una partida en el núcleo J2meJS de Manic EMU 2.0.2. Toca la carta y los cultivos, identifica las grabaciones por SHA-256 y mide la señal que llega a la salida Web Audio. También comprueba dos cosechas separadas por menos de un segundo y una segunda vuelta del ambiente. Si el proveedor mantiene un WAV corto en estado `STARTED` después de terminar, el MIDlet lo detiene según la duración del PCM y vuelve a iniciar el ambiente al finalizar cada vuelta. La prueba usa un navegador con Web Audio y no requiere salida por los altavoces.
