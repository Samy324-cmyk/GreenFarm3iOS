"""Rebuild the touchscreen MIDlet's resources from the supplied JAR and APK."""
from __future__ import annotations

from collections import Counter, defaultdict
from difflib import SequenceMatcher
from hashlib import sha256
from itertools import accumulate
from pathlib import Path
import ctypes
import ctypes.util
import io
import os
import re
import shutil
import struct
import subprocess
import tempfile
import wave
import zipfile


def unpack(data):
    count, parts, flags = struct.unpack_from("<3H", data)
    if (parts, flags) != (1, 0):
        raise ValueError("Expected a single-shard Gameloft pack")
    offsets = struct.unpack_from(f"<{count + 1}I", data, 6)
    if offsets[0] != 6 + 4 * len(offsets) or offsets[-1] != len(data) or tuple(sorted(offsets)) != offsets:
        raise ValueError("Invalid pack offsets")
    return [data[a:b] for a, b in zip(offsets, offsets[1:])]


def pack(entries):
    size = 6 + 4 * (len(entries) + 1)
    offsets = list(accumulate(map(len, entries), initial=size))
    return struct.pack("<3H", len(entries), 1, 0) + struct.pack(f"<{len(offsets)}I", *offsets) + b"".join(entries)


def read_groups(data):
    result = {}
    for block in unpack(data):
        version, group, count = struct.unpack_from("<BBI", block)
        ends = struct.unpack_from(f"<{count}I", block, 6)
        text = block[6 + 4 * count:]
        if version != 2 or group in result or tuple(sorted(ends)) != ends or ends[-1] != len(text):
            raise ValueError("Invalid indexed UTF-8 group")
        result[group] = [text[start:end].decode("utf-8") for start, end in zip((0, *ends), ends)]
    return result


def write_groups(groups):
    blocks = []
    for group, strings in groups.items():
        entries = [s.encode("utf-8") for s in strings]
        ends = list(accumulate(map(len, entries)))
        blocks.append(struct.pack("<BBI", 2, group, len(strings)) +
                      struct.pack(f"<{len(ends)}I", *ends) + b"".join(entries))
    return pack(blocks)


# Text specific to the MIDP edition. The other entries come from the source
# APK's LATAM pack. Retain SMS price variables and platform-specific rules.
J2ME_MX = {
    (0, 104): "Notificación de Green Farm 3",
    (0, 507): "Recibiste %d billetes de la granja del equipo de Atención al cliente de Gameloft. Ya se sumaron a tu saldo. ¡Gracias por jugar Green Farm 3!",
    (0, 508): "Recibiste %d monedas del equipo de Atención al cliente de Gameloft. Ya se sumaron a tu saldo. ¡Gracias por jugar Green Farm 3!",
    (0, 624): "Carga la avioneta fertilizante realizando acciones en la granja. ¡Úsala para fertilizar tus cultivos y árboles y duplicar su producción!",
    (0, 779): "La compra falló. La configuración de seguridad impidió la conexión a Internet. Permite que el juego se conecte y vuelve a intentarlo.",
    (0, 782): "La compra falló. No se pudo enviar el SMS para completarla. Revisa la configuración de tu teléfono y vuelve a intentarlo.",
    (0, 783): "IAP_INVALID_REQUEST",
    (0, 790): "La compra falló. La configuración de seguridad impidió enviar el SMS. Permite que el juego envíe mensajes y vuelve a intentarlo.",
    (0, 799): "¿Quieres comprar este artículo? Precio: %price ",
    (0, 839): "¡DESCUBRE MÁS JUEGOS!",
    (0, 840): "¿QUIERES ACTIVAR EL SONIDO?",
    (0, 841): '%price más el costo de un SMS de tarifa normal se cargarán a tu cuenta de teléfono o se descontarán de tu saldo.\nAl tocar "Comprar ahora", confirmas que tienes más de 16 años y que cuentas con el permiso de quien paga la cuenta.',
    (0, 842): "Comprar ahora",
    (0, 845): "Más tarde",
    (0, 846): "¿Quieres comprar %amount billetes por %price (más IVA)? Atención al cliente: 021-3918614.",
    (0, 847): "Comprar",
    (0, 848): "Cancelar",
    (0, 849): "Comprar",
    (0, 851): "CONFIRMAR COMPRA",
    (0, 852): "¡Parece que te faltan %d billetes de la granja!",
    (0, 853): "+ el costo de 2 SMS",
    (0, 854): "Sal del juego para obtener el código",
    (0, 855): "Para jugar, gira tu teléfono a la posición horizontal.",
    (0, 856): "¿Confirmas la compra? Costo: %price más el precio de %sms SMS.",
    (1, 100): "Realiza acciones para cargar la avioneta fertilizante. ¡Toca su icono para abonar la granja!",
    (1, 104): "¡Muy bien! La avioneta fertilizará los cultivos, los árboles y los terrenos. ¡Todo lo que fertilices producirá el doble!",
    (4, 212): "¡Realiza acciones para cargar la avioneta fertilizante!",
    (10, 20): "Compras dentro del juego",
    (10, 21): 'Puedes comprar billetes de la granja en cualquier momento. Si compras un paquete, se te cobrará su precio. Para abrir el menú, toca el signo "+" verde junto al contador de billetes. También puedes usar billetes para comprar monedas. ¡Así será más fácil cuidar de tu granja!',
    (10, 25): "¡La avioneta fertilizante de Walt recompensa tu esfuerzo! Cada vez que haces algo en la granja, se llena un poco el medidor de fertilizante junto al icono de pausa, arriba a la derecha. Cuando se llene, llama a Walt. ¡Abonará tus campos para que cada terreno produzca el doble! Puedes usar la avioneta una y otra vez.",
    (10, 32): "La mansión",
    (11, 3): "© 2013 Gameloft. Todos los derechos reservados. Gameloft y el logotipo de Gameloft son marcas registradas de Gameloft en Estados Unidos y otros países.",
    (11, 5): "Información y atención al cliente:",
    (11, 202): "<Pruebas de calidad>",
    (11, 283): "<Equipo de adaptación>",
}


def help_texts(latam):
    help_rows = latam[10]
    # The mobile editions share this help chapter, but individual mechanics
    # differ. Keep the MIDP rules where the wording diverges.
    return {
        (10, 1): help_rows[1].replace("\nLos Billetes de la Granja pueden adquirirse comprándolos con dinero real. ", ""),
        (10, 3): help_rows[3].replace("para conseguir más monedas!", "para conseguir más monedas o billetes de la granja!"),
        (10, 15): help_rows[15].rsplit("\n\n", 1)[0],
        (10, 17): help_rows[17].rsplit("\n\n", 1)[0] + "\n\nCada parcela tiene un precio y ciertos requisitos. Puedes usar billetes de la granja para saltarte algunos. Si se trata de un objeto o un animal, los billetes te permiten omitir el requisito, pero no compran ese objeto o animal. ¡Buena suerte!",
        (10, 33): help_rows[5].replace(" ¡Mientras más estancias renueves, mayores serán las fiestas que organices!", "").replace("acudir a tus amigos para que te ayuden o usar billetes", "usar billetes"),
    }


def localize(jar, apk):
    original = read_groups(jar.read("EN"))
    english = read_groups(apk.read("assets/800x480/EN"))
    latam = read_groups(apk.read("assets/800x480/LATAM"))
    translation = defaultdict(set)
    for group, rows in english.items():
        if len(rows) != len(latam[group]):
            raise ValueError("Android language pack has divergent group sizes")
        for en, es in zip(rows, latam[group]):
            translation[en].add(es)
    overrides = {**J2ME_MX, **help_texts(latam),
                 (0,203):latam[0][211], (0,205):latam[0][213]}
    groups = {}
    coverage = Counter()
    for group, rows in original.items():
        positions = {}
        for block in SequenceMatcher(None, rows, english[group], autojunk=False).get_matching_blocks():
            for delta in range(block.size):
                positions[block.a + delta] = block.b + delta
        result = []
        for index, text in enumerate(rows):
            if (group, index) in overrides:
                output, source = overrides[group, index], "adapted_mx"
            elif index in positions:
                output, source = latam[group][positions[index]], "apk_latam"
            elif len(translation[text]) == 1:
                output, source = next(iter(translation[text])), "apk_latam"
            elif group == 11 and re.fullmatch(r"(?:[A-Za-z]+(?: [A-Za-z]+)*|support@gameloft\.com)\s*", text):
                output, source = text, "credit_or_address"
            else:
                raise ValueError(f"Unmapped string {group}:{index}")
            if Counter(re.findall(r"%[a-zA-Z]+", text)) != Counter(re.findall(r"%[a-zA-Z]+", output)):
                raise ValueError(f"Changed substitution tokens in {group}:{index}")
            result.append(output)
            coverage[source] += 1
        groups[group] = result
    data = write_groups(groups)
    if read_groups(data) != groups:
        raise ValueError("Failed to round-trip localized text")
    return data, dict(coverage)


def resize_index(index, replacements, originals):
    """999 has repeated names for sprite shards. Edit only the replaced slots."""
    data = bytearray(index)
    count, = struct.unpack_from("<I", data)
    cursor = 4
    updated = set()
    for _ in range(count):
        length, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor:cursor + length].decode("ascii")
        cursor += length
        size, = struct.unpack_from("<I", data, cursor)
        if name in replacements:
            if size != len(originals.read(name)) or name in updated:
                raise ValueError(f"Unexpected resource index for {name}")
            struct.pack_into("<I", data, cursor, len(replacements[name]))
            updated.add(name)
        cursor += 4
    if cursor != len(data):
        raise ValueError("Malformed MIDlet resource index")
    return bytes(data)


# The first ten entries are the farm theme and the nine gameplay pieces.
# Numbers after them do not align: track 11 in the JAR is empty. The title
# and village identifications use the source MIDI track names and melodies.
MUSIC = {**{i: i for i in range(12)}, 13: 12, 14: 13}
# Two independently aligned waveform excerpts per cue. Preserve unconfirmed
# sounds and blank entries. Also replace byte-identical alternative-bank cues.
EFFECTS = {18: 17, 19: 18, 22: 21, 33: 32, 40: 39, 46: 45,
           57: 56, 59: 58, 62: 61}
PET_SOURCE_TO_SLOT = {64:119,65:120,69:121,70:122,71:123,68:124}
EXTRACTOR_SOURCE_TO_SLOT = {80:125,81:126}
COLLAR_KEY_SOUND = 135
# Event-only tracks have no equivalent in the original touch dispatch. Keep
# both editions' behavior addressable, including their unrelated cue numbers.
ADDITIONAL_SOUNDS = {source:137+i for i,source in enumerate((35,57,62,63,66,67,72,74,75,76,77,78,79))}
ORIGINAL_EMPTY_SLOTS = {24:23,26:25,27:26,28:27,29:28,30:29,34:33,53:52}
# Match the calls at the same gameplay event in the two engines. The animal
# sounds come from the species records (column 37), including the horse.
ANIMAL_SOUNDS = {15:14,16:15,17:16,18:17,19:18,20:19,21:20}
GAMEPLAY_SOUNDS = {
    23:22,  # Submit an order.
    25:24,  # Android's continuous farm ambience, played on its own channel.
    31:30,  # Focus the fertilized field and spawn the plane.
    32:31,  # Care animation on a selected animal.
    35:34,  # Confirm the new position of a farm object.
    37:36,  # Open the ready feed mill.
    38:37,  # Reveal a collectible, including the actor's type-60 branch.
    39:38,  # Restore a room of the mansion.
    41:40,  # Select the farm object.
    42:41,  # Display a newly available farm objective.
    43:42,  # Scripted scene 19.
    44:43,  # Animal payout at its feed-pile marker.
    45:44,  # Open the reward or purchase panel.
    47:46,  # Pick up an item or collect it on a neighbor's farm.
    48:47,  # Neighbor gift/return controls.
    49:48,  # Deliver an item to fill an order.
    50:49,  # Claim animal output after the barn capacity check.
    51:50,  # Open the order-board resource panel.
    52:51,  # Scripted scene 17.
    54:53,  # Scripted actor movement begins.
    55:54,  # Begin the farm transition.
    56:55,  # A farm action cannot be performed.
    60:59,  # Open a farm panel.
    61:60,  # Confirm/select a touchscreen control.
}


class SoundInfo(ctypes.Structure):
    _fields_ = [("frames", ctypes.c_int64), ("samplerate", ctypes.c_int),
                ("channels", ctypes.c_int), ("format", ctypes.c_int),
                ("sections", ctypes.c_int), ("seekable", ctypes.c_int)]


class VorbisReader:
    def __init__(self, path):
        location = str(path) if path else ctypes.util.find_library("sndfile")
        if not location:
            raise RuntimeError("Especifica la ruta a libsndfile con --decoder para decodificar el audio original.")
        self.lib = ctypes.CDLL(location)
        self.lib.sf_open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(SoundInfo)]
        self.lib.sf_open.restype = ctypes.c_void_p
        self.lib.sf_readf_float.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_float), ctypes.c_int64]
        self.lib.sf_readf_float.restype = ctypes.c_int64
        self.lib.sf_close.argtypes = [ctypes.c_void_p]
        self.lib.sf_close.restype = ctypes.c_int

    def wav(self, source, scratch):
        # sf_wchar_open supports non-ASCII paths on Windows.
        info = SoundInfo()
        if hasattr(self.lib, "sf_wchar_open"):
            open_file = self.lib.sf_wchar_open
            open_file.argtypes = [ctypes.c_wchar_p, ctypes.c_int, ctypes.POINTER(SoundInfo)]
            open_file.restype = ctypes.c_void_p
            filename = str(scratch)
        else:
            import os
            open_file = self.lib.sf_open
            filename = os.fsencode(scratch)
        scratch.write_bytes(source)
        handle = open_file(filename, 0x10, ctypes.byref(info))
        if not handle:
            raise ValueError("libsndfile no pudo abrir el audio del APK")
        try:
            final = source.rfind(b"OggS")
            if final < 0 or not source[final + 5] & 4:
                raise ValueError("Missing Vorbis end-of-stream granule")
            total, = struct.unpack_from("<Q", source, final + 6)
            if info.frames != total or total <= 0 or info.channels != 1 or info.samplerate != 32000:
                raise ValueError("Unexpected source duration, channels or sample rate")
            # Vorbis can reconstruct a few transients outside [-1,1].
            # Clamp them on conversion to PCM16 instead of wrapping polarity.
            samples = (ctypes.c_float * info.frames)()
            if self.lib.sf_readf_float(handle, samples, info.frames) != info.frames:
                raise ValueError("Incomplete Vorbis stream")
        finally:
            self.lib.sf_close(handle)
        output = io.BytesIO()
        with wave.open(output, "wb") as writer:
            writer.setparams((info.channels, 2, info.samplerate, info.frames, "NONE", ""))
            import sys
            from array import array
            pcm = array("h", (min(32767, max(-32768, round(x * 32768))) for x in samples))
            if sys.byteorder != "little":
                pcm.byteswap()
            writer.writeframes(pcm)
        return output.getvalue(), info.frames


def mp4_boxes(data):
    offset = 0
    while offset < len(data):
        if len(data) - offset < 8:
            raise ValueError("Incomplete MP4 box header")
        size, kind = struct.unpack_from(">I4s", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid MP4 box size")
        yield kind, data[offset + 8:offset + size]
        offset += size


def aac_presentation(source):
    movie = dict(mp4_boxes(dict(mp4_boxes(source))[b"moov"]))
    track = dict(mp4_boxes(movie[b"trak"]))
    header = dict(mp4_boxes(track[b"mdia"]))[b"mdhd"]
    if header[0] != 0:
        raise ValueError("Unsupported AAC media header version")
    timescale, duration = struct.unpack_from(">II", header, 12)
    metadata = dict(mp4_boxes(movie[b"udta"]))[b"meta"]
    entries = dict(mp4_boxes(metadata[4:]))[b"ilst"]
    for kind, entry in mp4_boxes(entries):
        if kind != b"----":
            continue
        fields = dict(mp4_boxes(entry))
        if fields.get(b"mean", b"")[4:] != b"com.apple.iTunes" or fields.get(b"name", b"")[4:] != b"iTunSMPB":
            continue
        value = fields[b"data"]
        if value[:8] != struct.pack(">II", 1, 0):
            raise ValueError("Unsupported iTunSMPB encoding")
        lead, tail, content = (int(word, 16) for word in value[8:].split()[1:4])
        if timescale <= 0 or content <= 0 or lead + tail + content != duration:
            raise ValueError("AAC presentation disagrees with MP4 track duration")
        return timescale, duration, lead, content
    raise ValueError("The original AAC presentation window is missing")


def aac_wav(source, scratch, decoder):
    executable = os.environ.get("GF3_FFMPEG") or shutil.which("ffmpeg")
    if not executable and decoder:
        # The Windows tool bundle places libsndfile in a Python wheel and
        # the FFmpeg executable beside that wheel's extraction directory.
        for parent in list(Path(decoder).resolve().parents)[:3]:
            candidate = parent / "ffmpeg.exe"
            if candidate.is_file():
                executable = str(candidate)
                break
    if not executable:
        raise RuntimeError("Instala FFmpeg o configura GF3_FFMPEG para convertir los sonidos AAC.")
    stream = scratch.with_suffix(".m4a")
    wav = scratch.with_suffix(".wav")
    stream.write_bytes(source)
    timescale, duration, lead, content = aac_presentation(source)
    # HE-AAC doubles the decoded sample rate. FFmpeg releases disagree about
    # which clock applies to gapless metadata, so request all coded frames.
    subprocess.run([executable, "-v", "error", "-nostdin", "-y", "-flags2", "+skip_manual",
                    "-i", str(stream), "-map", "0:a:0", "-c:a", "pcm_s16le", "-map_metadata",
                    "-1", "-bitexact", str(wav)], check=True)
    with wave.open(str(wav), "rb") as decoded:
        rate, channels = decoded.getframerate(), decoded.getnchannels()
        if decoded.getsampwidth() != 2 or channels not in (1, 2):
            raise ValueError("Unsupported AAC output format")
        scale, remainder = divmod(rate, timescale)
        if remainder or not scale or decoded.getnframes() != duration * scale:
            raise ValueError("AAC decoder did not return the entire MP4 track")
        frames = content * scale
        decoded.setpos(lead * scale)
        pcm = decoded.readframes(frames)
        if len(pcm) != frames * channels * 2:
            raise ValueError("Incomplete AAC presentation")
    output = io.BytesIO()
    with wave.open(output, "wb") as writer:
        writer.setparams((channels, 2, rate, frames, "NONE", ""))
        writer.writeframes(pcm)
    return output.getvalue(), frames


def build_audio(jar, apk, decoder):
    android = unpack(apk.read("assets/800x480/8"))
    original = unpack(jar.read("3"))
    if jar.read("0") != b"\x02\x0aaudio/midi\x0baudio/x-wav":
        raise ValueError("Unexpected MMAPI type table")
    effects = {**EFFECTS, **ANIMAL_SOUNDS, **GAMEPLAY_SOUNDS, **ORIGINAL_EMPTY_SLOTS}
    cues = {**MUSIC, **effects}
    for i, source in effects.items():
        # a.c(int,int,boolean) switches between the two MMAPI sound banks
        # by adding 52 to an effect number; several legacy alternate slots
        # contain placeholders or a different, lower quality recording.
        cues[i+52] = source
    if len(original)!=119:
        raise ValueError("Unsupported legacy sound bank")
    extra = PET_SOURCE_TO_SLOT | EXTRACTOR_SOURCE_TO_SLOT
    result = [*original,*([b'']*(2*len(extra)+2+2*len(ADDITIONAL_SOUNDS)))]
    for source,slot in extra.items():
        cues[slot]=source
        cues[slot+len(extra)]=source
    cues[COLLAR_KEY_SOUND]=73
    cues[COLLAR_KEY_SOUND+1]=73
    for source,slot in ADDITIONAL_SOUNDS.items():
        cues[slot]=source
        cues[slot+len(ADDITIONAL_SOUNDS)]=source
    if set(cues.values())!=set(range(len(android))):
        raise ValueError("Incomplete original audio library")
    metadata = []
    decoded = {}
    reader = VorbisReader(decoder)
    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory) / "cue.ogg"
        for target, source in sorted(cues.items()):
            payload = android[source][1:]
            if source not in decoded:
                decoded[source] = (aac_wav(payload,scratch,decoder) if payload[4:8]==b"ftyp"
                                   else reader.wav(payload,scratch))
            data, frames = decoded[source]
            result[target] = b"\x01" + data
            with wave.open(io.BytesIO(data)) as wav:
                rate,channels = wav.getframerate(),wav.getnchannels()
            metadata.append({"j2me": target, "apk": source, "frames": frames,
                             "sampleRate": rate, "channels": channels,
                             "sourceSha256": sha256(payload).hexdigest(),
                             "wavSha256": sha256(data).hexdigest()})
    data = pack(result)
    if unpack(data) != result:
        raise ValueError("Audio pack round-trip failed")
    return data, metadata


def build_media(jar: zipfile.ZipFile, apk: zipfile.ZipFile, *, decoder=None):
    from .store_locale import localize_store
    data, report = localize(jar, apk)
    audio, cues = build_audio(jar, apk, decoder)
    updates = {"EN": data, "3": audio, **localize_store(jar)}
    updates["999"] = resize_index(jar.read("999"), updates, jar)
    return updates, {"language": "es-MX", "strings": report, "apkAudio": cues,
                     "distinctAndroidRecordings":len({row['apk'] for row in cues}),
                     "catalogLabels":23, "regionalNotices":11}
