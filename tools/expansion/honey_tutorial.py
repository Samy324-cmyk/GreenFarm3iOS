"""Bind the original honey quest stages to the home farm, real hive and extractor."""
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from tools.timing.classfile import ClassFile,convert_helper
from tools.mexican_spanish import adapt
from tools.world import entries,labels,pack
from .neighbor import entry,expose
from .visit_predators import _controls


def patch_honey_tutorial(classes,apk):
    game=ClassFile(classes['a.class'])
    expose(game,game.fields,{('dW','I'),('d','Lf;')})
    entry(game,'D','(I)Z','gf3HoneyFarm','farm','(I)Z',b'\x1a','GF3HoneyTutorial')
    entry(game,'s','(I)Z','gf3HoneyInventory','inventory','(I)Z',b'\x1a','GF3HoneyTutorial')
    save=ClassFile(classes['GF3CatalogSave.class'])
    for name,desc in [('write','(Ljava/lang/String;[B)V'),('read','(Ljava/lang/String;)[B')]:
        save.pool[save.ref('GF3HomePredator',name,desc)]=save.pool[save.ref('GF3HoneyTutorial',name,desc)]
    result={'a.class':game.bytes(),'GF3CatalogSave.class':save.bytes()}
    gui=entries(classes['6'])
    mobile=entries(apk.read('assets/800x480/10'))
    for group,start,indices in ((10,69,(81,)),(22,191,(249,254,255))):
        rows=_controls(gui[group],False)
        target=_controls(mobile[group],True)
        if len(rows)!=start: raise ValueError('Unknown tutorial control count')
        for i in indices:
            marker=bytearray(target[i])
            if marker[0]!=205 or marker[8]!=3 or marker[10]!=0:raise ValueError('Unknown original tutorial marker')
            del marker[10]
            marker[13]=marker[26]=0
            rows.append(marker)
        gui[group]=gui[group][:1]+b''.join(rows)
    result['6']=pack(gui)
    words=labels(apk.read('assets/800x480/LATAM'))
    source=Path(__file__).resolve().parents[2]/'src/expansion/GF3HoneyTutorial.java'
    with TemporaryDirectory() as tmp:
        root=Path(tmp)
        stub=root/'a.java'
        stub.write_text('''class a {static int F,dW;static int[] bD,cb;static String[][] captions;static boolean redrawActors;
          static f c,selected; static e[] assets; static int a(){return 0;}
          static short[][][] controls; static void a(int gui,short[] item,int x,int y,int idx){}
          static boolean gf3HoneyInventory(int phase){return false;}
          static boolean gf3HoneyFarm(int e){return false;}static void a(f target,int x,int y){}
          static void a(String text,int portrait,int pose){} static void a(boolean v,f t){}static void a(int screen){}
          static int objective(int id,int count,int event,boolean flag){return 0;}
          static int g(int t,int n){return 0;}static boolean stock(int t,int p,int v){return false;}}
          class f {int r,s,D,K;static int a(int l,int t,int r,f[] f,int max){return 0;}
          static int a(int l,int t){return 0;}void a(int x,int y,int wait){}void h(int d){}}
          class k {static void f(){}}
          class g {static void open(String n){}static byte[] readEntry(int n){return null;}static void l(){}}
          class e {void a(byte[] d,int off){}}
          class h {static h[] tables;int[][] rows;}
          class GF3HomePredator {static int thief(){return 0;}
            static byte[] read(String n)throws java.io.IOException{return null;}
            static void write(String n,byte[] d)throws java.io.IOException{}}''',encoding='ascii')
        data=root/'GF3HoneyWords.java'
        cases=''.join(f'case {k}: return '+json.dumps(adapt(words[k]))+';' for k in range(12349,12358))
        data.write_text('class GF3HoneyWords {static String line(int id){switch(id){'+cases+
                        'default:throw new IllegalArgumentException();}}}',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(root),
                        str(data),str(stub),str(source)],check=True)
        cf=ClassFile((root/'GF3HoneyTutorial.class').read_bytes())
        for alias,real in {'assets':'a','tables':'a','rows':'a','captions':'a','controls':'a','selected':'d',
                           'open':'c','readEntry':'a','stock':'a','objective':'a','redrawActors':'l'}.items():
            cf.pool[cf.utf(alias)]=cf.pool[cf.utf(real)]
        result['GF3HoneyTutorial.class']=convert_helper(cf.bytes())
        result['GF3HoneyWords.class']=convert_helper((root/'GF3HoneyWords.class').read_bytes())
    return result
