"""Recover Android's wheel panel 45, with native offline currency payment."""
import json
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from .hives import patch_code
from .neighbor import expose
from .visit_predators import _controls
from tools.timing.classfile import ClassFile, code_parts, instruction_offsets, pack_code, convert_helper, u2
from tools.world import entries, labels, pack, table


def patch_wheel(classes, apk, api):
    panels=entries(classes['6'])
    if len(panels)!=30:raise ValueError('Unexpected native panel count')
    prefix='assets/800x480/'
    android=entries(apk.read(prefix+'10'))[45]
    rows=_controls(android,True)
    if len(rows)!=13:raise ValueError('Unknown APK wheel panel')
    mapping={20:173,22:174,33:175,41:176}
    for i,raw in enumerate(rows):
        row=bytearray(raw)
        if row[0]==204:del row[-1]
        else:
            if row[8] not in mapping or row[10]!=0:raise ValueError('Unknown wheel UI sprite')
            row[8]=mapping[row[8]]
            del row[10]
        rows[i]=bytes(row)
    panels.append(android[:1]+b''.join(rows))
    buildings=table(entries(apk.read(prefix+'13'))[3])[1]
    if buildings[29][1]!=1019 or buildings[29][24]!=185:raise ValueError('Unexpected wheel building')
    game=ClassFile(classes['a.class'])
    patch_code(game,'fC','()V',[(i,b'\x10\x1e',b'\x10\x1f') for i in (0,8,16,60)])
    patch_code(game,'<init>','(Ljava/lang/Object;Ljava/lang/Object;)V',[(83,b'\x10\x32',b'\x10\x33')])
    patch_code(game,'gf3UiSpritePool','()[Le;',[(0,b'\x11\x00\xad',b'\x11\x00\xb1')])
    expose(game,game.methods,{('a','(I)V'),('a','()I'),('t','()V'),('f','(I)Z'),('g','(I)V'),('h','(I)V'),('e','()I'),('c','(Z)V'),
                            ('b','(IZ)V'),('E','(I)V'),('F','(I)V'),('H','(I)V'),('gf','()V'),('a','(Ljava/lang/String;IIII)V')})
    expose(game,game.fields,{('a','[I'),('a','[[[S'),('a','[[Ljava/lang/String;'),('a','[Le;'),('a','[Ll;'),('f','[B')})
    # The ordinary farm tap dispatcher already resolves the building row.
    previous=b'\xb8'+u2(game.ref('GF3Doghouse','openBuilding','(I)Z'))
    replacement=b'\xb8'+u2(game.ref('GF3Wheel','openBuilding','(I)Z'))
    changed=0
    for _,_,_,attrs in game.methods:
        for i,(tag,body) in enumerate(attrs):
            if game.string(tag)!='Code':continue
            header,raw,exceptions,extra=code_parts(body)
            code=bytearray(raw)
            for pc in instruction_offsets(raw):
                if raw[pc:pc+3]==previous:
                    code[pc:pc+3]=replacement;changed+=1
            attrs[i]=tag,pack_code(header,code,exceptions,extra)
    if changed!=1:raise ValueError('Wheel building entry not unique')
    for name,desc,alias,handler,load,ret,count in (
        ('d','(II)Z','gf3WheelPreviousScreen','dispatch',b'\x1a\x1b',b'\xac',2),
        ('I','(I)V','gf3WheelPreviousHit','hit',b'\x1a',b'\xb1',1)):
        i,=[i for i,(_,n,d,_) in enumerate(game.methods) if (game.string(n),game.string(d))==(name,desc)]
        flags,n,d,attrs=game.methods[i]
        game.methods[i]=(flags&~2,game.utf(alias),d,attrs)
        code=load+b'\xb8'+u2(game.ref('GF3Wheel',handler,desc))+ret
        game.methods.append((flags,n,d,[(game.utf('Code'),pack_code(u2(count)*2,code,u2(0),[]))]))
    words=labels(apk.read(prefix+'LATAM'))
    src=Path(__file__).resolve().parents[2]/'src/expansion/GF3Wheel.java'
    with TemporaryDirectory() as tmp:
        folder=Path(tmp)
        strings=folder/'GF3WheelText.java'
        strings.write_text('class GF3WheelText {static final String TITLE='+json.dumps(words[12516])+
                           ',SPIN='+json.dumps(words[12524])+';}',encoding='ascii')
        stub=folder/'a.java'
        stub.write_text('''class a {static int[] states;static short[][][] controls;
            static String[][] captions;static e[] assets;static l[] images;static byte[] flags;
            static void a(int n){}static void c(int n){}static void c(boolean b){}static void g(int n){}static void h(int n){}
            static boolean f(int n){return false;}static int e(){return 0;}
            static void b(int i,boolean load){}static void E(int i){}static void F(int i){}static void H(int i){}static void gf(){}static void t(){}
            static void a(String s,int gui,int i,int x,int y){}
            static boolean gf3WheelPreviousScreen(int p,int i){return false;}static void gf3WheelPreviousHit(int i){}}
            class g {static javax.microedition.lcdui.Graphics graphics;static void open(String n){}
            static byte[] read(int n){return null;}static void l(){}static int i(){return 0;}
            static void arc(javax.microedition.lcdui.Graphics gr,int x,int y,int w,int h,int a,int b,boolean flag){}}
            class e{void a(byte[] data,int n){}void a(javax.microedition.lcdui.Graphics g,int f,int x,int y,int flags){}int d(int f){return 0;}int e(int f){return 0;}}
            class l{}class GF3Doghouse{static boolean openBuilding(int n){return false;}}''',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-classpath',str(api.resolve()),
                        '-d',str(folder),str(stub),str(strings),str(src)],check=True)
        helper=ClassFile((folder/'GF3Wheel.class').read_bytes())
        for alias,actual in {'states':'a','controls':'a','captions':'a','assets':'a','images':'a','flags':'f',
                             'graphics':'a','open':'c','read':'a','arc':'a'}.items():
            helper.pool[helper.utf(alias)]=helper.pool[helper.utf(actual)]
        result={'GF3Wheel.class':convert_helper(helper.bytes()),
                'GF3WheelText.class':convert_helper((folder/'GF3WheelText.class').read_bytes())}
    return {**result,'a.class':game.bytes(),'6':pack(panels)}
