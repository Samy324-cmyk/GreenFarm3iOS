"""Enable concurrent farm music, ambience and effects through the MIDlet's own MMAPI player."""
from pathlib import Path
import subprocess
import tempfile
from tools.expansion.neighbor import expose
from tools.expansion.hives import patch_code
from tools.media import (MUSIC, EFFECTS, GAMEPLAY_SOUNDS, ANIMAL_SOUNDS, ORIGINAL_EMPTY_SLOTS,
                         PET_SOURCE_TO_SLOT, EXTRACTOR_SOURCE_TO_SLOT, ADDITIONAL_SOUNDS, COLLAR_KEY_SOUND)
from tools.timing.classfile import ClassFile, code_parts, convert_helper, pack_code, u2


def patch_farm_audio(game_data,sound_data):
    game=ClassFile(game_data)
    sound=ClassFile(sound_data)
    # Channel 0 keeps the effects queue. k creates its per-channel players,
    # native fade controls, command buffers and pause/resume state from m.
    patch_code(sound,'<clinit>','()V',[(5,b'\x04',b'\x06')])
    # k.c(IIIII) must check the actual MMAPI state before touching volume,
    # media time or playback. A silent provider can accept prefetch as a no-op.
    check=u2(sound.ref('GF3AudioDevice','ready','(ILjavax/microedition/media/Player;)Z'))
    previous=bytes.fromhex('b2005b1a2e04a0000bb2004b1a32c70004b1')
    ready=bytes.fromhex('b2005b1a2eb2004b1a32b8')+check+bytes.fromhex('9a000500b1')
    patch_code(sound,'c','(IIIII)V',[(20,previous,ready)])
    expose(game,game.fields,{('R','Z'),('T','Z'),('S','Z'),('V','Z'),('at','I'),('C','I'),
                             ('e','J'),('c','Z')})
    expose(game,game.methods,{('l','(I)Z')})
    # Android's music toggle confirms by playing original track 11.
    for _,n,desc,atts in game.methods:
        if game.string(n)=='dT' and game.string(desc)=='()V':
            for idx,(tag,body) in enumerate(atts):
                if game.string(tag)!='Code': continue
                head,raw,ex,more=code_parts(body)
                pattern=b'\x03\x03\xb8'+u2(game.ref('a','c','(IZ)V'))
                if raw.count(pattern)!=1: raise ValueError('Unknown music toggle')
                music_on=b'\x10\x0b\xb8'+u2(game.ref('GF3FarmAudio','original','(I)V'))
                atts[idx]=tag,pack_code(head,raw.replace(pattern,music_on),ex,more)
    routes={('fE','()V'):('stop',b''),('fF','()V'):('update',b''),('c','(IZ)V'):('music',b'\x1a\x1b')}
    for index,(access,n,desc,attrs) in enumerate(list(game.methods)):
        name,signature=game.string(n),game.string(desc)
        if (name,signature) not in routes: continue
        target,load=routes.pop((name,signature))
        if name=='fE':
            game.methods.append((access&~2,game.utf('gf3StopSound'),desc,attrs))
        call=load+b'\xb8'+u2(game.ref('GF3FarmAudio',target,signature))+b'\xb1'
        method=(game.utf('Code'),pack_code(u2(len(load))+u2(len(load)),call,u2(0),[]))
        game.methods[index]=(access,n,desc,[method])
    if routes: raise ValueError('Unsupported farm audio entry points')
    source=Path(__file__).resolve().parents[1]/'src/catalog/GF3FarmAudio.java'
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        stub=folder/'a.java'
        stub.write_text('''class a {static boolean R,T,S,V,intro;static int at,C; static long lastEffect;static int[][] d;
            static void e(int id,int flags){} static boolean loadSound(int id){return false;}
            static void c(int cue){} static void gf3StopSound(){}}
            class k {static boolean loaded(int cue){return false;} static boolean playing(int ch){return false;}
            static void a(int ch,int cue,int loops,int volume,int priority){} static void a(int ch,boolean stop){}}
            class GF3AnimalMarket {static int alternate(int id){return 0;}}
            class g {static String packName;static void open(String name){}static int c(int lo,int hi){return 0;}}''',encoding='ascii')
        slots={src:dst for dst,src in (MUSIC|EFFECTS|GAMEPLAY_SOUNDS|ANIMAL_SOUNDS|ORIGINAL_EMPTY_SLOTS).items()}
        slots.update(PET_SOURCE_TO_SLOT|EXTRACTOR_SOURCE_TO_SLOT|ADDITIONAL_SOUNDS|{73:COLLAR_KEY_SOUND})
        ids=folder/'GF3AudioIds.java'
        ids.write_text('class GF3AudioIds {static final int[] slots={'+
                       ','.join(str(slots[i]) for i in range(82))+'};}',encoding='ascii')
        api=folder/'javax/microedition/media/Player.java'
        api.parent.mkdir(parents=True)
        api.write_text('package javax.microedition.media; public interface Player {int REALIZED=200; int getState();}',encoding='ascii')
        device=source.with_name('GF3AudioDevice.java')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',tmp,
                        str(stub),str(ids),str(source),str(api),str(device)],check=True)
        cf=ClassFile((folder/'GF3FarmAudio.class').read_bytes())
        for alias,actual in (('loaded','a'),('playing','b'),('loadSound','l'),('intro','c'),
                             ('lastEffect','e'),('packName','c'),('open','c')):
            cf.pool[cf.utf(alias)]=cf.pool[cf.utf(actual)]
        return {'a.class':game.bytes(),'k.class':sound.bytes(),'GF3FarmAudio.class':convert_helper(cf.bytes()),
                'GF3AudioIds.class':convert_helper((folder/'GF3AudioIds.class').read_bytes()),
                'GF3AudioDevice.class':convert_helper((folder/'GF3AudioDevice.class').read_bytes())}
