"""Apply the 4.4.4 animal reserve check before any of the pond's three casts."""
import json
from pathlib import Path
import subprocess
import tempfile

from .hives import patch_code
from .neighbor import expose
from tools.mexican_spanish import adapt
from tools.timing.classfile import ClassFile,convert_helper,u2
from tools.world import labels


def patch_pond(game_data,apk):
    game=ClassFile(game_data)
    expose(game,game.methods,{('b','(I)I'),('c','()I'),('a','(IIZ)V')})
    call=lambda owner,name,signature:b'\xb8'+u2(game.ref(owner,name,signature))
    old=b'\x08'+call('a','b','(I)I')+b'\x05'+call('f','a','(I)I')+b'\x60'+call('a','c','()I')+b'\x10\x0f\x64\xa4'
    new=call('GF3Pond','blocked','()Z')+b'\0'*12+b'\x99'
    patch_code(game,'M','(I)Z',[(0,old,new),(47,call('a','a','(IIZ)V'),call('GF3Pond','tip','(IIZ)V')),
        (112,call('g','c','(I)Ljava/lang/String;'),
        call('GF3Pond','message','(I)Ljava/lang/String;'))])
    text=adapt(labels(apk.read('assets/800x480/LATAM'))[12485])
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        code=folder/'GF3Pond.java'
        code.write_text('''final class GF3Pond {
    private static boolean animalLimit;
    static boolean blocked() {
        if(a.b(5)+f.a(2)>a.c()-15){animalLimit=false;return true;}
        int livestock=f.a(0,54);
        for(int row=0;row<a.gf3AnimalRows().length;row++)livestock+=a.gf3Stored(3,row);
        animalLimit=livestock>95;
        return animalLimit;
    }
    static void tip(int page,int index,boolean show){a.a(page,index,show&&!animalLimit);}
    static String message(int ordinary){
        return animalLimit?'''+json.dumps(text,ensure_ascii=True)+''':g.c(ordinary);
    }
} class a {static int[][] gf3AnimalRows(){return null;} static int gf3Stored(int group,int row){return 0;}
    static void a(int page,int index,boolean show){}
    static int b(int group){return 0;} static int c(){return 0;}}
class f {static int a(int layer){return 0;} static int a(int layer,int kind){return 0;}}
class g {static String c(int key){return null;}}''',encoding='ascii')
        subprocess.run(['javac','--release','8','-g:none','-Xlint:-options','-d',str(folder),str(code)],check=True)
        return {'a.class':game.bytes(),'GF3Pond.class':convert_helper((folder/'GF3Pond.class').read_bytes())}
