"""Check all original recordings against independent PCM decoding and the shipped MIDP packs."""
import argparse
from array import array
from hashlib import sha256
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import wave
from zipfile import ZipFile

sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from tools.media import unpack


def aac_reference(path, source, decoder):
    # Decode the elementary stream independently. ADTS carries the AAC
    # packets without the MP4 metadata that FFmpeg might trim on its own.
    fields = re.search(rb'iTunSMPB.{4}data\x00\x00\x00\x01\x00\x00\x00\x00'
                       rb'\s+00000000 ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{16})',
                       source, re.DOTALL)
    if not fields:
        raise AssertionError('Missing AAC gapless metadata')
    lead, tail, content = (int(field, 16) for field in fields.groups())
    elementary = path.with_suffix('.aac')
    subprocess.run([decoder, '-v', 'error', '-nostdin', '-y', '-i', str(path), '-map', '0:a:0',
                    '-c:a', 'copy', '-f', 'adts', str(elementary)], check=True)
    return elementary, (lead, tail, content)


def verify(apk,game,decoder):
    report=json.loads(game.with_name('build.json').read_text('utf8'))
    if sha256(game.read_bytes()).hexdigest()!=report['jarSha256']:
        raise ValueError('Audio report belongs to another JAR')
    with ZipFile(apk) as source,ZipFile(game) as port:
        originals=unpack(source.read('assets/800x480/8'))
        bank=unpack(port.read('3'))
    by_source={}
    for info in report['media']['apkAudio']:
        idx=info['apk']
        data=bank[info['j2me']]
        if data[0]!=1 or info['wavSha256']!=sha256(data[1:]).hexdigest():
            raise AssertionError(f'Invalid WAV at MIDP {info["j2me"]}')
        if idx in by_source and by_source[idx]!=data[1:]:
            raise AssertionError(f'Playback banks disagree for Android {idx}')
        by_source[idx]=data[1:]
    if set(by_source)!=set(range(82)) or len(originals)!=82:
        raise AssertionError('Incomplete Android audio library')
    checked=0
    with TemporaryDirectory() as temp:
        for idx,data in sorted(by_source.items()):
            with wave.open(io.BytesIO(data)) as sound:
                channels,rate,frames=sound.getnchannels(),sound.getframerate(),sound.getnframes()
                if sound.getsampwidth()!=2 or channels not in (1,2):
                    raise AssertionError(f'Unexpected sample format at Android {idx}')
                actual=array('h',sound.readframes(frames))
            original=originals[idx][1:]
            vorbis=original.startswith(b'OggS')
            path=Path(temp)/('audio.ogg' if vorbis else 'audio.m4a')
            path.write_bytes(original)
            if not vorbis:
                path, (lead, tail, content) = aac_reference(path, original, decoder)
            reference=subprocess.check_output([decoder,'-v','error','-nostdin','-i',str(path),
                '-map','0:a:0','-c:a','pcm_s16le','-f','wav','-'])
            with wave.open(io.BytesIO(reference)) as reference_sound:
                if (reference_sound.getframerate(),reference_sound.getnchannels())!=(rate,channels):
                    raise AssertionError(f'Original format differs at Android {idx}')
                expected=array('h',reference_sound.readframes(reference_sound.getnframes()))
            if sys.byteorder!='little':
                actual.byteswap()
                expected.byteswap()
            if vorbis:
                # FFmpeg may add or omit the final overlapped block on
                # short one-page recordings. The EOS granule is definitive.
                end=original.rfind(b'OggS')
                granule,=struct.unpack_from('<Q',original,end+6)
                header=original.index(b'\x01vorbis')
                half_block=(1<<(original[header+28]>>4))//2
                if granule!=frames or abs(len(expected)-len(actual))>half_block*channels:
                    raise AssertionError(f'Incorrect Vorbis duration at Android {idx}')
            else:
                # All 20 HE-AAC originals decode to twice the AAC core rate.
                if (rate, channels) != (32000, 2) or len(expected) != 2 * (lead + tail + content) * channels:
                    raise AssertionError(f'Incomplete HE-AAC elementary stream at Android {idx}')
                if frames != 2 * content:
                    raise AssertionError(f'Incorrect AAC duration at Android {idx}: {frames} frames, expected {2 * content}')
                first = 2 * lead * channels
                expected = expected[first:first + frames * channels]
            peak=max(abs(a-b) for a,b in zip(actual,expected))
            if peak>2 or not any(actual):
                raise AssertionError(f'PCM differs from original Android {idx}, peak error {peak}')
            checked+=min(len(actual),len(expected))
    print(f'Verified all 82 Android recordings and {checked:,} PCM samples.')


if __name__=='__main__':
    args=argparse.ArgumentParser(description=__doc__)
    args.add_argument('--apk',required=True,type=Path)
    args.add_argument('--jar',required=True,type=Path)
    args.add_argument('--ffmpeg',default='ffmpeg')
    opts=args.parse_args()
    verify(opts.apk,opts.jar,opts.ffmpeg)
