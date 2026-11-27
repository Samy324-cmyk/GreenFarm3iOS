"""Compare the northern terrain against APK layers positioned by cGame.Kv and s1.q1."""
import argparse
from hashlib import sha256
from pathlib import Path
from zipfile import ZipFile

from verify_farm import pixels
from tools.sprites import shards
from tools.world import entries

def atlas(blob):
    shape,locations,palettes,pages=pixels(blob)
    result=[]
    for (kind,width,height,_,_), (page,x,y) in zip(shape[0],locations):
        if kind:
            raise ValueError('Non-bitmap horizon module')
        stride,indices=pages[page]
        palette=palettes[page][0]
        result.append([b''.join(palette[i] for i in indices[row*stride+x:row*stride+x+width])
                       for row in range(y,y+height)])
    return result,shape[1]

def paint(canvas,mod,x,y,flags):
    w=len(mod[0])//3
    start=max(x,0)
    end=min(x+w,800)
    if start>=end:
        return
    for ry in range(max(0,-y),min(len(mod),480-y)):
        row=mod[-ry-1 if flags&2 else ry]
        line=canvas[ry+y]
        for col in range(start,end):
            shift=col-x
            pos=3*(w-1-shift if flags&1 else shift)
            rgb=row[pos:pos+3]
            if rgb!=b'\xff\x00\xff':
                line[3*col:3*col+3]=rgb

def checks(apk, profile):
    maps=entries(apk.read('assets/800x480/14'))
    tiles,flips=maps[0][1:],maps[1][1:]
    blobs=[b for v in shards(apk,'assets/800x480/9').values() for b in v]
    art={s:atlas(blobs[s]) for s in (0,77,78,79)}
    def half_sprite(mod):
        # The rotated touch renderer samples scaled scenery modules with
        # 8.8 fixed point. Its physical X corresponds to reversed world Y.
        h,w=len(mod),len(mod[0])//3
        ww,hh=(w+1)//2,(h+1)//2
        xs=[3*(i*((w<<8)//ww)>>8) for i in range(ww)]
        ys=[h-1-((hh-1-i)*((h<<8)//hh)>>8) for i in range(hh)]
        return [b''.join(mod[y][x:x+3] for x in xs) for y in ys]
    smaller={s:([half_sprite(m) for m in art[s][0]],art[s][1]) for s in (77,78)}
    smaller[0]=([[b''.join(row[x:x+3] for x in range(3,len(row),6)) for row in m[1::2]]
                 for m in art[0][0]],art[0][1])
    def frame(rows,slot,x,y,zoom):
        mods,parts=(art if zoom==100 else smaller)[slot]
        for m,dx,dy,_,flags,_ in parts:
            paint(rows,mods[m],x+int(dx*zoom/100),y+dy*zoom//100,flags)
    nposes=npix=0
    for pose in sorted(profile.glob('horizon-*.sha256')):
        _,zoom,cx,cy=pose.stem.split('-')
        zoom,cx,cy=map(int,(zoom,cx,cy))
        wx,wy=cx*100//zoom,cy*100//zoom
        rows=[bytearray(b'\xfa\x05\xe1'*800) for _ in range(480)]
        if wy<648:
            height=int(648-(648-wy)*215/648+0.5)*zoom//100-cy
            for y in range(max(0,min(480,height))):
                rows[y][:]=b'\x10\xb5\xf2'*800
        frame(rows,79,0,int((433-wy)*zoom/100),100)
        for x in range(0,58*72,240):
            frame(rows,78,x*zoom//100-(wx>>4)*zoom//100,int(648-(648-wy)*40/648+0.5)*zoom//100-cy,zoom)
        for x in range(0,58*72,400):
            frame(rows,77,x*zoom//100-cx,648*zoom//100-cy,zoom)
        # Android's tile layer clips pixels starting at row 18. The old
        # MIDlet began at row 16 and drew 116 extra ground modules.
        tw,th=72*zoom//100,36*zoom//100
        for ty in range(cy//th,(cy+479)//th+1):
            for tx in range(cx//tw,(cx+799)//tw+1):
                idx=ty*58+tx
                if tiles[idx]!=255:
                    paint(rows,(art if zoom==100 else smaller)[0][0][tiles[idx]],tx*tw-cx,ty*th-cy,flips[idx])
        digest=sha256(b''.join(rows)).hexdigest()
        expected=pose.read_text().strip()
        if digest!=expected:
            raise ValueError(f'Pixels differ at {zoom}% camera ({cx},{cy}): atlas {digest}, MIDP {expected}')
        nposes+=1
        npix+=800*480
    if nposes!=26:
        raise ValueError('Expected 13 farm camera positions at each of two zoom levels')
    print(f'Verified {nposes} northern views, {npix} APK terrain pixels.')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('apk',type=Path)
    p.add_argument('profile',type=Path)
    args=p.parse_args()
    with ZipFile(args.apk) as apk:
        checks(apk,args.profile)
