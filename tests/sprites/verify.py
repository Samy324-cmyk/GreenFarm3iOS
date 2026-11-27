"""Compare the shipping MIDP renderer against Android pixel values read directly from the atlas."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.sprites import geometry, indices, shards


def oracle(blob):
    sig, positions, r, _, _ = geometry(blob)
    pixel, encoding, pages = r.num('H'), r.num('H'), r.num('B')
    argb = pixel == 0x8888
    width = 4 if argb else 3
    palettes, images, expected = [], [], []
    for _ in range(pages):
        variants, colors = r.num('B'), r.num('B') or 256
        palettes.append([[r.take(width) for _ in range(colors)] for _ in range(variants)])
    for pal in palettes:
        w, h, size = r.num('H'), r.num('H'), r.num('I')
        source = r.take(size)
        images.append((w,source if argb else indices(source,encoding,w*h,len(pal[0]))))
    if r.pos != len(blob):
        raise ValueError('Unexpected Android resource tail')
    for idx, ((kind,mw,mh,_,_), (page,x,y)) in enumerate(zip(sig[0],positions)):
        if kind:
            continue
        w, rgba = images[page]
        for variant, pal in enumerate(palettes[page]):
            hasher = hashlib.sha256()
            mapped = [bytes([0 if p[:3] == b'\xff\x00\xff' else 255]) + p[2::-1] for p in pal]
            for row in range(y, y + mh):
                pos = row*w+x
                if argb:
                    source = rgba[2*pos:2*(pos+mw)]
                    hasher.update(b''.join(bytes([a])+pal[i][2::-1] for a,i in zip(source[::2],source[1::2])))
                else:
                    hasher.update(b''.join(mapped[i] for i in rgba[pos:pos+mw]))
            expected.append(struct.pack('>HBI',idx,variant,mw*mh) + hasher.digest())
    return expected


def verify(args):
    pieces = []
    mappings={(5,i):(9,19 if i==188 else i) for i in (13,*range(159,189))}
    mappings.update({(7,i):(11,i) for i in (2,34,*range(122,138))})
    report=args.jar.with_name('build.json')
    if report.is_file():
        manifest=json.loads(report.read_text('utf8'))
        if hashlib.sha256(args.jar.read_bytes()).hexdigest()!=manifest['jarSha256']:
            raise ValueError('Sprite report belongs to another MIDlet')
        for group in ('androidSpriteSlotsReencoded','identicalOriginalSlots'):
            for dst,slot,source,original in manifest['sprites'][group]:
                mappings[dst,slot]=source,original
    with ZipFile(args.apk) as apk, ZipFile(args.jar) as jar:
        android={g:[b for v in shards(apk,'assets/800x480/'+str(g)).values() for b in v] for g in (9,11)}
        mobile={g:[b for v in shards(jar,str(g)).values() for b in v] for g in (5,7)}
        for (dst,slot),(src,source_index) in sorted(mappings.items()):
            encoded = mobile[dst][slot][1:]
            expected = oracle(android[src][source_index])
            label = f'{dst}/{slot} <- {src}/{source_index}'.encode()
            pieces.append(struct.pack('>H',len(label)) + label + struct.pack('>I',len(encoded))
                          + encoded + struct.pack('>I',len(expected)) + b''.join(expected))
    with tempfile.TemporaryDirectory() as output:
        data = Path(output)/'oracle.bin'
        data.write_bytes(struct.pack('>I',len(pieces))+b''.join(pieces))
        subprocess.run(['javac','--release','17','-d',output,str(Path(__file__).with_name('SpritePixels.java'))],check=True)
        subprocess.run([args.java,'-cp',os.pathsep.join(map(str,(output,args.jar,args.api))),
                        'SpritePixels',str(data)],check=True)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    for key in ('apk','jar','api'):
        ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--java',default='java')
    verify(ap.parse_args())
