"""Attach the offline Harold encounter to his existing MIDP farm and touch handler."""
import json
from pathlib import Path
import subprocess
import tempfile

from tools.timing.classfile import ClassFile, convert_helper, pack_code, u2
from tools.world import labels


def expose(cf, members, wanted):
    for index, (flags, name, desc, attrs) in enumerate(members):
        key = cf.string(name), cf.string(desc)
        if key in wanted:
            members[index] = flags & ~2, name, desc, attrs
            wanted.remove(key)
    if wanted:
        raise ValueError(f'Missing encounter accessors {wanted}')


def entry(cf, name, desc, alias, target, target_desc, load, owner='GF3Neighbor'):
    for i, (flags, n, d, attrs) in enumerate(cf.methods):
        if (cf.string(n), cf.string(d)) == (name, desc):
            cf.methods[i] = flags & ~2, cf.utf(alias), d, attrs
            code = load + b'\xb8' + u2(cf.ref(owner, target, target_desc)) + b'\xac'
            cf.methods.append((flags, n, d, [(cf.utf('Code'), pack_code(u2(1)+u2(1),code,u2(0),[]))]))
            return
    raise ValueError(f'Missing encounter entry {name}{desc}')


def patch_neighbor(game_data, actor_data, apk):
    game, actor = ClassFile(game_data), ClassFile(actor_data)
    expose(game, game.methods, {('aI','(I)V'),('a','(Lf;II)V'),('a','(Ljava/lang/String;II)V')})
    expose(game, game.fields, {('bD','[I'),('cb','[I'),('j','[Z')})
    expose(actor, actor.methods, {('L','()V'),('i','(II)V')})
    expose(actor, actor.fields, {('au','I'),('av','I')})
    entry(game,'F','(I)Z','gf3Visit','visit','(I)Z',b'\x1a')
    entry(actor,'h','()Z','gf3PetTouch','touch','(Lf;)Z',b'\x2a')
    typ = actor.intern(b'\x0c'+u2(actor.utf('a'))+u2(actor.utf('Ln;')))
    path = actor.intern(b'\x09'+u2(actor.cls('f'))+u2(typ))
    actor.methods.append((16, actor.utf('gf3Path'), actor.utf('()Ln;'), [(actor.utf('Code'),
        pack_code(u2(1)+u2(1), b'\x2a\xb4'+u2(path)+b'\xb0',u2(0),[]))]))
    source = Path(__file__).resolve().parents[2]/'src/expansion/GF3Neighbor.java'
    localized = labels(apk.read('assets/800x480/LATAM'))[978]
    with tempfile.TemporaryDirectory() as scratch:
        folder = Path(scratch)
        stubs = folder/'a.java'
        stubs.write_text("""class a {static int F; static int[] bD,cb; static boolean[] j; static e[] b;
          static f c; static int a(){return 0;} static void c(){} static void c(int sound){} static void aI(int n){}
          static boolean gf3Visit(int e){return false;} static void a(f x,int y,int z){}
          static void a(String s,int p,int q){} static int b(int x,int y,int z){return 0;}
          static void d(int[] grid,int[] world){}}
        class f {int J,D,r,s,A,B,u,v,au,av,h,i; k a,b; n gf3Path(){return null;} void i(int x,int y){}
          void L(){} void d(int x,int y){} boolean gf3PetTouch(){return false;} void i(int s){}
          static int a(int l,int t,int r,f[] out,int max){return 0;}
          void a(int x,int y,int duration){} void l(int flag){}}
        class GF3FarmAudio {static void original(int cue){}}
        class n {int a(){return 0;} int a(int i){return 0;} int b(int i){return 0;}}
        class e {} class k {k(e sheet,int u,int v){} void b(int animation,int repeats){} boolean a(){return false;}}""", encoding='ascii')
        strings=folder/'GF3NeighborText.java'
        strings.write_text('final class GF3NeighborText {static String win(){return '+
                           json.dumps(localized, ensure_ascii=True)+';}}',encoding='ascii')
        subprocess.run(['javac','--release','8','-g:none','-d',str(folder),str(stubs),
                        str(strings),str(source)], check=True)
        result = {n+'.class':convert_helper((folder/(n+'.class')).read_bytes())
                  for n in ('GF3Neighbor','GF3NeighborText')}
    return {'f.class':actor.bytes(),'a.class':game.bytes(),**result}
