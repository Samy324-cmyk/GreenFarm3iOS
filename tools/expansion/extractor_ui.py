"""Append the 4.4.4 honey press panel and its animated sheet to MIDP group 22."""
import json
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory

from tools.sprites import android_modules, convert_sprite, geometry, shards
from tools.timing.classfile import ClassFile, convert_helper
from tools.world import entries, labels, pack
from .visit_predators import _controls


def _button(blob,frame):
    """Compose the two end caps and one-pixel strip as cGame.wp does, then rotate for MIDP."""
    shape,xy,reader,_,extra=geometry(blob)
    _,_,palette,blocks=android_modules(shape,xy,reader,extra)
    count,first,_=shape[3][frame]
    parts=shape[1][first:first+count]
    if count!=3: raise ValueError('Unexpected honey button')
    width=max(x+shape[0][mod][1] for mod,x,_,_,_,_ in parts)
    height=max(y+shape[0][mod][2] for mod,_,y,_,_,_ in parts)
    pixels=bytearray(width*height*4)
    for n,(mod,x,y,_,flags,_) in enumerate(parts):
        _,w,h,_,_=shape[0][mod]
        if flags not in (0,1) or (n==2 and w!=1): raise ValueError('Unexpected honey button cap')
        for j in range(h):
            for i in range(width-2*x if n==2 else w):
                index=blocks[mod][j*w + (0 if n==2 else w-1-i if flags&1 else i)]
                rgb=palette[3*index:3*index+3][::-1]
                dest=((x+i)*height+height-1-y-j)*4
                if rgb!=b'\xff\0\xff':
                    pixels[dest:dest+4]=b'\xff'+rgb
    return b'\x02'+struct.pack('>HH',height,width)+pixels


def patch_extractor_ui(classes,apk):
    panels=entries(classes['6'])
    local=_controls(panels[22],False)
    source=_controls(entries(apk.read('assets/800x480/10'))[22],True)
    if len(local)!=174 or len(source)<163:
        raise ValueError('Unsupported cooking panel')
    for item in [*source[147:163],source[167]]:
        control=bytearray(item)
        if control[0]==204:
            del control[-1]
            control[23]=0
        else:
            if control[10]!=0: raise ValueError('Unexpected extractor frame width')
            del control[10]
            control[8]=166+(20,22,48,125).index(control[8])
            control[13]=control[26]=0
        local.append(control)
    panels[22]=panels[22][:1]+b''.join(local)
    words=labels(apk.read('assets/800x480/LATAM'))
    sheets=[s for group in shards(apk,'assets/800x480/11').values() for s in group]
    result={'6':pack(panels),'hx':pack([convert_sprite(sheets[125]),convert_sprite(sheets[2]),
                                         _button(sheets[20],244),_button(sheets[20],245)])}
    with TemporaryDirectory() as tmp:
        folder=Path(tmp)
        stub=folder/'a.java'
        stub.write_text("""class a {
          static short[][][] controls,templates;static e[] assets;static l[] images;static byte[] flags;
          static boolean gf3QueueScreen(int p){return false;}
          static int g(int t,int n){return 0;}static void c(int n){}
          static void a(int gui,short[] c,int x,int y,int i){}
          static void a(String s,int gui,int i,int x,int y){}
          static void a(String s,int x,int y,int w,int h,int vert,int align,int font,int pal,boolean b,boolean u){}
        } class g {static int ab,ac,ad; static void gf3Open(String n){}
          static byte[] gf3Read(int n){return null;}static void l(){}}
          class h {static h[] tables;int[][] rows;}class l {static l a(int[] rgb,int w,int h,boolean a){return null;}}
          class e {void a(byte[] b,int o){} void a(int f,int p,int[] b,int o){}}
          class k {k(e s,int x,int y){} void b(int n,int r){}void c(int dt){}
            void gf3Render(){}boolean gf3Finished(){return false;}}
          class GF3KitchenQueue{static boolean extract(int[] r){return false;}}
          class GF3HoneyTutorial{static int phase(){return 0;}static boolean refill(){return false;}
            static void kitchen(){}static void drawPress(){}static void extractionFinished(){}}""",encoding='ascii')
        data=folder/'GF3ExtractorText.java'
        data.write_text('class GF3ExtractorText {static String extract='+json.dumps(words[12379])+
                        ',combs='+json.dumps(words[8635])+',unavailable='+json.dumps(words[12333])+';}',encoding='ascii')
        src=Path(__file__).resolve().parents[2]/'src/expansion/GF3ExtractorUI.java'
        subprocess.run(['javac','--release','8','-g:none','-d',str(folder),str(stub),str(data),str(src)],check=True)
        cf=ClassFile((folder/'GF3ExtractorUI.class').read_bytes())
        for alias,original in {'controls':'a','templates':'b','assets':'a','tables':'a','rows':'a',
                               'images':'a','flags':'f','gf3Open':'c','gf3Read':'a','gf3Render':'c','gf3Finished':'a'}.items():
            cf.pool[cf.utf(alias)]=cf.pool[cf.utf(original)]
        result['GF3ExtractorUI.class']=convert_helper(cf.bytes())
        result['GF3ExtractorText.class']=convert_helper((folder/'GF3ExtractorText.class').read_bytes())
    return result
