"""Apply the Android level table and two separate hive/tree populations to the MIDP market."""
import json
import subprocess
import tempfile
from pathlib import Path

from .hives import patch_code
from .neighbor import expose
from ..mexican_spanish import adapt
from ..timing.classfile import ClassFile,convert_helper,u2
from ..world import entries,labels,table


def hive_limits(game,apk):
    expose(game,game.fields,{('V','[I')})
    expose(game,game.methods,{('f','()I'),('B','()I'),('D','()V'),('e','(IIII)V'),
                             ('a','(Ljava/lang/String;Ljava/lang/String;IIZ)V')})
    def call(method,desc):
        return b'\xb8'+u2(game.ref('GF3HiveLimits',method,desc))
    buy='gf3PreviousBuy'
    patch_code(game,buy,'(I)V',[(321,bytes.fromhex('031034b8078ab80464'),
            b'\x1a'+call('buyCount','(I)I')+b'\x1a'+call('buyLimit','(I)I')),
        (346,bytes.fromhex('1101eb1101ec100703b8061b'),b'\x1a'+call('buyNotice','(I)V'))])
    patch_code(game,'a','(Lf;Z)V',[
        (385,bytes.fromhex('031034b8078a3db804643e'),b'\x2a'+call('placingCount','(Lf;)I')+b'\x3d\x2a'+call('placingLimit','(Lf;)I')+b'\x3e'),
        (401,bytes.fromhex('b8046d1014'),b'\x2a'+call('cancelPlacement','(Lf;)I'))])
    patch_code(game,'gf3OwnFarm','(I)Z',[(686,bytes.fromhex('1101eb1101ec100703b8061b'),call('placingNotice','()V'))])
    # Offline achievement 3999 asks for 15 planted fruit trees (Android
    # cGame.OG -> s1.y(1,52)); stock and hive actors are separate there.
    patch_code(game,'a','(Z)V',[(125,bytes.fromhex('031034b807a8'),call('trees','()I'))])
    area='(IIIIII[Lf;I)I'
    patch_code(game,'di','()V',[(130,bytes.fromhex('b8078f'),call('areaTrees',area)),
                               (134,bytes.fromhex('031034b8078a'),call('trees','()I'))])
    premium=table(entries(apk.read('assets/800x480/13'))[27])[1]
    caps=[0]*51
    for row in premium:
        if 1<=row[1]<=50:caps[row[1]]=row[5]
    if (caps[14:17],caps[48:51])!=([0,1,2],[20,20,20]):raise ValueError('Unexpected Android beehive level schedule')
    strings=labels(apk.read('assets/800x480/LATAM'))
    title=[adapt(strings[n]) for n in (12384,12383,12442,12443)]
    source=Path(__file__).resolve().parents[2]/'src/expansion/GF3HiveLimits.java'
    with tempfile.TemporaryDirectory() as scratch:
        folder=Path(scratch)
        data=folder/'GF3HiveLevels.java'
        data.write_text('final class GF3HiveLevels {static final byte[] maximum={'+','.join(map(str,caps))+
            '};static final String[] text={'+','.join(json.dumps(v,ensure_ascii=True) for v in title)+'};}',encoding='ascii')
        stub=folder/'a.java'
        stub.write_text('''class a{static int A;static int[] V;static int gf3Stored(int group,int row){return 0;}
          static int f(){return 0;}static int B(){return 0;}static void D(){}static void e(int i,int j,int k,int l){}
          static void gf3HiveNotice(String t,String b,int i,int j,boolean v){}}
          class f{int J; static int b(int layer,int sku){return 0;}static int a(int layer,int kind){return 0;}
          static int a(int layer,int kind,int l,int r,int t,int b,f[] found,int max){return 0;}}''',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),str(data),str(stub),str(source)],check=True)
        helper=ClassFile((folder/'GF3HiveLimits.class').read_bytes())
        helper.pool[helper.utf('gf3HiveNotice')]=helper.pool[helper.utf('a')]
        return {'GF3HiveLimits.class':convert_helper(helper.bytes()),
                'GF3HiveLevels.class':convert_helper((folder/'GF3HiveLevels.class').read_bytes())}
