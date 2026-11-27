"""Connect the first home-farm fox to the journal, farm actors and real touch handler."""
import json
from pathlib import Path
import struct
import subprocess
import tempfile

from .neighbor import entry, expose
from .hives import patch_code
from tools.farm_layout import records
from tools.timing.classfile import ClassFile, convert_helper, u2
from tools.world import entries, labels, pack, table
from .visit_predators import _controls


def android_data(apk):
    prefix='assets/800x480/'
    tables=entries(apk.read(prefix+'13'))
    animals=table(tables[0])[1]
    text=labels(apk.read(prefix+'LATAM'))
    farm=entries(apk.read(prefix+'14'))[4]
    home,=[struct.unpack_from('<HH',r,3) for r in records(farm)
           if r[0]==50 and r[8:10]==bytes((54,73))]
    breed_rows=(68,69,70,71,72,75)
    if any(animals[i][1]!=2000+i for i in breed_rows):
        raise ValueError('Unknown Android pet breed indices')
    values=','.join('{'+','.join(str(animals[i][j]) for j in (45,46,49,50,51,52,53,54))+'}' for i in breed_rows)
    quest_rows=table(tables[6])[1]
    special=quest_rows[297:304]
    quests=','.join(str(r[1]) for r in special)
    levels=','.join(str(r[12]) for r in special)
    prerequisites=','.join('{'+','.join(str(quest_rows[i][1]) for i in r[13:16] if i>=0)+'}' for r in special)
    lines=''.join('case '+str(i)+':return '+json.dumps(text[i],ensure_ascii=True)+';'
                  for i in (955,956,957,958,959,964,965,975,979,12320,12321,12327,12331,2400,2402,2405,2407))
    return ('final class GF3HomeData {static final int HOME_X=%d,HOME_Y=%d;'%home
            +'static final int[][] rates={'+values+'};'
            +'static final int[] quests={'+quests+'}, levels={'+levels+'};'
            +'static final int[][] prerequisites={'+prerequisites+'};'
            +'static int[] dog(int id){return rates[id==2075?5:id-2068];}'
            +'static String line(int id){switch(id){'+lines+'default:throw new IllegalArgumentException();}}}')


def home_panel(layout, apk):
    panels=entries(layout)
    native=_controls(panels[1],False)
    source=_controls(entries(apk.read('assets/800x480/10'))[1],True)
    alert=bytearray(source[37])
    if (len(native)!=96 or alert[0]!=205 or alert[8:12]!=bytes((1,70,0,255))
            or alert[14]!=0 or alert[26]!=255):
        raise ValueError('Unexpected home-farm predator alert')
    del alert[10]  # The farm HUD uses frame 70 of Android sheet 1.
    panels[1]+=alert
    return pack(panels)


def patch_home(game_data, actor_data, layout, apk):
    game,actor=ClassFile(game_data),ClassFile(actor_data)
    expose(game,game.methods,{('a','(II)Lf;'),('f','(IIZ)V'),('O','(I)Z'),
                              ('r','(II)V'),('d','(IIZ)V'),('ad','(I)V'),('t','(Z)V'),('J','(I)V'),
                              ('a','(Lf;[I)Z'),('av','(I)V'),('u','(I)V'),('a','(IIZ)V')})
    expose(game,game.fields,{('fE','I'),('k','C'),('C','I'),('af','I'),('bH','[I'),('M','[I'),('Q','[I'),('R','[I'),
                             ('a','Lf;'),('l','Z'),('b','[[I'),('dp','I'),('dr','I'),('a','[[[S')})
    # HUD sheet 10 keeps MIDP frames 10..13 for the old lock animation.
    # Android portraits 10/11 are relocated to 14/15 by hud_art.SHOP_FRAMES.
    category=game.intern(b'\x09'+u2(game.cls('a'))+u2(game.intern(b'\x0c'+u2(game.utf('bH'))+u2(game.utf('[I')))))
    patch_code(game,'d','(Z)V',[(204,b'\xb2'+u2(category)+bytes.fromhex('15042e0464'),
                    b'\x15\x04\xb8'+u2(game.ref('GF3HomePredator','journalIcon','(I)I'))+b'\x00\x00\x00')])
    # The seven expansion chapters use the Android priority and prerequisites,
    # independently of the stock scheduler's scan through the first 297 rows.
    # Preserve a journal slot for a tutorial that will shortly unlock.
    # The native scheduler's outer bound is a.k (four journal entries).
    field=game.intern(b'\x09'+u2(game.cls('a'))+u2(game.intern(b'\x0c'+u2(game.utf('k'))+u2(game.utf('C')))))
    patch_code(game,'u','()Z',[(31,b'\xb2'+u2(field),b'\xb8'+u2(game.ref('GF3HomePredator','ordinarySlots','()I'))),
                                (49,bytes.fromhex('b2033f'),bytes.fromhex('110129'))])
    entry(game,'u','()Z','gf3Schedule','schedule','()Z',b'','GF3HomePredator')
    entry(game,'D','(I)Z','gf3OwnFarm','farm','(I)Z',b'\x1a','GF3HomePredator')
    patch_code(game,'o','(I)Z',[(139,b'\xb8'+u2(game.ref('a','ad','(I)V')),
                   b'\xb8'+u2(game.ref('GF3HomePredator','shopCategory','(I)V')))])
    entry(game,'o','(I)Z','gf3HomeShop','shop','(I)Z',b'\x1a','GF3HomePredator')
    entry(game,'r','(I)Z','gf3HomeMill','mill','(I)Z',b'\x1a','GF3HomePredator')
    entry(actor,'h','()Z','gf3OtherTouch','touch','(Lf;)Z',b'\x2a','GF3HomePredator')
    entry(actor,'f','()Z','gf3OtherTreeTouch','touchTree','(Lf;)Z',b'\x2a','GF3HomePredator')
    expose(actor,actor.fields,{('c','J'),('d','J'),('e','J')})
    actor.fields.append((0,actor.utf('gf3ScaredAt'),actor.utf('J'),[]))
    patch_code(actor,'a','()V',[(44,b'\xb8'+u2(actor.ref('GF3DogToys','tick','(Lf;)I')),
            b'\xb8'+u2(actor.ref('GF3HomePredator','update','(Lf;)I')))])
    return {'a.class':game.bytes(),'f.class':actor.bytes(),'6':home_panel(layout,apk),**build_home_helpers(apk)}


def build_home_helpers(apk):
    path=Path(__file__).resolve().parents[2]/'src/expansion/GF3HomePredator.java'
    with tempfile.TemporaryDirectory() as temp:
        folder=Path(temp)
        stub=folder/'a.java'
        stub.write_text('''class a {
            static int F,C,fE,B,dp,dr,af; static boolean redrawObjects; static char k;
            static int[] bD,cb,bH,M,Q,R; static int[][] scroll; static f c,placing; static e[] art;
            static short[][][] controls; static void showControl(int panel,int index,boolean visible){}
            static int f(){return 0;} static boolean h(int id){return false;} static boolean i(int row){return false;}
            static void f(int q,int slot,boolean intro){} static boolean O(int s){return false;}
            static boolean gf3Schedule(){return false;}
            static boolean gf3OwnFarm(int e){return false;} static int a(){return 0;}
            static boolean gf3HomeShop(int e){return false;} static void d(int cat,int tab,boolean push){}
            static boolean gf3HomeMill(int e){return false;} static void t(boolean visible){} static void J(int slide){}
            static int c(int food){return 0;} static void a(int screen){}
            static boolean a(f actor,int[] out){return false;} static boolean a(f actor){return false;}
            static void av(int amount){}
            static void r(int cat,int group){} static void ad(int cat){} static void u(int tab){}
            static void a(f x,int y,int z){} static void a(String s,int p,int q){}
            static void a(String title,String text,int p,int q){} static void c(int[] world,int[] tile){}
            static boolean owned(int zone){return false;} static int region(int x,int y){return 0;}
            static f gf3CreateAnimal(int tab,int row){return null;} static int b(int x,int y,int z){return 0;}
            static void c(){} static void aI(int n){} }
          class f {int J,r,s,A,B,D,E,u,v,q,w,x,y; static f[] heads; f next; long gf3ScaredAt,treeStart,birth,feedStart;
            k a; boolean a(int flag){return false;} void k(int flag){} boolean gf3OtherTreeTouch(){return false;}
            void l(int flag){} void j(int flag){} void H(){} void i(int state){} void L(){} boolean gf3OtherTouch(){return false;}
            static int a(int l,int t,int r,f[] out,int max){return 0;}
            static f a(int t,int l,int[] p){return null;} void a(int x,int y,int duration){}
            void a(int x,int y,int type,int delay,boolean collect,int n){} }
          class k {int flags; boolean a(){return false;} static void f(){} int animation(){return 0;} int frame(){return 0;}}
          class g {static int ab,ac,ad,K; static int c(int lo,int hi){return lo;}
            static String a(String source,String token,String value){return null;}} class e {void a(int[] bounds,int anim,int frame,int x,int y,int flags){}}
          class GF3PetNames {static String name(f pet){return null;}static boolean naming(f pet){return false;}}
          class GF3FarmAudio {static void original(int cue){}}
          class GF3Hive {static boolean isHive(f x){return false;}}
          class GF3Doghouse {static f resident(f exclude){return null;} static int floor(){return 0;}}
          class GF3DogToys {static int tick(f x){return 0;}static void closeForFight(f x){}} class GF3MarketFront {static void drawPetRibbon(){}}
          class GF3VisitPredators {static void write(String n,byte[] b)throws java.io.IOException{}
            static byte[] read(String n)throws java.io.IOException{return null;}}
          class GF3Dogs {static boolean dog(f x){return false;} static int happiness(f d){return 0;} static int level(f d){return 0;}
            static void finishToy(f d,int xp,int mood){}static void bubble(f x,int frame){}static void clearMood(f x){}}
          class GF3Neighbor {static f animal(int row){return null;} static void hold(f f,int pose,int rep){}
            static void approach(f pet,f target){} static boolean advance(f pet,f target){return false;}static boolean advanceFight(f pet,k effect){return false;}static void finishFight(f pet){}static boolean combatActor(f x){return false;}static k startFight(f dog,f fox){return null;}}''',
            encoding='ascii')
        strings=folder/'GF3HomeData.java'
        strings.write_text(android_data(apk),encoding='ascii')
        subprocess.run(['javac','--release','8','-Xlint:-options','-g:none','-d',str(folder),
                        str(stub),str(strings),str(path),str(path.with_name('GF3ThiefClock.java'))],check=True)
        clock=ClassFile((folder/'GF3ThiefClock.class').read_bytes())
        for alias in ('heads','next'):
            clock.pool[clock.utf(alias)]=clock.pool[clock.utf('a')]
        helper=ClassFile((folder/'GF3HomePredator.class').read_bytes())
        for alias,real in (('gf3CreateAnimal','a'),('placing','a'),('redrawObjects','l'),
                           ('art','b'),('scroll','b'),('flags','a'),('animation','a'),
                           ('frame','b'),('treeStart','c'),('birth','e'),('feedStart','d'),
                           ('heads','a'),('next','a'),('owned','b'),('region','a'),
                           ('showControl','a'),('controls','a')):
            helper.pool[helper.utf(alias)]=helper.pool[helper.utf(real)]
        return {'GF3ThiefClock.class':convert_helper(clock.bytes()),
                'GF3HomePredator.class':convert_helper(helper.bytes()),
                'GF3HomeData.class':convert_helper((folder/'GF3HomeData.class').read_bytes())}


def link_home_save(data):
    state=ClassFile(data)
    for name,desc in (('read','(Ljava/lang/String;)[B'),('write','(Ljava/lang/String;[B)V')):
        state.pool[state.ref('GF3VisitPredators',name,desc)]=state.pool[state.ref('GF3HomePredator',name,desc)]
    return state.bytes()
