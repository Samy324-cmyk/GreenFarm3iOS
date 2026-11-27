"""Reconcile the MIDP animal state machine with the offline dog actor."""
from pathlib import Path
import subprocess
import tempfile
from .hives import patch_code
from tools.timing.classfile import ClassFile, convert_helper, pack_code, u2


def patch_dogs(f_class, javac='javac'):
    actor = ClassFile(f_class)
    def call(name,desc):
        return b'\xb8'+u2(actor.ref('GF3Dogs',name,desc))

    for key,original,helper,desc,ret in [
        (('h','()Z'),'gf3AnimalTouch','touch','(Lf;)Z',b'\xac'),
        (('gf3AnimalCare','()V'),'gf3NativeCare','care','(Lf;)V',b'\xb1')]:
        for idx,(flags,n,d,attributes) in enumerate(actor.methods):
            if (actor.string(n),actor.string(d)) == key:
                actor.methods[idx] = flags,actor.utf(original),d,attributes
                body = b'\x2a' + call(helper,desc) + ret
                actor.methods.append((flags,n,d,[(actor.utf('Code'),
                    pack_code(u2(1)+u2(1),body,u2(0),[]))]))
                break
        else:
            raise ValueError(f'Missing pet actor hook {key}')

    # Only the timer-driven maturity call is suppressed for a puppy. The
    # separate instant-finish entry still calls J() just as the APK does.
    grow = b'\x2a\xb7'+u2(actor.ref('f','J','()V'))+b'\xb1'
    actor.methods.append((16,actor.utf('gf3Mature'),actor.utf('()V'),[(actor.utf('Code'),
        pack_code(u2(1)+u2(1),grow,u2(0),[]))]))
    patch_code(actor,'a','()V',[
        (3973,bytes.fromhex('b7015b'),call('age','(Lf;)V')),
        (3306,bytes.fromhex('b6017c'),call('finishedEating','(Lf;I)V')),
        (3252,bytes.fromhex('b6017c'),call('finishedCleaning','(Lf;I)V')),
        (4301,bytes.fromhex('b6017f'),call('productionDue','(Lf;I)V'))])
    patch_code(actor,'J','()V',[(284,bytes.fromhex('b80122'),call('growthEvent','(III)I'))])

    source = Path(__file__).resolve().parents[2] / 'src/expansion/GF3Dogs.java'
    with tempfile.TemporaryDirectory() as temp:
        folder=Path(temp)
        stub=folder/'f.java'
        stub.write_text("""class f {int q,J,f,c,d,r,s,D; long e; boolean a(int flag){return false;}
        static f a(int t,int l,int[] p){return null;} void a(int x,int y,int t,int d,boolean collect,int n){}
        void i(int s){} void j(int flags){} void l(int flags){} void H(){} void r(){} boolean gf3AnimalTouch(){return false;}
        void gf3Mature(){} void gf3NativeCare(){} } class a {static int F;static int b(int i,int n,int action){return 0;}}
        class GF3FarmAudio {static void original(int cue){}}""",encoding='ascii')
        subprocess.run([javac,'--release','8','-g:none','-d',str(folder),str(stub),str(source)],check=True)
        helper = convert_helper((folder/'GF3Dogs.class').read_bytes())
    return {'f.class':actor.bytes(),'GF3Dogs.class':helper}
