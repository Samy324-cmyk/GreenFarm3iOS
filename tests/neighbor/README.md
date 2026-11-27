# Misiones de mascotas y apicultura

Las pruebas usan FreeJ2ME-Plus a 480 × 800, sin red. Cada ejecución necesita una carpeta de salida nueva. Los programas guardan las capturas y el archivo `run.log`. Los tres primeros argumentos son el JAR del juego, el JAR del emulador y la carpeta de salida.

| Misión | Recorrido | Prueba |
| --- | --- | --- |
| 9297 | Adopción del cachorro, molino, alimentación y defensa de la granja | [check.py con --adoption](check.py) |
| 9299 | Caseta, bono diario, pelota de regalo, reinicio y juego con el perro | [check.py con --lesson](../pets/check.py) |
| 9301 | Buzón, granja de Harold, zorro y cobro de la recompensa | [check.py](check.py) y [acciones táctiles](encounter.txt) |
| 9302 | Compra de la primera colmena por 1,000 monedas, colocación y cobro de 640 monedas y 90 XP | [bee_journal.py con --route market](bee_journal.py) |
| 9303 | Compra del extractor por 25,000 monedas, colocación y cobro de 680 monedas y 90 XP | [bee_journal.py con --route market](bee_journal.py) |
| 9304 | Recolección de panales, uso del ahumador y extracción de un frasco | [honey.py](honey.py) |
| 9305 | Preparación de caramelo de miel, cobro de la recompensa y venta de una pieza en el puesto | [bee_journal.py con --route candy](bee_journal.py) |

Los escenarios restauran [partidas de control](../emulator/fixtures) y preparan el nivel, el inventario o los requisitos anteriores que corresponden a cada misión. La prueba de 9305 espera los cinco minutos de la receta. El objetivo del diario se acredita al recoger el caramelo. La venta posterior comprueba el precio de 114 monedas.

La ruta `bee_journal.py --route limits` prueba los topes de colmenas para los niveles 15, 16 y 48. Compra, coloca y recupera la versión premium del almacén con toques. Comprueba los precios de 1,000 y 2,500 monedas, ambos avisos de capacidad y la devolución de la unidad cuando falla su colocación. Al final, el logro 3999 permanece pendiente con tres colmenas y 14 árboles frutales. El árbol número 15 lo completa.

## El buzón de los vecinos

Con `visits.py juego.jar emulador.jar carpeta --mailbox`, el emulador pide un huevo a Harold, le entrega mermelada de manzana y regala un pastel de manzana a Edwina. Después recoge la respuesta de Harold y cobra las 350 monedas y los 40 XP de «Un vecindario amistoso» (9047). La partida de prueba prepara los dos regalos y la amistad de Edwina a un punto del primer corazón. Los toques realizan las entregas, consumen ambos artículos y suben la amistad de 299 a 336. La prueba fija la semilla del sorteo de Harold para reproducir una respuesta favorable. [Recorrido del buzón](MailboxProbe.java)
