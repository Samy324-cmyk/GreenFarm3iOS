"""Verify every converted world module and compose common character and building poses from the APK."""
import argparse
from hashlib import sha256
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]))
from tools.farm_art import world_slots
from tools.hud_art import ANDROID_ZOOM_ALIASES, FARM_CONTROLS, HUD_SLOTS, PAUSE_ALIAS, SHOP_FRAMES, ZOOM_FRAMES
from tools.sprites import geometry, indices, midp_modules, shards
from verify import oracle


def pixels(blob):
    shape, locations,r,_,_=geometry(blob)
    pixel,mode,count=r.num('H'),r.num('H'),r.num('B')
    if pixel!=0x8808:
        raise ValueError('Unexpected color model for base farm assets')
    palettes=[]
    sheets=[]
    for _ in range(count):
        n,size=r.num('B'),r.num('B') or 256
        palettes.append([[r.take(3)[::-1] for _ in range(size)] for _ in range(n)])
    for pal in palettes:
        w,h=r.num('H'),r.num('H')
        sheets.append((w,indices(r.take(r.num('I')),mode,w*h,len(pal[0]))))
    return shape,locations,palettes,sheets


def midp_zoom_source(blob):
    shape,_,reader,flags,_=geometry(blob)
    variants,colors,raw,blocks=midp_modules(shape,reader,flags)
    if variants!=1:
        raise ValueError('Unsupported original touch HUD palette')
    pal=[[raw[i:i+3][::-1] for i in range(0,colors*3,3)]]
    locations=[(idx,0,0) for idx in range(len(blocks))]
    return shape,locations,[pal]*len(blocks),[(m[1],b) for m,b in zip(shape[0],blocks)]


def half_ground_oracle(blob):
    shape,locations,palettes,sheets=pixels(blob)
    rows=[]
    for module,((_,w,h,_,_),(page,x,y)) in enumerate(zip(shape[0],locations)):
        stride,tex=sheets[page]
        for variant,pal in enumerate(palettes[page]):
            colors=[bytes([0 if rgb==b'\xff\0\xff' else 255])+rgb for rgb in pal]
            rgba=b''.join(colors[tex[(y+j)*stride+x+i]] for j in range(1,h,2) for i in range(1,w,2))
            rows.append(struct.pack('>HBI',module,variant,w*h//4)+sha256(rgba).digest())
    return rows


def posed(source,frame,variant):
    shape,locations,palettes,sheets=source
    count,first,_=shape[3][frame]
    modules=[]
    for mod,x,y,_,flags,_ in shape[1][first:first+count]:
        kind,w,h,color,_=shape[0][mod]
        solid=None
        if kind!=0:
            if kind==253:
                continue
            if kind!=254 or color>>24 not in (0,255):
                raise ValueError(f'Unhandled drawn shape {kind}')
            solid=(color&0xffffff).to_bytes(3,'big')
            if flags&4:
                w,h=h,w
        page,u,v=locations[mod]
        if flags not in (0,1,2,3) and (solid is None or flags!=4):
            raise ValueError(f'Unknown module transform {flags}')
        modules.append((x,y,w,h,flags,page,u,v,solid))
    if not modules:
        return None
    # Logical farm coordinates are (800,480). The native MIDlet rotates
    # that view clockwise into a (480,800) touch screen.
    x0=max(0,min(480-(240+y+h) for x,y,w,h,*_ in modules)-1)
    y0=max(0,min(400+x for x,*_ in modules)-1)
    x1=min(480,max(480-(240+y) for x,y,w,h,*_ in modules)+1)
    y1=min(800,max(400+x+w for x,y,w,*_ in modules)+1)
    if x1<=x0 or y1<=y0:
        return None
    width,height=x1-x0,y1-y0
    buffer=bytearray(b'\xf8\x1f\xe9'*(width*height))
    for x,y,w,h,flags,page,u,v,solid in modules:
        stride,data=sheets[page]
        pal=palettes[page][variant]
        for j in range(h):
            px=479-(240+y+j)
            if not x0<=px<x1:
                continue
            row=(v+(h-1-j if flags&2 else j))*stride+u
            for i in range(w):
                py=400+x+i
                if not y0<=py<y1:
                    continue
                c=solid if solid is not None else pal[data[row+(w-1-i if flags&1 else i)]]
                if solid is not None or c!=b'\xff\0\xff':
                    p=3*((py-y0)*width+px-x0)
                    buffer[p:p+3]=c
    return struct.pack('>4H',x0,y0,width,height)+sha256(buffer).digest()


def verify(args):
    modules,poses=[],[]
    with ZipFile(args.reference) as ref, ZipFile(args.apk) as apk, ZipFile(args.jar) as jar:
        slots=world_slots(ref,apk)
        source=[b for blocks in shards(apk,'assets/800x480/9').values() for b in blocks]
        target=[b for blocks in shards(jar,'5').values() for b in blocks]
        for slot,values in ((0,oracle(source[0])),(158,half_ground_oracle(source[0]))):
            blob=target[slot][1:]
            label=f'ground/{slot}'.encode('ascii')
            modules.append(struct.pack('>H',len(label))+label+struct.pack('>I',len(blob))+blob
                           +struct.pack('>I',len(values))+b''.join(values))
        for slot in sorted(slots):
            blob=target[slot][1:]
            expected=oracle(source[slot])
            label=f'world/{slot}'.encode('ascii')
            modules.append(struct.pack('>H',len(label))+label+struct.pack('>I',len(blob))+blob
                           + struct.pack('>I',len(expected))+b''.join(expected))
            src=pixels(source[slot])
            shape=src[0]
            ids={0}
            for length,first in shape[5]:
                if length:
                    ids.update((shape[4][first][0],shape[4][first+length-1][0]))
            if len(shape[3])<=6:
                ids.update(range(len(shape[3])))
            checks=[]
            for frame in sorted(ids):
                for variant in {0,len(src[2][0])-1}:
                    digest=posed(src,frame,variant)
                    if digest:
                        checks.append(struct.pack('>HB',frame,variant)+digest)
            if slot==20:
                for legacy,frame in ((67,35),(95,63),(96,64)):
                    digest=posed(src,frame,0)
                    if digest:
                        checks.append(struct.pack('>HB',legacy,0)+digest)
            poses.append(struct.pack('>II',slot,len(blob))+blob+struct.pack('>I',len(checks))+b''.join(checks))
        source=[b for blocks in shards(apk,'assets/800x480/11').values() for b in blocks]
        target=[b for blocks in shards(jar,'7').values() for b in blocks]
        legacy=[b for blocks in shards(ref,'7').values() for b in blocks]
        for slot,changed in FARM_CONTROLS.items():
            src=pixels(source[slot]);old=midp_zoom_source(legacy[slot]);checks=[]
            for frame in range(len(old[0][3])):
                digest=posed(src if frame in changed else old,frame,0)
                if digest: checks.append(struct.pack('>HB',frame,0)+digest)
            if slot==20:
                for frame,alias in PAUSE_ALIAS.items():
                    digest=posed(src,frame,0)
                    if digest: checks.append(struct.pack('>HB',alias,0)+digest)
            blob=target[slot][1:]
            poses.append(struct.pack('>II',1000+slot,len(blob))+blob+struct.pack('>I',len(checks))+b''.join(checks))
        for slot in HUD_SLOTS:
            blob=target[slot][1:]
            expected=oracle(source[slot])
            label=f'hud/{slot}'.encode('ascii')
            modules.append(struct.pack('>H',len(label))+label+struct.pack('>I',len(blob))+blob
                           +struct.pack('>I',len(expected))+b''.join(expected))
            src=pixels(source[slot])
            checks=[]
            for frame in range(len(src[0][3])):
                target_frame=ANDROID_ZOOM_ALIASES.get(frame,frame) if slot==1 else frame
                if slot==10:
                    target_frame=SHOP_FRAMES.index(frame)
                for variant in range(len(src[2][0])):
                    digest=posed(src,frame,variant)
                    if digest:
                        checks.append(struct.pack('>HB',target_frame,variant)+digest)
            if slot==1:
                src=midp_zoom_source(legacy[slot])
                for frame in ZOOM_FRAMES:
                    checks.append(struct.pack('>HB',frame,0)+posed(src,frame,0))
            poses.append(struct.pack('>II',1000+slot,len(blob))+blob+struct.pack('>I',len(checks))+b''.join(checks))
    with tempfile.TemporaryDirectory() as temp:
        folder=Path(temp)
        subprocess.run(['javac','--release','17','-cp',str(args.api),'-d',temp,
                        str(HERE/'SpritePixels.java'),str(HERE/'FarmPosePixels.java')],check=True)
        cp=os.pathsep.join(map(str,(folder,args.jar.resolve(),args.api.resolve())))
        for name,pieces in (('SpritePixels',modules),('FarmPosePixels',poses)):
            data=folder/(name+'.bin')
            data.write_bytes(struct.pack('>I',len(pieces))+b''.join(pieces))
            done=subprocess.run([args.java,'-Djava.awt.headless=true','-Dfile.encoding=ISO_8859_1',
                                 '-cp',cp,name,str(data)],check=True,stdout=subprocess.PIPE,cwd=folder)
            if not done.stdout.startswith(b'Verified '):
                raise ValueError(f'{name} did not complete its comparisons')
            print(done.stdout.decode('ascii').strip())


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for param in ('reference','apk','jar','api'):
        parser.add_argument('--'+param,required=True,type=Path)
    parser.add_argument('--java',default='java')
    verify(parser.parse_args())
