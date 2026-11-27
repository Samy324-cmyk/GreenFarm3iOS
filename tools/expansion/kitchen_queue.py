"""Bind the second cooker to MIDP's real touch handler, UI and save system."""
import subprocess
import tempfile
from pathlib import Path

from tools.timing.classfile import ClassFile, code_parts, convert_helper, pack_code, u2


# Java source names for the duplicate-name/different-type CLDC field layout.
FIELDS = {
    'slots': ('dd', 'I'), 'count': ('df', 'I'), 'scroll': ('dg', 'I'),
    'ids': ('aj', '[I'), 'names': ('ak', '[I'), 'times': ('al', '[I'),
    'starts': ('b', '[J'), 'prices': ('am', '[I'), 'icons': ('an', '[I'),
    'phases': ('i', '[B'), 'starred': ('g', '[Z'), 'remaining': ('ao', '[I'),
    'captions': ('c', '[Ljava/lang/String;'), 'productIcons': ('d', '[S'),
    'drawerOpen': ('ax', 'Z'),
}


def field(cf, name, desc):
    typ = cf.intern(b'\x0c' + u2(cf.utf(name)) + u2(cf.utf(desc)))
    return cf.intern(b'\x09' + u2(cf.cls('a')) + u2(typ))


def compile_helper():
    root = Path(__file__).resolve().parents[2]
    types = {'I':'int', '[I':'int[]', '[J':'long[]', '[Z':'boolean[]',
             '[B':'byte[]', '[S':'short[]', '[Ljava/lang/String;':'String[]', 'Z':'boolean', '[Le;':'e[]'}
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        stub = directory/'a.java'
        graphics = directory/'Graphics.java'
        graphics.write_text('package javax.microedition.lcdui; public class Graphics {'
                            'public void setColor(int c) {}}', encoding='ascii')
        declarations = [f'static {types[desc]} {k};' for k,(_,desc) in FIELDS.items()]
        stub.write_text('import javax.microedition.lcdui.Graphics; class a {' + '\n'.join(declarations) +
                        'static void gd() {} static void C() {} static void a(int m) {} '
                        'static boolean gf3QueueScreen(int p){return false;} '
                        'static int g(int t,int i){return 0;} static void c(int s) {} '
                        'static void d(int t,int s) {} static boolean changeStock(int t,int p,int n){return false;} '
                        'static int objective(int r,int n,int t,boolean h){return 0;} '
                        'static int order(int r,int n,int t){return 0;} '
                        'static void a(String s,int x,int y,int w,int h,int v,int a,int f,int c,boolean b,boolean u) {} '
                        'static void p(int m) {}} '
                        'class GF3ExtractorUI {static boolean screen(int phase,boolean honey,boolean drawer){return false;}static void reset(){}} '
                        'class GF3HoneyTutorial {static void extracted(){}} '
                        'class h {static h[] tables; int[][] rows;} '
                        'class f {static int a(int g,int t,int r,f[] out,int n){return 0;}} '
                        'class g {static void a(String n,byte[] b) {} '
                        'static int K,L,ac,ad,ab; static Graphics graphics; '
                        'static void d(Graphics g,int x,int y,int w,int h,boolean rotate) {} '
                        'static byte[] a(String n){return null;} '
                        'static String c(int i){return null;}}', encoding='ascii')
        subprocess.run(['javac','--release','8','-g:none','-d',str(directory),str(stub),str(graphics),
                        str(root/'src/expansion/GF3HoneyKitchen.java'),
                        str(root/'src/expansion/GF3KitchenQueue.java')], check=True)
        cf = ClassFile((directory/'GF3KitchenQueue.class').read_bytes())
    remap = {('a', alias): actual for alias,(actual,_) in FIELDS.items()}
    remap.update({('h','tables'):'a', ('h','rows'):'a',
                  ('a','changeStock'):'a', ('a','objective'):'a', ('a','order'):'a'})
    for i, entry in enumerate(list(cf.pool)):
        if not entry or entry[0] not in (9,10):
            continue
        owner = cf.string(int.from_bytes(cf.pool[int.from_bytes(entry[1:3],'big')][1:], 'big'))
        typ = cf.pool[int.from_bytes(entry[3:5], 'big')]
        key = owner, cf.string(int.from_bytes(typ[1:3], 'big'))
        if key in remap:
            new = cf.intern(b'\x0c' + u2(cf.utf(remap.pop(key))) + typ[3:])
            cf.pool[i] = entry[:3] + u2(new)
    if remap:
        raise ValueError(f'Unbound cooking fields: {remap}')
    return convert_helper(cf.bytes())


def patch_kitchen_queue(engine, catalog_save):
    cf = ClassFile(engine)
    helper = 'GF3KitchenQueue'
    def call(owner, name, desc):
        return b'\xb8' + u2(cf.ref(owner, name, desc))

    edits = {
        # Farm dispatcher, actor type 50. Row 9 retains its existing menu;
        # row 28 enters the honey kitchen. The native tutorial gates precede it.
        'D(I)Z': [(2037, bytes.fromhex('1009a0000a1008') + call('a','a','(I)V'),
                  call(helper,'openBuilding','(I)Z') + bytes.fromhex('99000900000000')),
                 (334,call('a','C','()V'),call(helper,'resumeFarm','()V'))],
        'q(Z)V': [(1227,call('a','gd','()V'),call(helper,'newSession','()V'))],
        'dn()V': [(86,call('a','a','(I)V'),call(helper,'openNormal','(I)V'))],
        '<clinit>()V': [(2295,b'\x10\x0a',b'\x10\x14')],
        'm(I)I': [(4,b'\x07\x64\x2e',call(helper,'slotPrice','([II)I'))],
        'q(I)Z': [(2354,call('g','c','(I)Ljava/lang/String;'),
                   call(helper,'title','(I)Ljava/lang/String;'))],
        # Quest navigation receives the stable recipe ID from argument 1.
        'f(II)V': [(pc,b'\x10\x0b'+call('a','p','(I)V'),
                    b'\x1b'+call(helper,'openQuest','(I)V')+b'\x00') for pc in (411,469)],
    }
    serial = [(851,'slots','Slots'), (862,'slots','Slots'), (870,'phases','Phases'),
              (881,'starts','Starts'), (892,'times','Times'), (903,'ids','Ids'),
              (914,'starred','Starred')]
    edits['c(Z)V'] = []
    for pc, alias, getter in serial:
        name, desc = FIELDS[alias]
        edits['c(Z)V'].append((pc,b'\xb2'+u2(field(cf,name,desc)),call(helper,'normal'+getter,'()'+desc)))
    expose = set(FIELDS.values())
    for i,(flags, n, d, attrs) in enumerate(cf.fields):
        key = cf.string(n), cf.string(d)
        if key in expose:
            expose.remove(key)
            cf.fields[i] = flags & ~2,n,d,attrs
    if expose:
        raise ValueError(f'Missing native queue fields: {expose}')
    for i,(flags,n,d,attrs) in enumerate(cf.methods):
        key = cf.string(n) + cf.string(d)
        if key in ('gd()V','C()V','p(I)V','g(II)I','d(II)V','c(I)V'):
            cf.methods[i] = flags & ~2,n,d,attrs
        if key == 'q(I)Z':
            cf.methods[i] = flags & ~2,cf.utf('gf3QueueScreen'),d,attrs
        if key in edits:
            for j,(tag,body) in enumerate(attrs):
                if cf.string(tag) != 'Code':
                    continue
                header,ins,exc,extra = code_parts(body)
                code = bytearray(ins)
                for pc,old,new in edits.pop(key):
                    if len(old) != len(new) or code[pc:pc+len(old)] != old:
                        raise ValueError(f'Unsupported kitchen call site {key}+{pc}')
                    code[pc:pc+len(old)] = new
                attrs[j] = tag,pack_code(header,code,exc,extra)
    if edits:
        raise ValueError(f'Missing native kitchen methods: {edits.keys()}')
    body = b'\x1a'+call(helper,'screen','(I)Z')+b'\xac'
    cf.methods.append((10,cf.utf('q'),cf.utf('(I)Z'),[(cf.utf('Code'),
                       pack_code(u2(1)+u2(1),body,u2(0),[]))]))
    # Link the companion RMS AFTER stamping the catalog layout and unlink it
    # BEFORE migration. Original untagged files remain readable.
    save = ClassFile(catalog_save)
    for name,desc in [('read','(Ljava/lang/String;)[B'), ('write','(Ljava/lang/String;[B)V')]:
        old = save.ref('g','a',desc)
        new = save.ref(helper,name,desc)
        save.pool[old] = save.pool[new]
    return {'a.class':cf.bytes(), 'GF3CatalogSave.class':save.bytes(),
            'GF3KitchenQueue.class':compile_helper()}
