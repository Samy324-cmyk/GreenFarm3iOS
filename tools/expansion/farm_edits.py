"""Apply the APK's hive and working-dog warnings in the map's edit menu."""
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from .neighbor import expose
from ..mexican_spanish import adapt
from ..timing.classfile import ClassFile,convert_helper,pack_code,u2
from ..world import labels


def patch_farm_edits(classes,apk):
    game=ClassFile(classes['a.class'])
    expose(game,game.fields,{('a','Lf;')})
    expose(game,game.methods,{('D','()V'),('a','(Ljava/lang/String;Ljava/lang/String;II)V')})
    # Pause wraps the same native event dispatcher; leave its entry in the chain.
    index,= [i for i,(_,name,desc,_) in enumerate(game.methods)
             if (game.string(name),game.string(desc))==('I','(I)V')]
    flags,name,desc,attrs=game.methods[index]
    game.methods[index]=flags&~2,game.utf('gf3FarmEditHit'),desc,attrs
    code=b'\x1a\xb8'+u2(game.ref('GF3FarmEdits','hit','(I)V'))+b'\xb1'
    game.methods.append((flags,name,desc,[(game.utf('Code'),pack_code(u2(1)+u2(1),code,u2(0),[]))]))
    source=Path(__file__).resolve().parents[2]/'src/expansion/GF3FarmEdits.java'
    words=labels(apk.read('assets/800x480/LATAM'))
    with TemporaryDirectory() as scratch:
        folder=Path(scratch)
        stub=folder/'a.java'
        stub.write_text('''class a {static f selected;static void D(){}static void gf3FarmEditHit(int event){}
            static void a(String header,String message,int icon,int kind){}}
            class f {int q,y;static int b(int layer,int id){return 0;}}
            class GF3Dogs {static boolean dog(f item){return false;}}''',encoding='ascii')
        data=folder/'GF3EditWords.java'
        data.write_text('final class GF3EditWords {'+''.join(
            'static final String '+name+'='+json.dumps(adapt(words[key]),ensure_ascii=True)+';'
            for name,key in [('HIVE',12445),('KEEP_HIVE',12446),('DOG',12447),('KEEP_DOG',12448)])+'}',encoding='ascii')
        subprocess.run(['javac','--release','8','-g:none','-d',str(folder),str(stub),str(data),str(source)],check=True)
        helper=ClassFile((folder/'GF3FarmEdits.class').read_bytes())
        helper.pool[helper.utf('selected')]=helper.pool[helper.utf('a')]
        return {'a.class':game.bytes(),'GF3FarmEdits.class':convert_helper(helper.bytes())}
