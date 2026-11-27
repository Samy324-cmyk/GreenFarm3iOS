"""Connect Android tutorial 1026–1038 to the real shop, doghouse, journal and pet."""
import json
from pathlib import Path
import subprocess
import tempfile

from .neighbor import entry, expose
from tools.timing.classfile import ClassFile, convert_helper
from tools.world import labels


def patch_dog_tutorial(classes,apk):
    game=ClassFile(classes['a.class'])
    toys=ClassFile(classes['GF3DogToys.class'])
    expose(game,game.methods,{('a','(IZZ)V'),('a','(IIZ)V'),('J','(I)V')})
    expose(game,game.fields,{('c','C')})
    expose(game,game.fields,{(letter,'[I') for letter in 'LMNOPQRSTUVW'}|{('f','[Z')})
    for native,prior,handler in [('D','gf3DogLessonsFarm','farm'),('o','gf3DogLessonsShop','shop')]:
        entry(game,native,'(I)Z',prior,handler,'(I)Z',b'\x1a','GF3DogTutorial')
    for name,desc in [('pack','([B)[B'),('unpack','([B)[B'),('reset','()V')]:
        toys.pool[toys.ref('GF3PetNames',name,desc)]=toys.pool[toys.ref('GF3DogTutorial',name,desc)]
    texts=labels(apk.read('assets/800x480/LATAM'))
    path=Path(__file__).resolve().parents[2]/'src/expansion/GF3DogTutorial.java'
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        data=folder/'GF3DogLines.java'
        data.write_text('final class GF3DogLines {static final String FREE='+json.dumps(texts[407])+';'
                        'static final String[] TEXT={'+
                        ','.join(json.dumps(texts[i],ensure_ascii=True) for i in range(967,973))+'};}',
                        encoding='ascii')
        stub=folder/'a.java'
        stub.write_text('''class a {
            static int[] bD,cb,L,M,N,O,P,Q,R,S,T,U,V,W,k;static boolean[] locked;
            static char count;static int ct,cu,F,B,transition;static f c;static e[] art;
            static boolean gf3DogLessonsFarm(int event){return false;}
            static boolean gf3DogLessonsShop(int event){return false;}
            static int a(){return 0;}static boolean h(int id){return false;}static void c(){}static int b(int id,int n,int action){return 0;}
            static void a(String s,int p,int c){} static void a(f x,int a,int b){}
            static void a(String s,int gui,int row,int x,int y){}static void visible(int gui,int row,boolean show){}
            static void d(int tab,int group,boolean push){}static void r(int tab,int index){}static void card(int pos,boolean show,boolean cat){}
            static void gf(){}static void H(int group){}static void J(int slide){}
        } class f {int r,s,q,E,u,v;k a;void a(int x,int y,int time){}boolean a(int flag){return false;}boolean h(){return false;}}
        class g {static int ab,ac,ad;}class k{int flags;int clip(){return 0;}int frame(){return 0;}}
        class e {void a(int[] box,int clip,int frame,int x,int y,int flags){}}
        class GF3Doghouse {static f placed(f excluding){return null;}static f resident(f pet){return null;}}
        class GF3Dogs {static int level(f pet){return 0;}}
        class GF3DogToys {static long nextBonus;}
        class GF3PetNames {static void reset(){}static byte[] pack(byte[] b){return b;}
            static byte[] unpack(byte[] b)throws java.io.IOException{return b;}}
        class GF3HomePredator {static void trained(){}}''',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),
                        str(stub),str(path),str(data)],check=True)
        helper=ClassFile((folder/'GF3DogTutorial.class').read_bytes())
        for alias,real in [('count','c'),('transition','af'),('card','a'),('locked','f'),('visible','a'),
                           ('art','b'),('clip','a'),('frame','b'),('flags','a')]:
            helper.pool[helper.utf(alias)]=helper.pool[helper.utf(real)]
        return {'a.class': game.bytes(),'GF3DogToys.class':toys.bytes(),
                'GF3DogTutorial.class':convert_helper(helper.bytes()),
                'GF3DogLines.class':convert_helper((folder/'GF3DogLines.class').read_bytes())}
