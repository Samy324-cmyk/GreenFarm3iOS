"""Enable concurrent farm music, ambience and effects through the MIDlet's own MMAPI player."""
from pathlib import Path
import subprocess
import tempfile
from tools.expansion.neighbor import expose
from tools.expansion.hives import patch_code
from tools.media import (MUSIC, EFFECTS, GAMEPLAY_SOUNDS, ANIMAL_SOUNDS, ORIGINAL_EMPTY_SLOTS,
                         PET_SOURCE_TO_SLOT, EXTRACTOR_SOURCE_TO_SLOT, ADDITIONAL_SOUNDS, COLLAR_KEY_SOUND)
from tools.timing.classfile import ClassFile, code_parts, convert_helper, pack_code, u2


def patch_audio_boot(data):
    cf=ClassFile(data)
    # Keep all of the original startApp's branches and stack maps intact.
    for i,(flags,n,d,attributes) in enumerate(cf.methods):
        if (cf.string(n),cf.string(d))==('startApp','()V'):
            cf.methods[i]=(2,cf.utf('gf3StartApp'),d,attributes)
            call=b'\xb8'+u2(cf.ref('GF3AudioDevice','prime','()V'))+b'\x2a\xb7'+u2(cf.ref('GloftGF2M','gf3StartApp','()V'))+b'\xb1'
            cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(1)*2,call,u2(0),[]))]))
            return cf.bytes()
    raise ValueError('Missing MIDlet startup')


def patch_farm_audio(game_data,sound_data):
    game=ClassFile(game_data)
    sound=ClassFile(sound_data)
    # k sizes the MMAPI players, command buffers and fade tables from m.
    for _,name,_,attributes in sound.methods:
        if sound.string(name)=='<clinit>':
            for index,(tag,body) in enumerate(attributes):
                if sound.string(tag)=='Code':
                    header,code,ex,extras=code_parts(body)
                    if code[5:9]!=bytes.fromhex('04b3006c') or ex!=u2(0) or extras:
                        raise ValueError('Unknown sound channel initialization')
                    attributes[index]=tag,pack_code(header,code[:5]+b'\x10\x08'+code[6:],ex,extras)
    # k.a(String,int,boolean) originally opens the global g resource reader.
    # Load only the requested audio shard using an independent stream instead.
    def field(owner,name,desc):
        typ=sound.intern(b'\x0c'+u2(sound.utf(name))+u2(sound.utf(desc)))
        return u2(sound.intern(b'\x09'+u2(sound.cls(owner))+u2(typ)))
    old_read=b'\x2a\xb8'+u2(sound.ref('g','c','(Ljava/lang/String;)V'))+b'\x1b\xb8'+u2(sound.ref('g','a','(I)[B'))+b'\xb2'+field('g','V','I')
    new_read=b'\x2a\x1b\xb8'+u2(sound.ref('GF3AudioDevice','readSound','(Ljava/lang/String;I)[B'))+b'\xb2'+field('GF3AudioDevice','soundType','I')+b'\x00'*3
    patch_code(sound,'a','(Ljava/lang/String;IZ)V',[(12,old_read,new_read)])
    # k.c(IIIII) must check the actual MMAPI state before touching volume,
    # media time or playback. A silent provider can accept prefetch as a no-op.
    check=u2(sound.ref('GF3AudioDevice','ready','(ILjavax/microedition/media/Player;)Z'))
    previous=bytes.fromhex('b2005b1a2e04a0000bb2004b1a32c70004b1')
    ready=bytes.fromhex('b2005b1a2eb2004b1a32b8')+check+bytes.fromhex('9a000500b1')
    # Supply the actual decoded WAV to the clock at the MMAPI start call.
    start=u2(sound.ref('GF3AudioDevice','start','(ILjavax/microedition/media/Player;[BI)V'))
    old_start=bytes.fromhex('b2004b1a3209b900e2030058b2004b1a32b900e30100')
    new_start=bytes.fromhex('1ab2004b1a32b2004d1b321db8')+start
    # Some MMAPI providers expose no VolumeControl. Preserve the volume
    # arithmetic, but do not let a missing control abort playback.
    volume=u2(sound.ref('GF3AudioDevice','volume','(Ljavax/microedition/media/Player;I)V'))
    patch_code(sound,'c','(IIIII)V',[(20,previous,ready),
        (72,bytes.fromhex('1218b900da0200c00035'),b'\x00'*10),
        (95,bytes.fromhex('b900e9020057'),b'\xb8'+volume),
        (101,old_start,new_start)])
    expose(sound,sound.methods,{('g','()V')})
    patch_code(sound,'run','()V',[(6,b'\xb8'+u2(sound.ref('k','g','()V')),
                                  b'\xb8'+u2(sound.ref('GF3AudioDevice','update','()V')))])
    patch_code(sound,'a','(I)J',[(19,bytes.fromhex('b900dd0100'),
                         b'\xb8'+u2(sound.ref('GF3AudioDevice','time','(Ljavax/microedition/media/Player;)J')))])
    expose(game,game.fields,{('R','Z'),('T','Z'),('S','Z'),('V','Z'),('at','I'),('C','I'),
                             ('e','J'),('c','Z'),('aw','I'),('W','Z')})
    expose(game,game.methods,{('l','(I)Z')})
    # The credits screen calls the private single-channel dispatcher
    # directly, bypassing the public sound-effect entry point.
    credit=bytes.fromhex('03102203b8')+u2(game.ref('a','c','(IIZ)V'))
    patch_code(game,'y','(I)Z',[(31,credit,b'\x10\x22\xb8'+u2(game.ref('a','c','(I)V')))])
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
    routes={('fE','()V'):('stop',b''),('fF','()V'):('update',b''),('c','(IZ)V'):('music',b'\x1a\x1b'),
            ('c','(I)V'):('effect',b'\x1a'),('d','(I)V'):('effect',b'\x1a')}
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
        stub.write_text('''class a {static boolean R,T,S,V,W,intro;static int at,C,aw; static long lastEffect;static int[][] d;
            static void e(int id,int flags){} static boolean loadSound(int id){return false;}
            static void c(int cue){} static void gf3StopSound(){}}
            class k {static boolean loaded(int cue){return false;} static boolean playing(int ch){return false;}
            static void tick(){} static void a(int ch,int cue,int loops,int volume,int priority){} static void a(int ch,boolean stop){}}
            class GF3AnimalMarket {static int alternate(int id){return 0;}}
            class g {static String packName;static void open(String name){}static int c(int lo,int hi){return 0;}}''',encoding='ascii')
        slots={src:dst for dst,src in (MUSIC|EFFECTS|GAMEPLAY_SOUNDS|ANIMAL_SOUNDS|ORIGINAL_EMPTY_SLOTS).items()}
        slots.update(PET_SOURCE_TO_SLOT|EXTRACTOR_SOURCE_TO_SLOT|ADDITIONAL_SOUNDS|{73:COLLAR_KEY_SOUND})
        ids=folder/'GF3AudioIds.java'
        ids.write_text('class GF3AudioIds {static final int[] slots={'+
                       ','.join(str(slots[i]) for i in range(82))+'};}',encoding='ascii')
        api=folder/'javax/microedition/media/Player.java'
        api.parent.mkdir(parents=True)
        api.write_text('package javax.microedition.media; public interface Player {int REALIZED=200,STARTED=400;'
                       'int getState(); long getMediaTime(); long setMediaTime(long time); void start(); void stop(); void close(); void realize(); void prefetch(); Control getControl(String name);}',encoding='ascii')
        control=api.with_name('Control.java')
        control.write_text('package javax.microedition.media; public interface Control {}',encoding='ascii')
        manager=api.with_name('Manager.java')
        manager.write_text('package javax.microedition.media; public class Manager {public static Player createPlayer(java.io.InputStream in,String type){return null;}}',encoding='ascii')
        volume_api=api.parent/'control/VolumeControl.java'
        volume_api.parent.mkdir()
        volume_api.write_text('package javax.microedition.media.control; public interface VolumeControl extends javax.microedition.media.Control {int setLevel(int n);}',encoding='ascii')
        device=source.with_name('GF3AudioDevice.java')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',tmp,
                        str(stub),str(ids),str(source),str(api),str(control),str(manager),str(volume_api),str(device)],check=True)
        cf=ClassFile((folder/'GF3FarmAudio.class').read_bytes())
        for alias,actual in (('loaded','a'),('playing','b'),('loadSound','l'),('intro','c'),
                             ('lastEffect','e')):
            cf.pool[cf.utf(alias)]=cf.pool[cf.utf(actual)]
        device_class=ClassFile((folder/'GF3AudioDevice.class').read_bytes())
        device_class.pool[device_class.utf('tick')]=device_class.pool[device_class.utf('g')]
        return {'a.class':game.bytes(),'k.class':sound.bytes(),'GF3FarmAudio.class':convert_helper(cf.bytes()),
                'GF3AudioIds.class':convert_helper((folder/'GF3AudioIds.class').read_bytes()),
                'GF3AudioDevice.class':convert_helper(device_class.bytes())}
