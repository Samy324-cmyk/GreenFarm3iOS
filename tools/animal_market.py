"""Install the catalog artwork and animal-category hooks in native MIDP code."""
from pathlib import Path
import subprocess
import tempfile
from .timing.classfile import ClassFile, code_parts, convert_helper, instruction_offsets, pack_code, u2
from .catalog_ext import reserve_constants


def patch_market(data, sound_class):
    cf = ClassFile(data)
    constants=reserve_constants(cf,(150,163))
    count = bytes((0x12,constants[163]))
    # The original factory leaves the actor and its selected feed index on
    # the stack before writing f.a:S. Keep the same consumption and CLDC PCs.
    feed = cf.ref('GF3AnimalMarket','feed','(Lf;I)V')
    newart = cf.ref('GF3AnimalMarket','worldArt','(IIIIIII)V')
    native_art = cf.ref('a','a','(IIIIIII)V')
    queue = cf.ref('a','e','(II)V')
    pet_queue = cf.ref('GF3AnimalMarket','preloadSounds','(II)V')
    alt = cf.ref('GF3AnimalMarket','alternate','(I)I')
    edits = {
        'a(II)Lf;': [(698,b'\xb5\x04\x1e',b'\xb8'+u2(feed))],
        'x()V': [(1334,b'\xb8'+u2(native_art),b'\xb8'+u2(newart)),
                 (3947,b'\xb8'+u2(queue),b'\xb8'+u2(pet_queue))],
        # The original 5-entry animal menu had an unused sixth button
        # which opens category four twice. The APK's sixth species is Dogs.
        'J()V': [(26,b'\x07\xb8\x07\x22',b'\x08\xb8\x07\x22')],
        '<clinit>()V': [(603,b'\x10\x43',bytes((0x12,constants[150])))],
        'c(IIZ)V': [(150,b'\x10\x34\x60',b'\xb8'+u2(alt))],
        'q(Z)V': [(1569,b'\x10\x77',count)],
        'g(I)I': [(1,b'\x10\x77',count)],
        't()I': [(5,b'\x10\x77',count)],
    }
    for i,(flags,n,d,attrs) in enumerate(cf.fields):
        if (cf.string(n),cf.string(d))==('d','[[I'):
            cf.fields[i] = flags & ~2,n,d,attrs
    for i,(flags,n,d,attrs) in enumerate(cf.methods):
        method = cf.string(n)+cf.string(d)
        if method=='e(II)V':
            cf.methods[i] = flags & ~2,n,d,attrs
        if method not in edits:
            continue
        for ati,(tag,body) in enumerate(attrs):
            if cf.string(tag) != 'Code':
                continue
            header,ins,ex,extra = code_parts(body)
            code=bytearray(ins)
            for pc,old,new in edits.pop(method):
                if ins[pc:pc+len(old)]!=old:
                    raise ValueError(f'Unsupported market hook at {method}/{pc}')
                code[pc:pc+len(old)]=new
            attrs[ati] = tag,pack_code(header,code,ex,extra)
    if edits:
        raise ValueError('Missing native market hook')
    source = Path(__file__).resolve().parents[1]/'src/catalog/GF3AnimalMarket.java'
    with tempfile.TemporaryDirectory() as temp:
        folder = Path(temp)
        stub = folder/'a.java'
        stub.write_text('class a {static int[][] d;static void e(int sound,int f){} '
                        'static void a(int g,int s,int p,int a,int f,int m,int n){}} '
                        'class h {static h[] a; int b;} class f {int E;short a;} '
                        'class e {int a(){return 0;} int a(int anim){return 0;}}',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),
                        str(stub),str(source)],check=True)
        helper = convert_helper((folder/'GF3AnimalMarket.class').read_bytes())
    sound = ClassFile(sound_class)
    count = bytes((0x12,reserve_constants(sound,(163,))[163]))
    changed = 0
    for _,n,d,attrs in sound.methods:
        for index,(tag,body) in enumerate(attrs):
            if sound.string(tag)!='Code':
                continue
            head,code,ex,extra=code_parts(body)
            for pc in instruction_offsets(code):
                # One duplicated constant initializes both player slots and
                # the byte[][] payload cache in the native startup routine.
                if code[pc:pc+7]==bytes.fromhex('107759b3006ebd'):
                    code=code[:pc]+count+code[pc+2:]
                    attrs[index]=tag,pack_code(head,code,ex,extra)
                    changed+=1
    if changed!=1:
        raise ValueError('Unexpected MMAPI player allocation')
    return {'a.class':cf.bytes(),'k.class':sound.bytes(),'GF3AnimalMarket.class':helper}


def patch_decor_factory(data):
    """Select static art when animation zero has an empty frame list."""
    actor = ClassFile(data)
    native = b'\xb6'+u2(actor.ref('e','a','()I'))
    target = b'\xb8'+u2(actor.ref('GF3AnimalMarket','decorFrames','(Le;)I'))
    matches = 0
    for _,name,desc,attrs in actor.methods:
        if actor.string(name) not in ('a','gf3Factory') or actor.string(desc)!='(II[I)Lf;':
            continue
        for i,(tag,body) in enumerate(attrs):
            if actor.string(tag)!='Code':
                continue
            head,code,exceptions,extra = code_parts(body)
            if code[967:970]==native:
                attrs[i]=tag,pack_code(head,code[:967]+target+code[970:],exceptions,extra)
                matches+=1
    if matches!=1:
        raise ValueError('Unexpected decoration animation factory')
    return actor.bytes()
