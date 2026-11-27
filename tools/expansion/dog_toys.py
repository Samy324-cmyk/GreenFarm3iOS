"""Attach the Android dog-toy selector to the corresponding MIDP shop and ribbon."""
import subprocess
import tempfile
from pathlib import Path
from tools.timing.classfile import ClassFile, convert_helper, pack_code, u2
from .hives import patch_code


def patch_toys(a_class,f_class,save_class,javac='javac'):
    a,f,save = ClassFile(a_class),ClassFile(f_class),ClassFile(save_class)
    names = {('M','[I'),('Q','[I'),('R','[I'),('f','[Z'),('ct','I'),('cu','I'),
             ('k','[I'),('l','[I'),('m','[I'),('n','[I'),('aF','I'),('aG','I'),('aH','I'),
             ('a','[[[S'),('a','[Le;'),('b','[Le;'),('i','[[I')}
    for i,(flags,n,d,attrs) in enumerate(a.fields):
        key = a.string(n),a.string(d)
        if key in names:
            a.fields[i] = flags&~2,n,d,attrs
            names.remove(key)
    if names: raise ValueError(f'Missing selector fields {names}')
    for i,(flags,n,d,attrs) in enumerate(a.methods):
        if a.string(n)=='B' and a.string(d)=='()V':
            a.methods[i] = flags&~2,n,d,attrs
            break
    else: raise ValueError('Missing touch ribbon refresh')
    # B() always emits the old tool sound even on a pet ribbon.
    patch_code(a,'B','()V',[(2,b'\xb8'+u2(a.ref('a','c','(I)V')),b'\xb8'+u2(a.ref('GF3DogToys','wheelSound','(I)V')))])
    for cf, key, original, handler, desc, load, ret in [
        (a,('af','(I)V'),'gf3PreviousBuy','buy','(I)V',b'\x1a',b'\xb1'),
        (a,('I','(I)V'),'gf3PreviousControl','control','(I)V',b'\x1a',b'\xb1'),
        (f,('h','()Z'),'gf3PreviousPetTouch','touch','(Lf;)Z',b'\x2a',b'\xac')]:
        for i,(flags,n,d,attrs) in enumerate(cf.methods):
            if (cf.string(n),cf.string(d)) != key: continue
            cf.methods[i] = flags&~2,cf.utf(original),d,attrs
            code=load+b'\xb8'+u2(cf.ref('GF3DogToys',handler,desc))+ret
            cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(1)+u2(1),code,u2(0),[]))]))
            break
        else: raise ValueError(f'Missing dog market hook {key}')

    # This is the actor-type switch after advancing the visible animation.
    patch_code(f,'a','()V',[(44,bytes.fromhex('b400e4'),
        b'\xb8'+u2(f.ref('GF3DogToys','tick','(Lf;)I')))])
    for n,d in [('write','(Ljava/lang/String;[B)V'),('read','(Ljava/lang/String;)[B')]:
        oldref = save.ref('GF3KitchenQueue',n,d)
        old=save.pool[oldref]
        new=save.pool[save.ref('GF3DogToys',n,d)]
        for i,ref in enumerate(save.pool):
            if ref == old: save.pool[i] = new
    source = Path(__file__).resolve().parents[2]/'src/expansion/GF3DogToys.java'
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        stub=folder/'a.java'
        stub.write_text("""class a {
          static int ct,cu,aF,aG,aH,F; static int[] M,Q,R,k,l,m,n;static boolean[] f;
          static short[][][] controls;static e[] assets,world;static int[][] hits;
          static int screen(){return 0;}static void clearTool(int id){} static void sound(int id){} static void gf3PreviousBuy(int b){} static boolean c(int n){return false;}
          static boolean f(int n){return false;} static int f(){return 0;}
          static void a(boolean b,int mode,int slot){} static void a(boolean b,f pet){} static void B(){} static void gf(){} static void H(int panel){} static void gf3PreviousControl(int e){}
          static int b(int id,int q,int ac){return 0;} }
          class k {e sprite(){return null;}void b(int an,int reps){} int aId(){return 0;}int frameNumber(){return 0;}boolean a(){return false;}}
          class GF3FarmAudio {static void original(int cue){}}
          class f {int q,J,r,s,D,u,v; k a; boolean a(int fl){return false;} void i(int n){}
          boolean gf3PreviousPetTouch(){return false;} static f a(int t,int l,int[] p){return null;}
          void a(int x,int y,int t,int delay,boolean collect,int n){}}
          class h {static h[] a;int[][] rows;}
          class g {static int K;} class e {int f(int n){return 0;}int g(int n){return 0;}
              int d(int n){return 0;}int e(int n){return 0;}int a(int clip){return 0;}int animations(){return 0;}int frames(){return 0;}}
          class GF3Dogs { static boolean dog(f x){return false;} static void normalize(f x){}static void clearMood(f x){}static void refreshMood(f x){} static void beginToy(f x,int n){}
          static int pending(f x){return 0;} static void cancelToy(f x){} static void finishToy(f x,int xp,int mood){}}
          class GF3DogTutorial {static void played(){}static void bought(int toy){}}
          class GF3PetNames {static boolean unavailable(int row){return false;}
          static boolean houseUnavailable(int row){return false;}static void collar(int slot,int button){}static void farmTick(f pet){}
          static void reset(){}static byte[] pack(byte[] b){return b;}
          static byte[] unpack(byte[] b)throws java.io.IOException{return b;}}
          class GF3KitchenQueue {static void write(String s,byte[] b)throws java.io.IOException{}
          static byte[] read(String name)throws java.io.IOException{return null;}}""",encoding='ascii')
        subprocess.run([javac,'--release','8','-g:none','-d',str(folder),str(source),str(stub)],check=True)
        helper=ClassFile((folder/'GF3DogToys.class').read_bytes())
        # The original bytecode distinguishes these members by return/field type.
        for old,real in (('screen','a'),('clearTool','e'),('rows','a'),('sprite','a'),('animations','a'),('frames','b'),('aId','a'),('frameNumber','b'),('sound','c'),('controls','a'),('assets','a'),('world','b'),('hits','i')):
            helper.pool[helper.utf(old)] = helper.pool[helper.utf(real)]
        cooked=convert_helper(helper.bytes())
    return {'a.class':a.bytes(),'f.class':f.bytes(),'GF3CatalogSave.class':save.bytes(),'GF3DogToys.class':cooked}
