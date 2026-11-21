# Audio de Green Farm 3

El archivo `assets/800x480/8` del APK 4.4.4 contiene 82 grabaciones a 32 kHz. Hay 62 archivos Vorbis mono y 20 archivos AAC estéreo. El compilador conserva la frecuencia y los canales de cada grabación y entrega WAV PCM de 16 bits al reproductor MMAPI. Algunos efectos ocupan dos entradas idénticas porque el juego alterna entre dos reproductores cuando se repite un sonido. La sección `media.apkAudio` de `build.json` indica la grabación de origen, la entrada del JAR, la duración en muestras y las sumas SHA-256.

En la granja, el canal MIDP 1 reproduce la música y el canal 2 repite el ambiente de campo del APK (grabación 24). El canal 0 recibe los efectos de controles, cosecha, ganado y pedidos. La música incluye el tema principal y nueve piezas que el juego intercala durante la partida. El volumen y las opciones de música y efectos se aplican dentro del MIDlet.

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

`check_audio.py --pets` ejecuta el MIDlet en FreeJ2ME-Plus y captura la salida de Java Sound en memoria. Reconoce por sus muestras las grabaciones que arrancan al jugar el comienzo de la campaña. Luego llama al reproductor del juego para probar la mezcla simultánea, los efectos del perro, el collar, la pelea, el extractor y las repeticiones. La presencia de los 82 audios en el banco se comprueba por separado de que cada escena los dispare durante una partida completa.
