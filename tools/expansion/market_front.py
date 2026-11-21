"""Recover Android shop table 13 and its three independently selected collections."""
import json
from pathlib import Path
import subprocess
import tempfile

from tools.media import read_groups,write_groups
from tools.mexican_spanish import adapt
from tools.timing.classfile import ClassFile,convert_helper,pack_code,u2
from tools.world import entries,labels,pack,table
from .visit_predators import _controls
from .neighbor import entry,expose
from .hive_limits import hive_limits


def _wrap(cf,key,desc,alias,target,load,stack):
    for i,(flags,n,d,attrs) in enumerate(cf.methods):
        if (cf.string(n),cf.string(d))!=(key,desc):continue
        cf.methods[i]=flags&~2,cf.utf(alias),d,attrs
        code=load+b'\xb8'+u2(cf.ref('GF3MarketFront',target,desc))+b'\xb1'
        cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(stack)+u2(stack),code,u2(0),[]))]))
        return
    raise ValueError('Missing original shop entry '+key+desc)


def patch_marketfront(classes,apk,locale):
    prefix='assets/800x480/'
    data=entries(apk.read(prefix+'13'))
    spanish=labels(apk.read(prefix+'LATAM'))
    groups=read_groups(locale)
    cards=[]
    for idx,label,sheet,frame in table(data[13])[1]:
        group=(label>>10) if label>>10 in groups else 0
        value=adapt(spanish[label])
        if value not in groups[group]:
            if len(groups[group])>=1024: raise ValueError('No room for market label')
            groups[group].append(value)
        cards.append((idx,group*1024+groups[group].index(value),sheet,frame))
    if len(cards)!=12:raise ValueError('Unexpected Android shop categories')
    shops=(0,0,0,0,0,0,0,3,4,2,2,2,3,4)
    items=[]
    for category,kind in enumerate(shops):
        filter_column={0:10,2:31,3:34,4:22}[kind]
        order_column=6 if kind in (0,3) else 5
        rows=table(data[kind])[1]
        ordered=sorted((row[order_column],row[0]) for row in rows
                       if row[filter_column]==(category if category<12 else 0) and row[order_column]>=0)
        if [i for i,_ in ordered]!=list(range(len(ordered))) or not ordered:
            raise ValueError(f'Non-contiguous original shelf {category}')
        items.append([row for _,row in ordered])
    panels=entries(classes['6']); old=_controls(panels[2],False)
    mobile=_controls(entries(apk.read(prefix+'10'))[2],True)
    if len(old)!=122 or len(mobile)!=213:raise ValueError('Unexpected shop panel')
    for idx in (14,20,26):
        control=bytearray(mobile[idx]);del control[10]
        control[13]=control[26]=0;old.append(control)
    # The Android offers tab displays these controls when its remote index is empty.
    caption=bytearray(mobile[202]);del caption[-1]
    sign=bytearray(mobile[203]);del sign[10]
    if caption[0]!=204 or sign[0]!=205 or sign[8:10]!=bytes([7,0]):
        raise ValueError('Unexpected empty-offers panel')
    old.extend([caption,sign])
    panels[2]=panels[2][:1]+b''.join(old)
    def arr(values):return '{'+','.join(arr(v) if isinstance(v,(list,tuple)) else str(v) for v in values)+'}'
    nav=mobile[10:28]
    src=Path(__file__).resolve().parents[2]/'src/expansion/GF3MarketFront.java'
    game=ClassFile(classes['a.class'])
    limits=hive_limits(game,apk)
    expose(game,game.fields,{('cu','I'),('cv','I'),('cw','I'),('ct','I')})
    expose(game,game.methods,{('ad','(I)V'),('u','(I)V'),('af','(I)V')})
    entry(game,'o','(I)Z','gf3MarketScreen','screen','(I)Z',b'\x1a','GF3MarketFront')
    _wrap(game,'r','(II)V','gf3MarketPopulate','populate',b'\x1a\x1b',2)
    _wrap(game,'I','(I)V','gf3MarketHit','hit',b'\x1a',1)
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        data=folder/'GF3MarketRows.java'
        data.write_text('class GF3MarketRows {static String empty='+json.dumps(adapt(spanish[908]))+';'
            +'static int[][] cards='+arr(cards)+',items='+arr(items)+';'
            +'static int[] kinds='+arr(shops)+',x='+arr([int.from_bytes(t[3:5],"little",signed=True) for t in nav])
            +',y='+arr([int.from_bytes(t[5:7],"little",signed=True) for t in nav])+',icons='+
            arr([t[9] for t in mobile[22:28]])+';}',encoding='ascii')
        stub=folder/'a.java'
        stub.write_text('''class a {static int C,cu,cv,cw,ct;static short[][][] controls;static e[] assets;
           static boolean i(int row){return false;}static int a(){return 0;}static void c(int s){}
           static void a(String text,int gui,int row,int x,int y){}
           static void gf(){}static void H(int gui){}static void ad(int i){}static void af(int i){}static void u(int i){}
           static boolean gf3MarketScreen(int p){return false;}static void gf3MarketPopulate(int t,int c){}
           static void gf3MarketHit(int i){}}
           class GF3HiveLimits {static int owned(){return 0;}static int capacity(){return 0;}}
           class h {static h[] tables;int[][] rows;int b;}
           class e {void a(byte[] b,int offset){}} class g {static void openAsset(String n){} static byte[] readChunk(int i){return null;}static void l(){}}''',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),str(data),
                        str(stub),str(src)],check=True)
        helper=ClassFile((folder/'GF3MarketFront.class').read_bytes())
        for key,actual in {'controls':'a','tables':'a','rows':'a','assets':'a','openAsset':'c','readChunk':'a'}.items():
            helper.pool[helper.utf(key)]=helper.pool[helper.utf(actual)]
        return {**limits,'a.class':game.bytes(),'6':pack(panels),'EN':write_groups(groups),
                'GF3MarketFront.class':convert_helper(helper.bytes()),
                'GF3MarketRows.class':convert_helper((folder/'GF3MarketRows.class').read_bytes())}
