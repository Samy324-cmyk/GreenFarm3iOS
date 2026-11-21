"""Translate Android's doghouse layout and bind it to MIDP state 48."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

from tools.sprites import convert_sprite, shards
from tools.timing.classfile import ClassFile, convert_helper, pack_code, u2
from tools.world import entries, labels, pack, table
from .hives import patch_code

SHEETS = (1, 3, 9, 20, 22, 33, 41, 48)
BASE = 150


def convert_layout(raw, expected):
    out, index, pos = bytearray(raw[:1]), 0, 1
    while pos < len(raw):
        kind = raw[pos]
        if kind not in (204,205):
            raise ValueError(f'Unexpected doghouse control {kind}')
        count = 27 if kind == 204 else 32
        control = bytearray(raw[pos:pos+count])
        if kind == 204:
            # Android added a final text-style flag after the legacy 18 fields.
            del control[-1]
        else:
            sheet = control[8]
            frame, = struct.unpack_from('<h', control, 9)
            if sheet not in SHEETS or not 0 <= frame < 255:
                raise ValueError(f'Unexpected sprite {sheet}/{frame} at control {index}')
            control[8] = BASE + SHEETS.index(sheet)
            del control[10]  # MIDP's frame field is one byte.
        out.extend(control)
        index += 1
        pos += count
    if index!=expected or pos!=len(raw):
        raise ValueError('Unexpected doghouse layout')
    return bytes(out)


def layout(original, apk):
    groups=entries(original)
    if len(groups)!=28: raise ValueError('Unexpected MIDP UI count')
    mobile=entries(apk.read('assets/800x480/10'))
    return pack([*groups,convert_layout(mobile[30],80),convert_layout(mobile[31],69)])


def name_filter(apk):
    """Read Android's name-filter initializer and resolve its DEX string IDs."""
    dex=apk.read('classes.dex')
    string_ids,=struct.unpack_from('<I',dex,0x3c)
    pos=0x471d80
    terms=[]
    widths={0x12:2,0x13:4,0x1a:4,0x4d:4}
    while len(terms)<244:
        opcode=dex[pos]
        if opcode not in widths: raise ValueError('Unknown dog-name initializer')
        if opcode==0x1a:
            index,=struct.unpack_from('<H',dex,pos+2)
            start,=struct.unpack_from('<I',dex,string_ids+4*index)
            while dex[start]&128: start+=1
            terms.append(dex[start+1:dex.index(0,start+1)])
        pos+=widths[opcode]
    if hashlib.sha256(b'\0'.join(terms)).hexdigest()!='28bcc9f9c72be3f52b366df769cd14ceb9713e7bfc3e5be1d2df9fa44c682c81':
        raise ValueError('Unexpected Android dog-name dictionary')
    return ','.join(json.dumps(term.decode('ascii')) for term in terms)


def patch_house(engine, renderer, original_layout, apk):
    cf = ClassFile(engine)
    patch_code(cf,'fC','()V',[(i,b'\x10\x1c',b'\x10\x1e') for i in (0,8,16,60)])
    # The original drawer indexes a bitset by state number. State 48 is
    # opaque and needs byte 6; six bytes covered the existing states 0–44.
    patch_code(cf,'<init>','(Ljava/lang/Object;Ljava/lang/Object;)V',[
        (73,b'\x10\x06',b'\x10\x07'),(83,b'\x10\x2d',b'\x10\x32')])
    kitchen = cf.ref('GF3KitchenQueue','openBuilding','(I)Z')
    patch_code(cf,'D','(I)Z',[(2037,b'\xb8'+u2(kitchen),
        b'\xb8'+u2(cf.ref('GF3Doghouse','openBuilding','(I)Z')))])
    exposed={('b','(IZ)V'),('E','(I)V'),('F','(I)V'),('H','(I)V'),
             ('gf','()V'),('t','()V'),('d','(IIZ)V'),('c','(Z)V'),
             ('a','(Ljava/lang/String;IIII)V'),('b','(Ljava/lang/String;IIII)V'),
             ('a','(Ljava/lang/String;Ljava/lang/String;I)V'),('c','(Lf;)V')}
    fieldmap={'states':('a','[I'),'controls':('a','[[[S'),'templates':('b','[[[S'),
              'captions':('a','[[Ljava/lang/String;'),'assets':('a','[Le;'),
              'images':('a','[Ll;'),'flags':('f','[B'),'placedPet':('a','Lf;'),'mode':('d','I'),
              'transition':('af','I')}
    wanted=set(fieldmap.values())
    for i,(flags,n,d,attrs) in enumerate(cf.fields):
        key=cf.string(n),cf.string(d)
        if key in wanted:
            cf.fields[i]=flags&~2,n,d,attrs
            wanted.remove(key)
    for i,(flags,n,d,attrs) in enumerate(list(cf.methods)):
        key=cf.string(n),cf.string(d)
        if key in exposed:
            cf.methods[i]=flags&~2,n,d,attrs
            exposed.remove(key)
        if key==('fI','()V'):
            cf.methods[i]=flags&~2,cf.utf('gf3PreviousPlacement'),d,attrs
            body=b'\xb8'+u2(cf.ref('GF3PetNames','place','()V'))+b'\xb1'
            cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(0)+u2(0),body,u2(0),[]))]))
        if key not in {('d','(II)Z'),('I','(I)V')}: continue
        dispatch=key[0]=='d'
        alias='gf3PreviousScreen' if dispatch else 'gf3PreviousHit'
        cf.methods[i]=flags&~2,cf.utf(alias),d,attrs
        fn='dispatch' if dispatch else 'hit'
        body=(b'\x1a\x1b' if dispatch else b'\x1a')+b'\xb8'+u2(cf.ref('GF3Doghouse',fn,key[1]))+(b'\xac' if dispatch else b'\xb1')
        width=u2(2 if dispatch else 1)
        cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(width+width,body,u2(0),[]))]))
    if exposed or wanted: raise ValueError(f'Doghouse API mismatch: {exposed} {wanted}')
    values=labels(apk.read('assets/800x480/LATAM'))
    dogs=table(entries(apk.read('assets/800x480/13'))[0])[1]
    houses=table(entries(apk.read('assets/800x480/13'))[3])[1]
    rewards=[dogs[row][69:89:2] for row in (68,70,72,75)]
    if any(dogs[row][70:89:2]!=(1,)*10 for row in (68,70,72,75)):
        raise ValueError('Unexpected daily prize type')
    def nums(rows): return '{'+','.join('{'+','.join(map(str,r))+'}' for r in rows)+'}'
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        data=folder/'GF3HouseData.java'
        strings=','.join(json.dumps(values[i],ensure_ascii=True) for i in
                         (875,883,12288,12291,201,202,203,204,9296,9289,9293,9299,
                          876,877,878,884,885,886,893,894,946,947,942,943,481,487,891,892))
        data.write_text('final class GF3HouseData {static final int[][] BONUS='+nums(rewards)+';'
                        'static final int[] FLOOR={'+','.join(str(houses[i][35]) for i in range(24,27))+'};'
                        'static final String[] TEXT={'+strings+'}, BAD={'+name_filter(apk)+'};}',encoding='ascii')
        stub=folder/'a.java'
        stub.write_text("""class a {static int[] states;static short[][][] controls,templates;
           static String[][] captions;static e[] assets;static l[] images;static byte[] flags;
           static boolean gf3PreviousScreen(int p,int l){return false;}static void gf3PreviousHit(int e){}
           static void b(int id,boolean load){} static void E(int id){} static void F(int id){}
           static void H(int id){} static void gf(){} static void t(){} static void a(int id){}
           static void c(int id){}static void d(int store,int category,boolean push){}static void c(boolean all){}
           static int d(){return 0;}static int e(){return 0;}static void g(int quantity){}
           static int totalStored(int arg){return 0;}static int capacity(){return 0;}
           static f placedPet;static int mode,transition;static int[] Q,R;static void gf3PreviousPlacement(){}
           static void b(f building){}static void c(f dog){}static int a(){return 0;}static void gf3PreviousBuy(int b){}
           static boolean spend(int n){return false;}static boolean f(int n){return false;}
           static void a(String name,String body,int button){}
           static void a(String s,int group,int row,int x,int y){}static void b(String s,int group,int row,int x,int y){}}
           class f {int q,y,J;static f[] heads;f next;boolean a(int n){return false;}}
           class h {static h[] registry;int[][] rows;}class l {}
           class e{short[] c;void a(byte[] b,int off){}void a(int part,int x){}int b(int part){return 0;}int j(int frame){return 0;}}
           class g {static void open(String name){}static byte[] read(int i){return null;}static void l(){}
            static String c(int i){return null;}static int i(){return 0;}}
           class GF3Dogs{static void floor(f p,int h){}static boolean dog(f p){return false;}static int xp(f p){return 0;}static int happiness(f p){return 0;}static int level(f p){return 0;}
               static int nextXp(int level){return 0;}static int nextBills(int level){return 0;}}
           class GF3DogToys{static int quantity(int t){return 0;}static long nextBonus;}
           class GF3DogTutorial{static boolean closeHouse(){return true;}static void house(){}
              static int hint(){return -1;}static void claimed(){}static void placed(int row){}}
           class GF3KitchenQueue{static boolean openBuilding(int row){return false;}}""",encoding='ascii')
        src=Path(__file__).resolve().parents[2]/'src/expansion/GF3Doghouse.java'
        subprocess.run(['javac','--release','8','-g:none','-d',str(folder),str(stub),str(src),
                        str(src.with_name('GF3PetNames.java')),str(data)],check=True)
        remap={**{k:v[0] for k,v in fieldmap.items()},'open':'c','read':'a','registry':'a','rows':'a',
               'heads':'a','next':'a','spend':'c','totalStored':'b','capacity':'c'}
        result={'GF3HouseData.class':convert_helper((folder/'GF3HouseData.class').read_bytes())}
        for name in ('GF3Doghouse.class','GF3PetNames.class'):
            helper=ClassFile((folder/name).read_bytes())
            for alias,real in remap.items():
                helper.pool[helper.utf(alias)]=helper.pool[helper.utf(real)]
            result[name]=convert_helper(helper.bytes())
    sprite=ClassFile(renderer)
    for i,(flags,n,d,attrs) in enumerate(sprite.methods):
        if (sprite.string(n),sprite.string(d))!=('j','(I)I'): continue
        # Both callers need the count of modules in the frame. k(int) already
        # reads it with the same field-width flag used by the sprite loader.
        code=b'\x2a\x1b\xb7'+u2(sprite.ref('e','k','(I)I'))+b'\xac'
        sprite.methods[i]=flags,n,d,[(sprite.utf('Code'),pack_code(u2(2)+u2(2),code,u2(0),[]))]
        break
    else: raise ValueError('Missing native sprite frame-size function')
    sheets=[b for group in shards(apk,'assets/800x480/11').values() for b in group]
    return {**result,'a.class':cf.bytes(),'e.class':sprite.bytes(),'6':layout(original_layout,apk),
            'dh':pack([convert_sprite(sheets[i]) for i in SHEETS])}
