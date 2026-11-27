"""Translate the twelve offline deed contracts used by the story campaign."""
from .catalog_ext import encode_table
from .world import table
from .expansion.hives import patch_code
from .timing.classfile import ClassFile, convert_helper, pack_code, u2
from pathlib import Path
import subprocess
import tempfile


def build_deeds(reference_blob, android_blob):
    reference = table(reference_blob)[1]
    android = table(android_blob)[1]
    if len(reference) != 12 or len(android) != len(reference):
        raise ValueError('Unknown number of farm deeds')
    rows = []
    for number, (old, new) in enumerate(zip(reference, android), 1):
        # MIDP a.fV() reads price, two required items, counts and optional
        # premium alternatives in columns 2–10. Android adds a telemetry ID
        # after the last fee. Both editions use the same stable item IDs.
        if (len(old) != 11 or len(new) != 12 or old[:2] != (number-1, number)
                or old[:2] != new[:2] or old[3:] != new[3:11]):
            raise ValueError(f'Unknown item requirements for deed {number}')
        rows.append(new[:11])
    return encode_table(reference_blob, rows)


def build_achievements(reference_blob, android_blob):
    reference, android = table(reference_blob)[1], table(android_blob)[1]
    if len(reference) != 20 or len(android) != 20:
        raise ValueError('Unknown trophy catalog')
    rows = []
    for old, new in zip(reference, android):
        if old[:3] != new[:3] or old[7:10] != new[7:10]:
            raise ValueError('Unmapped trophy ID or objective')
        # The shared goal and title already use the localized MIDP string
        # indices. Last trophy awards 50,000 XP, larger than signed int16.
        rows.append((*old[:10],*new[10:14]))
    return encode_table(reference_blob, rows)


def patch_flock(game_class, actor_class):
    game, actor = ClassFile(game_class), ClassFile(actor_class)
    def invoke(cf, name, desc):
        return b'\xb8'+u2(cf.ref('GF3Flock',name,desc))

    def field(name, desc):
        kind = game.intern(b'\x0c'+u2(game.utf(name))+u2(game.utf(desc)))
        return u2(game.intern(b'\x09'+u2(game.cls('h'))+u2(kind)))

    tag = game.utf('Code')
    rows = b'\xb2'+field('a','[Lh;')+b'\x03\x32\xb4'+field('a','[[I')+b'\xb0'
    game.methods.append((8,game.utf('gf3AnimalRows'),game.utf('()[[I'),[
        (tag,pack_code(u2(2)+u2(0),rows,u2(0),[]))]))
    for i,(flags,n,d,_) in enumerate(game.methods):
        if (game.string(n),game.string(d)) == ('w','()I'):
            game.methods[i] = flags,n,d,[(tag,pack_code(u2(1)+u2(0),
                                     invoke(game,'distinct','()I')+b'\xac',u2(0),[]))]
            break
    else:
        raise ValueError('Cannot locate native trophy species check')

    # At both sites the actor was already tested for ownership (flag 512).
    # Android s1.A excludes young and special hidden actors. Its separate
    # prize check s1.z excludes young actors and requires flag 2048.
    modulo = bytes.fromhex('b400ef057004')
    patch_code(actor,'a','(IIII)I',[(32,modulo,invoke(actor,'countable','(Lf;)Z')+b'\x04')])
    young = b'\x10\x20\xb6'+u2(actor.ref('f','a','(I)Z'))+b'\x03'
    patch_code(actor,'d','(II)I',[(32,modulo,young)])
    # Native trophy events receive an item ID. APK accepts any owned adult
    # species and recomputes distinct species on every animal acquisition.
    patch_code(game,'a','(III)I',[
        (67,bytes.fromhex('057004'),invoke(game,'adult','(I)Z')),
        (70,bytes.fromhex('a002c3'),bytes.fromhex('9902c3')),
        (525,bytes.fromhex('1a057004a000f8'),b'')])
    patch_code(game,'a','(Z)V',[(190,b'\x10\x3f',b'\x10\x4b')])
    patch_code(game,'l','(I)V',[
        (185,b'\xb8'+u2(game.ref('f','a','(IIII)I')),invoke(game,'pigs','(IIII)I')),
        (377,b'\x10\x3f',b'\x10\x4b')])
    source = Path(__file__).resolve().parents[1]/'src/catalog/GF3Flock.java'
    with tempfile.TemporaryDirectory() as temp:
        folder = Path(temp)
        stub = folder/'a.java'
        stub.write_text('class a {static int[][] gf3AnimalRows(){return null;}} '
                        'class f {boolean a(int flag){return false;} '
                        'static int a(int l,int t,int first,int last){return 0;}}',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),str(stub),str(source)],check=True)
        helper = convert_helper((folder/'GF3Flock.class').read_bytes())
    return {'a.class':game.bytes(), 'f.class':actor.bytes(), 'GF3Flock.class':helper}
