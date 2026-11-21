"""Preserve the APK's full tank until Walt finishes fertilizing the farm."""
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from .hives import patch_code
from .neighbor import expose
from tools.timing.classfile import ClassFile,convert_helper,u2
from tools.world import entries,table


def patch_crop_duster(data,apk):
    # Android's Kg uses the exact same fuel units as the touch engine.
    if table(entries(apk.read('assets/800x480/13'))[20])[1][5][1]!=360:
        raise ValueError('Unexpected aircraft fuel capacity')
    game=ClassFile(data)
    expose(game,game.fields,{('bT','I')})
    def call(name,signature):
        return b'\xb8'+u2(game.ref('GF3CropDuster',name,signature))
    patch_code(game,'I','(I)V',[
        (2354,bytes.fromhex('b20205'),call('available','()I')),
        (2364,bytes.fromhex('b30205'),call('launch','(I)V'))])
    patch_code(game,'I','(I)Z',[(2438,b'\xb8'+u2(game.ref('f','o','()V')),call('land','()V'))])
    source=Path(__file__).resolve().parents[2]/'src/expansion/GF3CropDuster.java'
    with TemporaryDirectory() as tmp:
        folder=Path(tmp)
        stub=folder/'a.java'
        stub.write_text('class a {static int w,bT;} class f {static f[] heads;f next;int q,D;void F(){}}')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',tmp,str(stub),str(source)],check=True)
        helper=ClassFile((folder/'GF3CropDuster.class').read_bytes())
        for field in ('heads','next'):
            helper.pool[helper.utf(field)]=helper.pool[helper.utf('a')]
        return {'a.class':game.bytes(),'GF3CropDuster.class':convert_helper(helper.bytes())}
