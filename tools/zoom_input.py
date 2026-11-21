"""Keep Android's farm free of zoom buttons and route the available camera inputs."""
import struct
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from .continuous_zoom import patch_fractional
from .expansion.hives import patch_code
from .expansion.neighbor import expose
from .expansion.visit_predators import _controls
from .timing.classfile import ClassFile,convert_helper,pack_code,u2
from .world import entries


def patch_zoom(game,engine,actor,tiles,apk,api):
    terrain=patch_fractional(game,actor,tiles,apk)
    expose(game,game.fields,{('B','I'),('C','I')})
    expose(game,game.methods,{('a','()I')})
    hide=b'\xb8'+u2(game.ref('GF3Zoom','hide','(IIZ)V'))
    for pc,name in [(54,'a'),(61,'b'),(71,'a'),(78,'b')]:
        patch_code(game,'f','(Z)V',[(pc,b'\xb8'+u2(game.ref('a',name,'(IIZ)V')),hide)])
    patch_code(game,'fM','()V',[(432,b'\xb8'+u2(game.ref('f','a','()V')),
                                      b'\xb8'+u2(game.ref('GF3Zoom','update','()V')))])
    for phase,end in enumerate(('Pressed','Released','Dragged')):
        name='pointer'+end
        for i,(flags,n,d,attributes) in enumerate(game.methods):
            if (game.string(n),game.string(d))!=(name,'(II)V'):continue
            game.methods[i]=flags,game.utf('gf3Zoom'+end),d,attributes
            call=b'\x2a\x1b\x1c'+bytes([3+phase])+b'\xb8'+u2(game.ref('GF3Zoom','pointer','(La;III)V'))+b'\xb1'
            game.methods.append((flags,n,d,[(game.utf('Code'),pack_code(u2(4)+u2(3),call,u2(0),[]))]))
            break
        else:raise ValueError('Missing native '+name)
    # Drop a pending single press when a second contact changes the gesture
    # to a pinch. Sending a normal release would activate a crop or HUD button.
    clear=b''
    for name in ('c','d','e'):
        typ=engine.intern(b'\x0c'+u2(engine.utf(name))+u2(engine.utf('Z')))
        ref=engine.intern(b'\x09'+u2(engine.cls('g'))+u2(typ))
        clear+=b'\x03\xb3'+u2(ref)
    clear+=b'\xb8'+u2(engine.ref('g','q','()V'))+b'\xb1'
    engine.methods.append((8,engine.utf('cancelZoomPress'),engine.utf('()V'),[(engine.utf('Code'),
                          pack_code(u2(1)+u2(0),clear,u2(0),[]))]))
    return {'a.class':game.bytes(),'g.class':engine.bytes(),'f.class':actor.bytes(),'k.class':tiles.bytes(),
            'tiles.rgb':terrain,**compile_zoom_helpers(api)}


def compile_zoom_helpers(api):
    with TemporaryDirectory() as scratch:
        p=Path(scratch);stub=p/'a.java'
        stub.write_text('''class a {static int B,C;static boolean l; static f camera;static int screen(){return 0;}
          static void loadZoomMap(){} static boolean zoomPreScaled(int id){return false;}
          static void a(int p,int i,boolean v){} static void b(int p,int i,boolean v){}
          void gf3ZoomPressed(int x,int y){} void gf3ZoomReleased(int x,int y){} void gf3ZoomDragged(int x,int y){}}
          class f {int r,s;void c(int x,int y){} static void changeZoom(int n){} static void e(int n){} static void a(){}}
          class k {static void invalidate(){} static int[][] state; static byte[][][] maps;
            static void drawTiles(javax.microedition.lcdui.Graphics g,int a,int b,int c,int d,int e,int f,int h,boolean l){}}
          class g {static void cancelZoomPress(){}}''',encoding='ascii')
        src=Path(__file__).resolve().parents[1]/'src/catalog/GF3Zoom.java'
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-classpath',str(api),
                        '-d',str(p),str(stub),str(src),str(src.with_name('GF3Fractional.java'))],check=True)
        cls=ClassFile((p/'GF3Zoom.class').read_bytes())
        cls.pool[cls.utf('screen')]=cls.pool[cls.utf('a')]
        projection=ClassFile((p/'GF3Fractional.class').read_bytes())
        for source,target in [('state','a'),('maps','a'),('camera','c'),('invalidate','f')]:
            projection.pool[projection.utf(source)]=projection.pool[projection.utf(target)]
        return {'GF3Zoom.class':convert_helper(cls.bytes()),'GF3Fractional.class':convert_helper(projection.bytes())}


def build_zoom(classes,apk,api):
    local=_controls(entries(classes['6'])[1],False)
    controls=_controls(entries(apk.read('assets/800x480/10'))[1],True)
    if struct.unpack_from('<H',local[58],1)[0]!=44 or any(struct.unpack_from('<H',r,1)[0]==44 for r in controls):
        raise ValueError('Original farm zoom controls changed')
    result=patch_zoom(ClassFile(classes['a.class']),ClassFile(classes['g.class']),
                      ClassFile(classes['f.class']),ClassFile(classes['k.class']),apk,api)
    name='META-INF/MANIFEST.MF'
    manifest=classes[name].decode('utf8').splitlines()
    manifest=[line for line in manifest if line]
    manifest.append('MIDlet-ScreenSize: 480x800')
    manifest.append('Nokia-UI-Enhancement: EnableMultiPointTouchEvents')
    result[name]=('\r\n'.join(manifest)+'\r\n\r\n').encode('utf8')
    return result
