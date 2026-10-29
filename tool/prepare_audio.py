#!/usr/bin/env python3
"""Rebuild iOS audio from the original /800x480/8 pack, or verify checked assets.

Vorbis is decoded to IEEE float32 WAV without further sample quantization.
Original M4A bytes are retained. SoundFile/libsndfile and FFprobe are preparation
dependencies only;
normal CI builds use the checked assets and --verify-only (Python stdlib).
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "assets/original/800x480/8"
OUT = ROOT / "assets/audio"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def entries():
    data = PACK.read_bytes()
    count, shards, flags = struct.unpack_from("<HHH", data)
    assert (count, shards, flags) == (82, 1, 0), "Unexpected original audio pack"
    offsets = struct.unpack_from("<" + "I" * (count + 1), data, 6)
    assert offsets[0] == 6 + 4 * (count + 1) and offsets[-1] == len(data)
    assert all(a < b for a, b in zip(offsets, offsets[1:]))
    return [(data[a], data[a + 1:b]) for a, b in zip(offsets, offsets[1:])]


def wav_pcm(data):
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE"
    assert struct.unpack_from("<I", data, 4)[0] + 8 == len(data)
    offset, fmt, pcm = 12, None, None
    while offset < len(data):
        key, size = struct.unpack_from("<4sI", data, offset)
        offset += 8
        assert offset + size <= len(data)
        value = data[offset:offset + size]
        if key == b"fmt ":
            code, channels, rate, _, block, bits = struct.unpack_from("<HHIIHH", value)
            if code == 65534:
                assert len(value) >= 40
                code = struct.unpack_from("<I", value, 24)[0]
            assert code == 3 and bits == 32 and block == channels * 4
            fmt = (channels, rate)
        elif key == b"data":
            pcm = value
        offset += size + (size & 1)
    assert fmt is not None and pcm is not None
    assert len(pcm) % (4 * fmt[0]) == 0
    return fmt, pcm


def ogg_frames(data):
    """Read original Vorbis channels/rate and final Ogg PCM granule."""
    pos, info, final = 0, None, None
    while pos < len(data):
        assert data[pos:pos+4] == b"OggS" and data[pos+4] == 0
        segments = data[pos+26]
        start = pos + 27 + segments
        end = start + sum(data[pos+27:start])
        assert end <= len(data)
        if pos == 0:
            packet = data[start:end]
            assert packet[:7] == b"\x01vorbis"
            info = (packet[11], struct.unpack_from("<I", packet, 12)[0])
        if data[pos+5] & 4:
            assert end == len(data)
            final = struct.unpack_from("<Q", data, pos+6)[0]
        pos = end
    assert info is not None and final is not None
    return (*info, final)


def verify():
    manifest = json.loads((OUT / "manifest.json").read_text())
    assert manifest["packSha256"] == sha(PACK.read_bytes())
    original = entries()
    assert len(manifest["tracks"]) == len(original) == 82
    counts = {"ogg": 0, "m4a": 0}
    total = 0
    for track, (kind, source) in zip(manifest["tracks"], original):
        assert track["index"] == sum(counts.values())
        assert track["typeByte"] == kind
        assert sha(source) == track["sourceSha256"]
        asset = ROOT / track["asset"]
        assert asset.resolve().is_relative_to(OUT.resolve())
        data = asset.read_bytes()
        assert sha(data) == track["assetSha256"]
        assert len(data) == track["assetBytes"]
        counts[track["sourceFormat"]] += 1
        total += len(data)
        if track["sourceFormat"] == "ogg":
            (channels, rate), pcm = wav_pcm(data)
            assert (channels, rate) == (track["channels"], track["sampleRate"])
            assert sha(pcm) == track["decodedPcmSha256"]
            assert len(pcm) // (4 * channels) == track["decodedFrames"]
            assert ogg_frames(source) == (channels, rate, track["decodedFrames"])
        else:
            assert source == data
    assert counts == {"ogg": 62, "m4a": 20}
    print(json.dumps({"verified": 82, "float32Wav": 62, "unchangedM4a": 20, "assetBytes": total}))


def generate(ffmpeg, ffprobe, workers):
    import soundfile as sf
    OUT.mkdir(parents=True, exist_ok=True)
    scratch = ROOT / ".dart_tool/audio-prepare"
    scratch.mkdir(parents=True, exist_ok=True)
    assert scratch.resolve().is_relative_to(ROOT)
    version = subprocess.check_output([ffmpeg, "-version"], text=True).splitlines()[0]

    def convert(item):
        index, (kind, source) = item
        ext = "ogg" if source.startswith(b"OggS") else "m4a" if source[4:8] == b"ftyp" else None
        assert ext is not None, f"Unknown audio header {index}"
        src = scratch / f"audio_{index:03d}.{ext}"
        src.write_bytes(source)
        probe = json.loads(subprocess.check_output([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(src)]))
        assert len(probe["streams"]) == 1
        stream = probe["streams"][0]
        assert stream["codec_name"] == ("vorbis" if ext == "ogg" else "aac")
        rate, channels = int(stream["sample_rate"]), int(stream["channels"])
        row = {"index": index, "typeByte": kind, "sourceFormat": ext,
               "sourceSha256": sha(source), "sourceBytes": len(source),
               "sourceCodec": stream["codec_name"], "sourceSampleFormat": stream["sample_fmt"],
               "sampleRate": rate, "channels": channels,
               "sourceDurationSeconds": float(stream["duration"])}
        dst = OUT / f"audio_{index:03d}.{'wav' if ext == 'ogg' else 'm4a'}"
        if ext == "ogg":
            # libsndfile's reference Vorbis decoder honors the final Ogg
            # granule, including the complete final lapped PCM block. FFmpeg's
            # demux+decode path loses 256 final samples in some source tracks
            # and emits untrimmed codec padding in others. Do not insert guessed
            # silence or rely on those timestamps to reconstruct the samples.
            samples, decoded_rate = sf.read(src, dtype="float32", always_2d=True)
            assert (decoded_rate, samples.shape[1]) == (rate, channels)
            frames = len(samples)
            assert frames == int(stream["duration_ts"]), (index, frames, stream["duration_ts"])
            pcm = samples.astype("<f4", copy=False).tobytes()
            # Deterministic IEEE-float WAVEFORMATEX + fact + data; no metadata.
            fmt = struct.pack("<HHIIHHH", 3, channels, rate, rate*channels*4, channels*4, 32, 0)
            body = b"WAVEfmt " + struct.pack("<I",len(fmt)) + fmt
            body += b"fact" + struct.pack("<II",4,frames)
            body += b"data" + struct.pack("<I",len(pcm)) + pcm
            dst.write_bytes(b"RIFF" + struct.pack("<I",len(body)) + body)
            (out_channels, out_rate), decoded = wav_pcm(dst.read_bytes())
            assert (channels, rate) == (out_channels, out_rate) and decoded == pcm
            # Read the finished asset through the independent container reader.
            back, back_rate = sf.read(dst, dtype="float32", always_2d=True)
            assert back_rate == rate and back.astype("<f4", copy=False).tobytes() == pcm
            row.update(decodedFrames=frames, decodedPcmSha256=sha(pcm), pcmEncoding="float32le", durationSeconds=frames / rate)
        else:
            shutil.copyfile(src, dst)
            row["durationSeconds"] = float(stream["duration"])
        data = dst.read_bytes()
        row.update(asset=dst.relative_to(ROOT).as_posix(), assetSha256=sha(data), assetBytes=len(data))
        return row

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        tracks = list(pool.map(convert, enumerate(entries())))
    manifest = {"schemaVersion": 1, "packAsset": PACK.relative_to(ROOT).as_posix(),
                "packSha256": sha(PACK.read_bytes()), "decoder": f"SoundFile {sf.__version__} / libsndfile {sf.__libsndfile_version__}", "probe": version,
                "conversion": "Reference Vorbis decoder -> IEEE float32 WAV; decoded PCM retained bit-for-bit, final frame count matches original Ogg granule; M4A retained byte-for-byte",
                "sources": ["https://libsndfile.github.io/libsndfile/", "https://xiph.org/vorbis/doc/Vorbis_I_spec.html"], "tracks": tracks}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    verify()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--python-deps", help="Optional directory containing soundfile dependencies")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    if args.python_deps:
        sys.path.insert(0, str(Path(args.python_deps).resolve()))
    if args.verify_only:
        verify()
    else:
        generate(args.ffmpeg, args.ffprobe, args.workers)
