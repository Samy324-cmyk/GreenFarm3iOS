"""Recover Android shop table 13 and its three independently selected collections."""
import json
from pathlib import Path
import subprocess
import tempfile

from tools.media import read_groups,write_groups
from .wheel_art import shop_bill, offer_clock
from tools.mexican_spanish import adapt
from tools.timing.classfile import ClassFile,convert_helper,pack_code,u2
from tools.world import entries,labels,pack,table
from .visit_predators import _controls
from .neighbor import entry,expose
from .hive_limits import hive_limits
from .hives import patch_code


def _wrap(cf,key,desc,alias,target,load,stack):
    for i,(flags,n,d,attrs) in enumerate(cf.methods):
        if (cf.string(n),cf.string(d))!=(key,desc):continue
        cf.methods[i]=flags&~2,cf.utf(alias),d,attrs
        code=load+b'\xb8'+u2(cf.ref('GF3MarketFront',target,desc))+b'\xb1'
        cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(stack)+u2(stack),code,u2(0),[]))]))
        return
    raise ValueError('Missing original shop entry '+key+desc)


def align_tabs(rows,android_rows):
    """Store the same origins for painting the tabs and building their hit boxes."""
    # a.G(2) uses the saved panel template when registering a tap target.
    # GF3MarketFront.nav also reads these Android positions for active controls.
    for group in range(3):
        for slot,mobile_slot in enumerate((0,1,2,3,5)):
            index=10+5*group+slot
            reference=android_rows[10+6*group+mobile_slot]
            row=bytearray(rows[index])
            if row[0]!=205 or reference[0]!=205:
                raise ValueError('Unexpected market navigation control')
            row[3:7]=reference[3:7]
            rows[index]=bytes(row)


def reserve_ui_sheets(game):
    # The loader saves the address of this same array in a.a[1]. A later
    # array copy leaves loaded and disposed sprites in different caches.
    # The market, doghouse, extractor and farm stand use slots up through 172.
    packed_count=game.intern(b'\x03'+(138).to_bytes(4,'big'))
    if packed_count>255:raise ValueError('Native UI pack count is not an ldc constant')
    make_array=b'\xbd'+u2(game.cls('e'))
    allocator='gf3UiSpritePool'
    code=b'\x11'+u2(173)+make_array+b'\xb0'
    game.methods.append((10,game.utf(allocator),game.utf('()[Le;'),[(game.utf('Code'),
                         pack_code(u2(1)+u2(0),code,u2(0),[]))]))
    patch_code(game,'fC','()V',[(89,b'\x12'+bytes([packed_count])+make_array,
                                  b'\xb8'+u2(game.ref('a',allocator,'()[Le;')))])


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
    cash_labels=[]
    for amount in range(3,11):
        name=str(amount)+" billetes"
        if name not in groups[0]:groups[0].append(name)
        cash_labels.append(groups[0].index(name))
    if 'Agotado' not in groups[0]:groups[0].append('Agotado')
    sold_label=groups[0].index('Agotado')
    if len(groups[0])>1024:raise ValueError('No room for weekly offer labels')
    panels=entries(classes['6']); old=_controls(panels[2],False)
    mobile=_controls(entries(apk.read(prefix+'10'))[2],True)
    if len(old)!=122 or len(mobile)!=213:raise ValueError('Unexpected shop panel')
    align_tabs(old,mobile)
    for idx in (14,20,26):
        control=bytearray(mobile[idx]);del control[10]
        control[13]=control[26]=0;old.append(control)
    # The Android offers tab displays these controls when its remote index is empty.
    caption=bytearray(mobile[202]);del caption[-1]
    sign=bytearray(mobile[203]);del sign[10]
    if caption[0]!=204 or sign[0]!=205 or sign[8:10]!=bytes([7,0]):
        raise ValueError('Unexpected empty-offers panel')
    # Use the same visible native text type/style as a stock market caption.
    timer=bytearray(old[115]);timer[1:3]=mobile[201][1:3]
    old.extend([caption,sign,timer])
    panels[2]=panels[2][:1]+b''.join(old)
    def arr(values):return '{'+','.join(arr(v) if isinstance(v,(list,tuple)) else str(v) for v in values)+'}'
    nav=mobile[10:28]
    src=Path(__file__).resolve().parents[2]/'src/expansion/GF3MarketFront.java'
    game=ClassFile(classes['a.class'])
    reserve_ui_sheets(game)
    limits=hive_limits(game,apk)
    expose(game,game.fields,{('cu','I'),('cv','I'),('cw','I'),('ct','I'),('bR','I'),('b','[Le;')})
    expose(game,game.methods,{('ad','(I)V'),('u','(I)V'),('af','(I)V'),('d','()I'),('e','()I'),('f','()I'),('g','(I)V'),('h','(I)V'),('c','(Z)V')})
    entry(game,'o','(I)Z','gf3MarketScreen','screen','(I)Z',b'\x1a','GF3MarketFront')
    _wrap(game,'r','(II)V','gf3MarketPopulate','populate',b'\x1a\x1b',2)
    # Draw offer previews without modifying the shared native control array.
    _wrap(game,'a','(I[SIII)V','gf3DrawControl','drawControl',b'\x1a\x2b\x1c\x1d\x15\x04',5)
    _wrap(game,'I','(I)V','gf3MarketHit','hit',b'\x1a',1)
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp)
        data=folder/'GF3MarketRows.java'
        data.write_text('class GF3MarketRows {static String empty='+json.dumps(adapt(spanish[908]))+';'
            +'static int[][] cards='+arr(cards)+',items='+arr(items)+';'
            +'static int soldLabel='+str(sold_label)+';static int[] cashLabels='+arr(cash_labels)+',kinds='+arr(shops)+',x='+arr([int.from_bytes(t[3:5],"little",signed=True) for t in nav])
            +',y='+arr([int.from_bytes(t[5:7],"little",signed=True) for t in nav])+',icons='+
            arr([t[9] for t in mobile[22:28]])+';}',encoding='ascii')
        stub=folder/'a.java'
        stub.write_text('''class a {static int C,cu,cv,cw,ct,maxBills;static short[][][] controls;static e[] assets,worldAssets;
           static int d(){return 0;}static int e(){return 0;}static int f(){return 0;}
           static void giveCoins(int n){}static void giveBills(int n){}static void saveFarm(boolean force){}
           static boolean i(int row){return false;}static int a(){return 0;}static void c(int s){}
           static void a(String text,int gui,int row,int x,int y){}
           static void gf(){}static void H(int gui){}static void ad(int i){}static void af(int i){}static void u(int i){}
           static boolean gf3MarketScreen(int p){return false;}static void gf3MarketPopulate(int t,int c){}
           static void gf3MarketHit(int i){} static void gf3DrawControl(int gui,short[] c,int x,int y,int i){}}
           class GF3HiveLimits {static int owned(){return 0;}static int capacity(){return 0;}}
           class h {static h[] tables;int[][] rows;int b;}
           class e {void a(byte[] b,int offset){} int d(int frame){return 0;}int e(int frame){return 0;}int f(int frame){return 0;}int g(int frame){return 0;} int frames(){return 0;} int palette(){return 0;} void setPalette(int n){} void paintScaled(javax.microedition.lcdui.Graphics g,int f,int x,int y,int z){} } class GF3Doghouse {static boolean drawFixed(int gui,short[] row){return false;}} class GF3DogToys {static boolean ribbonActive(){return false;} static int visibleToy(int i){return 0;}static int slotX(int i){return 0;}static int slotY(int i){return 0;}static int quantity(int i){return 0;}static int dragToy(){return -1;}static int dragX(){return 0;}static int dragY(){return 0;}} class g {static javax.microedition.lcdui.Graphics graphics;static void openAsset(String n){} static byte[] readChunk(int i){return null;}static byte[] readOffer(String name){return null;}static void writeOffer(String name,byte[] b){}static void l(){}}''',encoding='ascii')
        graphics=folder/'javax/microedition/lcdui/Graphics.java'
        graphics.parent.mkdir(parents=True)
        graphics.write_text('package javax.microedition.lcdui; public class Graphics {public static final int HCENTER=1, VCENTER=2; public void drawImage(Image i,int x,int y,int anchor){} public int getClipX(){return 0;}public int getClipY(){return 0;}public int getClipWidth(){return 0;}public int getClipHeight(){return 0;}public void setClip(int x,int y,int w,int h){}}',encoding='ascii')
        image=graphics.with_name('Image.java')
        image.write_text('package javax.microedition.lcdui; public class Image {public static Image createImage(String s)throws java.io.IOException{return null;}}',encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),str(data),
                        str(stub),str(src),str(graphics),str(image)],check=True)
        helper=ClassFile((folder/'GF3MarketFront.class').read_bytes())
        for key,actual in {'controls':'a','tables':'a','rows':'a','assets':'a','worldAssets':'b','frames':'b','palette':'f','setPalette':'d','paintScaled':'c','graphics':'a','openAsset':'c','readChunk':'a','readOffer':'a','writeOffer':'a','giveCoins':'g','giveBills':'h','saveFarm':'c','maxBills':'bR'}.items():
            helper.pool[helper.utf(key)]=helper.pool[helper.utf(actual)]
        return {**limits,'a.class':game.bytes(),'6':pack(panels),'EN':write_groups(groups),
                'GF3MarketFront.class':convert_helper(helper.bytes()),
                'GF3MarketRows.class':convert_helper((folder/'GF3MarketRows.class').read_bytes()),'gf3-bills.png':shop_bill(apk),'gf3-offer-clock.png':offer_clock(apk)}
