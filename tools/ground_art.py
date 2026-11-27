"""Rebuild the two resolutions of the MIDP terrain tiles from the Android artwork."""
import struct
from .sprites import convert_sprite, geometry, midp_modules, midp_pixels, rebuild_shard, shards
from .expansion.hives import patch_code
from .timing.classfile import pack_code, u2


def sample_half(block,w,h):
    # The 480×800 MIDlet's half-size terrain sheet takes the center of
    # each 2×2 source area, rounded toward the bottom right.
    return b''.join(block[y*w+1:(y+1)*w:2] for y in range(1,h,2))


def ground_tiles(jar,apk,updates):
    legacy=[b for group in shards(jar,'5').values() for b in group]
    original = [b for group in shards(apk,'assets/800x480/9').values() for b in group][0]
    full=convert_sprite(original)
    shape,_,r,flags,_=geometry(full)
    small,_,reader,sflags,_=geometry(legacy[158])
    old,_,oref,oflags,_=geometry(legacy[0])
    header=legacy[158][:reader.pos]
    if (shape!=old or len(shape[0])!=48 or any(shape[1:]) or any(small[1:]) or
            [m[1:3] for m in shape[0]]!=[(72,36)]*48 or
            [m[1:3] for m in small[0]]!=[(36,18)]*48):
        raise ValueError('Unknown terrain tile indices or dimensions')
    _,_,old_colors,old_blocks=midp_modules(old,oref,oflags)
    _,_,small_colors,small_blocks=midp_modules(small,reader,sflags)
    def rgb(palette,ids):
        return b''.join(palette[3*v:3*v+3] for v in ids)
    if any(rgb(old_colors,sample_half(b,72,36))!=rgb(small_colors,s)
           for b,s in zip(old_blocks,small_blocks)):
        raise ValueError('Half-resolution terrain no longer uses the reference sampler')
    count,n,palette,blocks=midp_modules(shape,r,flags)
    half=midp_pixels((count,n,palette,[sample_half(b,72,36) for b in blocks]),sflags,header)
    class Overlay:
        def read(self,key):
            return updates[key] if key in updates else jar.read(key)
    overlay=Overlay()
    out={}
    offset=0
    for name,group in shards(overlay,'5').items():
        changed=False
        for ident,art in ((0,full),(158,half)):
            if offset<=ident<offset+len(group):
                group[ident-offset]=art
                changed=True
        if changed:
            raw=overlay.read(name)
            h=0 if '.' in name else 4+2*struct.unpack_from('<H',raw,2)[0]
            out[name]=rebuild_shard(group,raw[:h])
        offset+=len(group)
    return out


def preserve_actor_invalidation(actor):
    # Actor changes erase underlying tiles immediately. When the queue of 500
    # erase rectangles wraps, its discarded rectangles cannot restore sprites
    # on those tiles. Mark the native actor layer for one complete composition.
    def field(owner,name,desc):
        typ=actor.intern(b'\x0c'+u2(actor.utf(name))+u2(actor.utf(desc)))
        return u2(actor.intern(b'\x09'+u2(actor.cls(owner))+u2(typ)))
    counter=field('f','ay','I')
    full=field('a','l','Z')
    reset = b'\x1a\xb3' + counter + b'\x04\xb3' + full + b'\xb1'
    name = 'gf3ResetActorRegions'
    desc = '(I)V'
    actor.methods.append((10,actor.utf(name),actor.utf(desc),[(actor.utf('Code'),
        pack_code(u2(1)+u2(1),reset,u2(0),[]))]))
    patch_code(actor,'a','(IIII)V',[(10,b'\xb3'+counter,b'\xb8'+u2(actor.ref('f',name,desc)))])


def patch_horizon(actor_data, terrain_data):
    from pathlib import Path
    import subprocess
    from tempfile import TemporaryDirectory
    from .expansion.neighbor import expose
    from .timing.classfile import ClassFile, convert_helper
    actor=ClassFile(actor_data)
    terrain=ClassFile(terrain_data)
    preserve_actor_invalidation(actor)
    expose(terrain, terrain.fields, {('s','I'),('a','[[I'),('a','[[[I'),('p','[I')})
    expose(actor, actor.fields, {('ay','I')})
    expose(actor, actor.methods, {('f','(II)V')})
    def invoke(owner, name, desc):
        return b'\xb8'+u2(actor.ref(owner,name,desc))

    # Enter the first actor group before painting the horizon or any flowers.
    # The original rolls over five groups within one composition.
    old_actor = b'\xb7'+u2(actor.ref('f','f','(II)V'))
    visible = invoke('GF3Horizon','paintActor','(Lf;II)V')
    patch_code(actor,'b','()V',[
        (9,bytes.fromhex('b2009f1b32'),b'\x1b'+invoke('GF3Horizon','firstActor','(I)Lf;')),
        (47,old_actor,visible),(627,old_actor,visible)])
    # Keep the original actor erase/damage queue. Only the calls that used
    # the tile layer's dirty region are replaced, including prescaled sprites.
    sprite = '(ILe;IIIZ[I)V'
    old, new = invoke('k','a',sprite), invoke('GF3Horizon','staticSprite',sprite)
    patch_code(actor,'f','(II)V',[(159,old,new),(179,old,new)])
    # Keep the typed branch and its verified stack frame. draw() handles
    # every supported farm and skips the old baked scenery at this site.
    patch_code(actor,'b','()V',[(79,bytes.fromhex('b2004eb400e8110240a2021e'),
        b'\xb8'+u2(actor.ref('GF3Horizon','draw','()Z'))+bytes.fromhex('0000000000009a021e'))])
    with TemporaryDirectory() as tmp:
        folder=Path(tmp)
        graphics=folder/'Graphics.java'
        graphics.write_text('package javax.microedition.lcdui; public class Graphics{public void setColor(int c){}}')
        stub=folder/'a.java'
        stub.write_text("""class a {static int B;static boolean l;static e[] b,ui;
              static boolean prescaled(int id){return false;}}
            class e {int top(int f){return 0;} int left(int f){return 0;} int width(int f){return 0;}
              int height(int f){return 0;} int frames(){return 0;}}
            class f {static f[] actors;static int eraseCount;int r,s;void paintTile(int slot,int frame){}}
            class k {static int[][] layer;static int[][][] dirty;static int[] tiles;static int dirtyCount; static javax.microedition.lcdui.Graphics[][] buffers;
              static int cameraX(int layer){return 0;} static int cameraY(int layer){return 0;}
              static int e(){return 0;} static void fill(int x,int y,int w,int h,boolean all){}
              static void sprite(int layer,e pic,int frame,int x,int y,boolean all,int[] clip){}}
            class g {static void o(){} static void n(int zoom){} static void p(){}}""")
        source=Path(__file__).resolve().parents[1]/'src/catalog/GF3Horizon.java'
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',tmp,
                        str(graphics),str(stub),str(source)],check=True)
        helper=ClassFile((folder/'GF3Horizon.class').read_bytes())
        for alias,real in [('cameraX','a'),('cameraY','b'),('buffers','a'),('actors','a'),('dirtyCount','s'),('fill','a'),('sprite','a'),
                           ('top','g'),('left','f'),('width','d'),('height','e'),('frames','b'),
                           ('layer','a'),('dirty','a'),('tiles','p'),('ui','a'),('prescaled','g'),
                           ('paintTile','f'),('eraseCount','ay')]:
            helper.pool[helper.utf(alias)]=helper.pool[helper.utf(real)]
        return {'f.class':actor.bytes(),'k.class':terrain.bytes(),'GF3Horizon.class':convert_helper(helper.bytes())}
