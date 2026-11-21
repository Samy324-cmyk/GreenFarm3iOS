"""Use the existing tree save format for the Android hive states and touch actions."""
from pathlib import Path
import subprocess
import tempfile

from tools.timing.classfile import ClassFile, code_parts, convert_helper, pack_code, u2

SOURCE = Path(__file__).resolve().parents[2] / 'src/expansion/GF3Hive.java'


def encoded_call(cf, name, desc):
    return b'\xb8' + u2(cf.ref('GF3Hive', name, desc))


def wrap(cf, key, original, helper, helper_desc, load, end, stack, locals_count):
    for index, (flags, n, d, attrs) in enumerate(cf.methods):
        if (cf.string(n), cf.string(d)) != key:
            continue
        cf.methods[index] = flags, cf.utf(original), d, attrs
        code = load + encoded_call(cf, helper, helper_desc) + end
        cf.methods.append((flags, n, d, [(cf.utf('Code'),
            pack_code(u2(stack)+u2(locals_count), code, u2(0), []))]))
        return
    raise ValueError(f'Missing actor entry {key}')


def patch_code(cf, name, desc, edits):
    for _, n, d, attributes in cf.methods:
        if (cf.string(n),cf.string(d)) != (name,desc):
            continue
        for i,(key,body) in enumerate(attributes):
            if cf.string(key) != 'Code':
                continue
            header,raw,exceptions,extras = code_parts(body)
            code = bytearray(raw)
            for start,old,new in edits:
                if code[start:start + len(old)] != old or len(new) > len(old):
                    raise ValueError(f'Unexpected code in {name}{desc} at {start}')
                code[start:start+len(old)] = new.ljust(len(old), b'\0')
            attributes[i] = key,pack_code(header,code,exceptions,extras)
            return
    raise ValueError(f'Missing {name}{desc}')


def patch_hives(a_class, f_class, javac='javac'):
    """Return the two modified engine classes and the CLDC helper."""
    actor, game = ClassFile(f_class), ClassFile(a_class)
    for index,(flags,n,d,attributes) in enumerate(actor.fields):
        if actor.string(n) == 'as' and actor.string(d) == 'I':
            actor.fields[index] = flags & ~2,n,d,attributes
            break
    else:
        raise ValueError('Missing actor footprint area')

    # The actor holds the static hive base in E/F while its optional k animator
    # draws the bee swarm over it when ready. On reload enter the same state API.
    wrap(actor, ('h','(I)V'), 'gf3TreeState', 'state','(Lf;I)V',
         bytes.fromhex('2a1b'), b'\xb1', 2, 2)
    wrap(actor, ('f','()Z'), 'gf3TouchTree', 'touch','(Lf;)Z',
         b'\x2a', b'\xac', 1, 1)
    wrap(actor, ('t','()V'), 'gf3AnimalCare', 'clean','(Lf;)V',
         b'\x2a', b'\xb1', 1, 1)
    native_factory = actor.ref('f','gf3Factory','(II[I)Lf;')
    wrap(actor, ('a','(II[I)Lf;'), 'gf3Factory', 'configure','(Lf;)Lf;',
         bytes.fromhex('1a1b2cb8') + u2(native_factory), b'\xb0', 3, 3)

    # Retain the native bubble link/replacement semantics and private field.
    link = b'\x2a\x2b\xb7' + u2(actor.ref('f','a','(Lf;)V')) + b'\xb1'
    actor.methods.append((16,actor.utf('gf3Link'),actor.utf('(Lf;)V'),[(actor.utf('Code'),
        pack_code(u2(2)+u2(2),link,u2(0),[]))]))

    def call(name,desc): return encoded_call(actor,name,desc)
    patch_code(actor,'g','()Z',[(23,bytes.fromhex('102fb80129'),
        b'\x2a'+call('progressSound','(Lf;)V'))])
    patch_code(actor, 'a','()V', [(4984,bytes.fromhex('b4007f'),call('tickState','(Lf;)I'))])
    patch_code(actor, 'p','()V', [(2,bytes.fromhex('b6017a'),call('afterHarvest','(Lf;I)V'))])
    patch_code(actor, 'a','(Z)V', [
        (99,bytes.fromhex('0436051b990006063605'),
         b'\x2a\x1b'+call('yieldOrSingle','(Lf;Z)I')+bytes.fromhex('3605')),
        (153,bytes.fromhex('b40085'),call('harvestId','(Lf;)I'))])
    # The legacy source combines two inventory counts then adds three. The
    # same additions fit in-place by exposing wrappers (JVM PC maps stay valid).
    for name,desc,body,stack in [
        ('gf3LooseStorage','()I',bytes.fromhex('08b8011c05b8015f60ac'),2),
        ('gf3QueuedStorage','()I',bytes.fromhex('08b8011cb2007160ac'),2)]:
        actor.methods.append((8,actor.utf(name),actor.utf(desc),[(actor.utf('Code'),
            pack_code(u2(stack)+u2(0),body,u2(0),[]))]))
    patch_code(actor,'gf3TouchTree','()Z',[
        (29,bytes.fromhex('08b8011c05b8015f600660'),
         b'\xb8'+u2(actor.ref('f','gf3LooseStorage','()I'))+b'\x2a'+call('baseYield','(Lf;)I')+b'\x60'),
        (52,bytes.fromhex('08b8011cb20071600660'),
         b'\xb8'+u2(actor.ref('f','gf3QueuedStorage','()I'))+b'\x2a'+call('baseYield','(Lf;)I')+b'\x60')])
    # Closing the farm finalizes pending flying rewards. The stock path only
    # recognized the original 26 produce IDs and silently discarded honeycomb.
    patch_code(actor,'d','()V',[(142,bytes.fromhex('1b04a100101b101aa3000a'),
         b'\x1b'+call('flushItem','(I)Z')+bytes.fromhex('99000e'))])
    patch_code(game,'r','(II)V',[(518,bytes.fromhex('10062e'),encoded_call(game,'price','([I)I'))])
    alias = bytes.fromhex('1a1bb8') + u2(game.ref('a','g','(II)I')) + b'\xac'
    game.methods.append((8,game.utf('gf3Stored'),game.utf('(II)I'),[(game.utf('Code'),
        pack_code(u2(2)+u2(2),alias,u2(0),[]))]))
    # The same capacity check runs when the farmer actually reaches the hive.
    patch_code(game,'gm','()V',[
        (526,bytes.fromhex('06b20126b203dd32110400b60789'),
         bytes.fromhex('b20126b203dd32')+encoded_call(game,'requiredSlots','(Lf;)I')+b'\x03')])

    with tempfile.TemporaryDirectory() as temp:
        folder = Path(temp)
        stub = folder/'f.java'
        stub.write_text("""class f { int q,E,F,w,x,as,r,s,u,v,D,I,J; k a;
        void gf3TreeState(int s){} void gf3AnimalCare(){} boolean gf3TouchTree(){return false;}
        void gf3Link(f x){} void h(int s){} void H(){} boolean a(int flag){return false;}
        static int b(int layer,int id){return 0;} static f a(int t,int layer,int[] data){return null;} }
        class e {}
        class GF3FarmAudio {static void original(int cue){}}
        class GF3HoneyTutorial { static void harvest(int producer,int combs){}
            static boolean requestSmoke(){return true;}static boolean canSmoke(){return true;} }
        class k {k(e s,int x,int y){} void b(int a,int n){} boolean a(){return false;}}
        class a {static int F; static int gf3Stored(int t,int id){return 0;} static e[] b; static void a(int type,f actor){} static void c(int n){}}""", encoding='ascii')
        subprocess.run([javac,'--release','8','-g:none','-d',str(folder),str(stub),str(SOURCE)],check=True)
        bridge = convert_helper((folder/'GF3Hive.class').read_bytes())
    return {'a.class':game.bytes(), 'f.class':actor.bytes(),'GF3Hive.class':bridge}
