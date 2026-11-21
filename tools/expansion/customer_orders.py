"""Bring the APK's per-customer order refresh interval into the MIDP stand."""
import json
from pathlib import Path
import subprocess
import tempfile

from .neighbor import entry,expose
from .visit_predators import _controls
from tools.mexican_spanish import adapt
from tools.timing.classfile import ClassFile,convert_helper,pack_code,u2
from tools.world import entries,labels,pack


def patch_customer_orders(classes,apk):
    panels=entries(classes['6'])
    legacy=_controls(panels[3],False)
    source=_controls(entries(apk.read('assets/800x480/10'))[3],True)
    if len(legacy)!=208 or len(source)!=243:
        raise ValueError('Unexpected sales stand layout')
    for index in (216,217,218,222,223,224):
        ctl=bytearray(source[index])
        if ctl[0]==204:del ctl[-1]
        else:
            if ctl[8]!=20:raise ValueError('Unsupported sales stand sprite')
            del ctl[10]
            ctl[13]=ctl[26]=0
        legacy.append(ctl)
    panels[3]=panels[3][:1]+b''.join(legacy)
    game=ClassFile(classes['a.class'])
    expose(game,game.fields,{('aw','Z'),('cA','I'),('cB','I'),('cC','I'),('ab','[I'),
                            ('a','[[[S'),('b','[[[S'),('a','[Le;')})
    expose(game,game.methods,{('gf','()V'),('H','(I)V'),('ah','(I)V'),('s','(II)V'),
        ('a','(ILh;)V'),('d','(IZ)V'),('e','(I)Ljava/lang/String;'),('f','(I)Z'),
        ('a','(Ljava/lang/String;IIII)V'),('b','(Ljava/lang/String;IIII)V'),
        ('a','(Ljava/lang/String;II)V')})
    entry(game,'p','(I)Z','gf3StandScreen','screen','(I)Z',b'\x1a','GF3CustomerOrders')
    entry(game,'n','(I)Z','gf3CanDeliver','available','(I)Z',b'\x1a','GF3CustomerOrders')
    for key,desc,handler,alias,load in [('ao','()V','discard',None,b''),
                                        ('I','(I)V','hit','gf3StandHit',b'\x1a')]:
        for i,(flags,n,d,attrs) in enumerate(game.methods):
            if (game.string(n),game.string(d))!=(key,desc):continue
            code=load+b'\xb8'+u2(game.ref('GF3CustomerOrders',handler,desc))+b'\xb1'
            replacement=(flags,n,d,[(game.utf('Code'),pack_code(u2(len(load))*2,code,u2(0),[]))])
            if alias:
                game.methods[i]=(flags&~2,game.utf(alias),d,attrs)
                game.methods.append(replacement)
            else:game.methods[i]=replacement
            break
        else:raise ValueError(f'Missing stand entry {key}{desc}')
    chain=ClassFile(classes['GF3DogToys.class'])
    for name,desc in [('pack','([B)[B'),('unpack','([B)[B'),('reset','()V')]:
        chain.pool[chain.ref('GF3DogTutorial',name,desc)]=chain.pool[chain.ref('GF3CustomerOrders',name,desc)]
    base=Path(__file__).resolve().parents[2]/'src/expansion/GF3CustomerOrders.java'
    texts=labels(apk.read('assets/800x480/LATAM'))
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        data=folder/'GF3CustomerText.java'
        literals=','.join(name+'='+json.dumps(adapt(texts[label]),ensure_ascii=True)
                          for name,label in [('WAIT',12348),('DETAIL',12347),('MISSING',390)])
        data.write_text('class GF3CustomerText {static final String '+literals+';}',encoding='ascii')
        stub=folder/'a.java'
        stub.write_text('''class a {static int cA,cB,cC;static int[] ab;static boolean aw;
            static short[][][] ui,templates;static e[] assets;
            static int a(){return 0;}static void gf(){}static void H(int g){}static void c(int s){}
            static void select(int pos){}static void generate(int pos,h table){}static void rebind(int pos,int slot){}
            static void card(int pos,boolean show){}
            static boolean gf3CanDeliver(int slot){return false;}static boolean gf3StandScreen(int e){return false;}
            static void gf3StandHit(int event){}static boolean payBills(int price){return false;}
            static void line(String text,int gui,int row,int x,int y){}static void wrap(String s,int g,int r,int x,int y){}
            static void notice(String text,int gui,int row){}static String time(int s){return "";}
        }class e{void a(byte[] x,int offset){}}class h{}
        class g{static void open(String file){}static byte[] chunk(int slot){return null;}static void l(){}}
        class GF3DogTutorial{static void reset(){}static byte[] pack(byte[] b){return b;}
            static byte[] unpack(byte[] b)throws java.io.IOException{return b;}}''',encoding='ascii')
        subprocess.run(['javac','--release','8','-g:none','-Xlint:-options','-d',str(folder),str(stub),
                        str(data),str(base)],check=True)
        helper=ClassFile((folder/'GF3CustomerOrders.class').read_bytes())
        remap={'ui':'a','templates':'b','assets':'a','select':'ah','generate':'a','rebind':'s','card':'d',
               'payBills':'f','line':'a','wrap':'b','notice':'a','time':'e','open':'c','chunk':'a'}
        for alias,name in remap.items():
            helper.pool[helper.utf(alias)]=helper.pool[helper.utf(name)]
        return {'a.class':game.bytes(),'GF3DogToys.class':chain.bytes(),'6':pack(panels),
                'GF3CustomerOrders.class':convert_helper(helper.bytes())}
