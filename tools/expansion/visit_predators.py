"""Bind Android's optional repeatable predator requests to the offline neighbors."""
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from tools.timing.classfile import ClassFile, convert_helper
from tools.world import entries, labels, pack, table
from .neighbor import entry, expose


def _controls(data,android):
    pos=1
    result=[]
    while pos<len(data):
        size={204:26,205:31}[data[pos]]+int(android)
        result.append(data[pos:pos+size])
        pos+=size
    if pos!=len(data): raise ValueError('Truncated mailbox interface')
    return result


def _mailbox(data,apk):
    panels=entries(data)
    local=_controls(panels[17],False)
    source=_controls(entries(apk.read('assets/800x480/10'))[17],True)
    if len(local)!=51 or len(source)!=59:
        raise ValueError('Unrecognized mailbox interface')
    for raw in source[48:55]:
        ctl=bytearray(raw)
        if ctl[0]==204:
            del ctl[-1]
        else:
            if ctl[8] not in (1,20) or ctl[10]!=0: raise ValueError('Unknown predator artwork')
            del ctl[10]
        local.append(ctl)
    panels[17]=panels[17][:1]+b''.join(local)
    return pack(panels)


def patch_visit_predators(classes,apk):
    game,actor,save=[ClassFile(classes[key+'.class']) for key in ('a','f','GF3CatalogSave')]
    expose(game,game.methods,{('n','(II)V'),('cO','()V'),('cQ','()V'),('c','(Z)V'),
                             ('a','(I[SIII)V'),('a','(Ljava/lang/String;IIII)V')})
    expose(game,game.fields,{('eS','I'),('e','[[I'),('a','[[[S'),('a','[Le;')})
    owner='GF3VisitPredators'
    entry(game,'H','(I)Z','gf3VisitDetail','detail','(I)Z',b'\x1a',owner)
    entry(game,'F','(I)Z','gf3VisitFarm','visit','(I)Z',b'\x1a',owner)
    entry(actor,'h','()Z','gf3VisitPetTouch','touch','(Lf;)Z',b'\x2a',owner)
    for name,desc in [('read','(Ljava/lang/String;)[B'),('write','(Ljava/lang/String;[B)V')]:
        save.pool[save.ref('GF3DogToys',name,desc)]=save.pool[save.ref('GF3VisitPredators',name,desc)]
    source=Path(__file__).resolve().parents[2]/'src/expansion/GF3VisitPredators.java'
    words=labels(apk.read('assets/800x480/LATAM'))
    definitions={'yes':30,'no':31,'offer':933,'empty':12332}
    animal_rows=table(entries(apk.read('assets/800x480/13'))[0])[1]
    rewards=[v for row in animal_rows[68:76] for v in row[55:59]]
    with TemporaryDirectory() as temp:
        work=Path(temp)
        strings=work/'GF3VisitText.java'
        strings.write_text('class GF3VisitText {'+''.join(
            'static String '+key+'='+json.dumps(words[idx],ensure_ascii=True)+';' for key,idx in definitions.items()
            )+'static int[] rewards={'+','.join(map(str,rewards))+'};}',encoding='ascii')
        stub=work/'a.java'
        stub.write_text("""class a {
          static int F,eS;static int[][] e;static int[] d;static e[] b,assets;static short[][][] controls;static f c;
          static boolean i(int r){return false;}static boolean h(int n){return false;}
          static void c(int n){}static void c(){}static void c(boolean s){}
          static int a(){return 0;}static int b(int id,int n,int ev){return 0;}
          static boolean gf3VisitDetail(int p){return false;}static boolean gf3VisitFarm(int p){return false;}
          static void a(String s,int gui,int i,int x,int y){}static void a(int gui,short[] c,int x,int y,int i){}
          static void a(String s,int a,int b){}static void cO(){}static void cQ(){}static void aI(int n){}static void n(int r,int n){}
        } class g {static int ac,ad,ab;}
          class f {static int a(int l,int t,int r,f[] out,int max){return 0;}
          static f a(int t,int l,int[] p){return null;} void a(int x,int y,int t,int delay,boolean collect,int n){}
          int D,r,s,A,B,u,v,au,av,h,i,E,F,J; k a,b;void i(int v){}void L(){}void l(int n){}void k(int n){}
          void a(int x,int y,int d){}boolean a(int flag){return false;}boolean gf3VisitPetTouch(){return false;}}
          class k {k(e sheet,int x,int y){}void b(int a,int r){}boolean a(){return false;}}
          class e {void a(int frame,int part,int[] rect,int offset){}}
          class GF3Neighbor {static f animal(int row){return null;}static void hold(f pet,int a,int r){}
                             static void approach(f pet,f target){}static k startFight(f pet,f target){return null;}}
          class GF3Dogs {static int level(f pet){return 0;}}
          class GF3FarmAudio {static void original(int cue){}}
          class GF3DogToys {static byte[] read(String s)throws java.io.IOException{return null;}
                             static void write(String s,byte[] b)throws java.io.IOException{}}""",encoding='ascii')
        subprocess.run(['javac','--release','8','-g:none','-d',str(work),str(stub),str(strings),str(source)],
                       check=True)
        helper=ClassFile((work/'GF3VisitPredators.class').read_bytes())
        for member in ('controls','assets'):
            helper.pool[helper.utf(member)]=helper.pool[helper.utf('a')]
        text=convert_helper((work/'GF3VisitText.class').read_bytes())
    return {'a.class':game.bytes(),'f.class':actor.bytes(),
            'GF3CatalogSave.class':save.bytes(),'GF3VisitPredators.class':convert_helper(helper.bytes()),
            'GF3VisitText.class':text,'6':_mailbox(classes['6'],apk)}
