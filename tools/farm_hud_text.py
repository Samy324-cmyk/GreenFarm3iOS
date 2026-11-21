"""Draw the four farm HUD counters with the original Latin American Android bitmap fonts."""
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory
import zlib

from .loading_screen import font_map, glyphs
from .pause_menu import rows
from .timing.classfile import ClassFile, convert_helper, pack_code, u2
from .world import entries


CHARACTERS='0123456789 /,.-+'
CELL=32
BASELINE=24
PADDING=4


def font_atlas(apk):
    fonts=entries(apk.read('assets/800x480/2'))
    mapping=font_map(fonts[7])
    width,height=len(CHARACTERS)*CELL,3*CELL
    bitmap=bytearray(width*height*4)
    advances=bytearray()
    # cGame.Fv constructs font 1 in palette 1, and font 2 in palette 5 with
    # its blue outline from sheet 3. t0 first draws all outlines, then all fills.
    for row,(bank,color) in enumerate(((1,(255,255,255)),(3,(25,121,235)),(2,(255,255,255)))):
        for slot,ch in enumerate(CHARACTERS):
            frame=1 if ch==' ' else mapping[ord(ch)]
            advance,parts=glyphs(fonts[bank],[frame])
            if row<2:advances.append(advance)
            elif advance!=advances[len(CHARACTERS)+slot]:raise ValueError('Different fill and outline advances')
            for x,y,w,h,alpha in parts:
                dx,dy=PADDING+x,BASELINE+y
                if dx<0 or dy<0 or dx+w>CELL or dy+h>CELL:
                    raise ValueError('The source HUD glyph does not fit its cell')
                for j in range(h):
                    for i in range(w):
                        a=alpha[j*w+i]
                        if not a:continue
                        offs=4*((row*CELL+dy+j)*width+slot*CELL+dx+i)
                        bitmap[offs:offs+4]=bytes((*color,a))
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    scan=b''.join(b'\0'+bitmap[4*y*width:4*(y+1)*width] for y in range(height))
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))
    return png+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b''),advances


def patch_farm_hud_text(classes,apk,api):
    controls=rows(entries(classes['6'])[1],False)
    for idx,uid in ((13,8),(16,19),(22,118),(23,272)):
        if controls[idx][0]!=204 or struct.unpack_from('<H',controls[idx],1)[0]!=uid:
            raise ValueError('Unrecognized farm counter binding')
    atlas,advances=font_atlas(apk)
    game=ClassFile(classes['a.class'])
    desc='(Ljava/lang/String;IIII)V'
    for original,alias,redirect in (('a','originalLabel','simple'),('b','originalScrollingLabel','scrolling')):
        found=next((m for m in game.methods if game.string(m[1])==original and game.string(m[2])==desc),None)
        if found is None:raise ValueError('Missing native panel label draw')
        flags,name,sig,body=found
        idx=game.methods.index(found)
        game.methods[idx]=flags & ~2,game.utf(alias),sig,body
        code=bytes.fromhex('2a1b1c1d1504b8')+u2(game.ref('GF3FarmHudText',redirect,desc))+b'\xb1'
        game.methods.append((flags,name,sig,[(game.utf('Code'),pack_code(u2(5)+u2(5),code,u2(0),[]))]))
    with TemporaryDirectory() as temp:
        folder=Path(temp)
        stub=folder/'a.java'
        stub.write_text('class a {static short[][][] controls;static void originalLabel(String s,int p,int i,int x,int y){}'
                        'static void originalScrollingLabel(String s,int p,int i,int x,int y){}}'
                        'class g {static javax.microedition.lcdui.Graphics screen;}')
        src=Path(__file__).resolve().parents[1]/'src/catalog/GF3FarmHudText.java'
        subprocess.run(['javac','--release','8','-g:none','-cp',str(api),'-d',str(folder),str(stub),str(src)],check=True)
        helper=ClassFile((folder/'GF3FarmHudText.class').read_bytes())
        for name in ('controls','screen'):
            helper.pool[helper.utf(name)]=helper.pool[helper.utf('a')]
        return {'a.class':game.bytes(),'GF3FarmHudText.class':convert_helper(helper.bytes()),
                'farm-font.png':atlas,'farm-font-widths':bytes(advances)}
