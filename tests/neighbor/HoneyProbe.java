import java.lang.reflect.Array;
import java.lang.reflect.Method;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Physical input through the 4.4.4 honey lesson from a controlled level-15 farm. */
final class HoneyProbe {
    private static Class<?> game,actor,lesson,sprite;
    private static Object colony;
    private static Object field(Class<?> c,Object obj,String key,Class<?> type)throws Exception {
        return MarketProbe.field(c,obj,key,type);
    }
    private static Method method(Class<?> c,String name,Class<?> out,Class<?>...args) {
        return MarketProbe.method(c,name,out,args);
    }
    private static int stage()throws Exception {return (Integer)field(lesson,null,"stage",int.class);}
    private static int screen()throws Exception {return (Integer)method(game,"a",int.class).invoke(null);}
    private static int stock(int n)throws Exception {return (Integer)method(game,"g",int.class,int.class,int.class).invoke(null,0,n);}
    private static int n(Object obj,String key)throws Exception {return (Integer)field(actor,obj,key,int.class);}
    private static void waitFor(int expected,int menu)throws Exception {
        long end=System.currentTimeMillis()+10000;
        while((stage()!=expected || screen()!=menu) && System.currentTimeMillis()<end) Thread.sleep(80);
        if(stage()!=expected || screen()!=menu) throw new AssertionError("Honey "+stage()+"/"+screen()+" expected "+expected+"/"+menu);
        System.out.println("HONEY phase="+expected+" menu="+menu);
    }
    private static void tap(int x,int y)throws Exception {
        System.out.println("HONEY tap="+x+","+y);
        MobilePlatform.pointerPressed(x,y);Thread.sleep(105);MobilePlatform.pointerReleased(x,y);Thread.sleep(370);
    }
    private static void dialog(int state)throws Exception {
        waitFor(state,19);Thread.sleep(700);tap(145,450);
        if(screen()==19 && stage()==state) tap(145,450);
    }
    private static void actorTap(Object target)throws Exception {
        tap(480-n(target,"v")+32,n(target,"u"));
    }
    private static void ui(int gui,int i)throws Exception {
        short[] c=((short[][][])field(game,null,"a",short[][][].class))[gui][i];
        Object[] sheets=(Object[])field(game,null,"a",Array.newInstance(sprite,0).getClass());
        int[] hit=new int[4];
        method(sprite,"a",void.class,int.class,int.class,int[].class,int.class).invoke(sheets[c[5]],(int)c[6],0,hit,0);
        int x=c[2]+hit[0]+hit[2]/2, y=c[3]+hit[1]+hit[3]/2;
        tap(479-y,x);
    }
    static void run(String action)throws Exception {
        if(game==null) {
            ClassLoader loader=Mobile.getPlatform().loader;
            game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);
            sprite=Class.forName("e",true,loader);lesson=Class.forName("GF3HoneyTutorial",true,loader);
        }
        if(action.equals("seed")) {
            method(game,"X",void.class,int.class).invoke(null,15);
            colony=method(game,"a",actor,int.class,int.class).invoke(null,2,22);
            method(game,"a",void.class,actor,boolean.class).invoke(null,colony,false);
            method(game,"fI",void.class).invoke(null);
            if(n(colony,"J")!=3022) throw new AssertionError("Wrong hive");
            method(game,"a",boolean.class,int.class,int.class,int.class).invoke(null,0,119,-stock(119));
            method(game,"f",void.class,int.class,int.class,boolean.class).invoke(null,302,0,false);
            ((int[])field(game,null,"cb",int[].class))[0]=2;
            System.out.println("HONEY seed pos="+n(colony,"r")+","+n(colony,"s")+" nativeState="+n(colony,"D"));
        } else if(action.equals("intro")) {
            dialog(1061);
            if(stage()==1062) {
                dialog(1062);waitFor(1064,17);
                HomeProbe.run("raid-win");dialog(1065);
                System.out.println("HONEY_PREDATOR_OK");
            }
            waitFor(1066,17);Thread.sleep(1100);
            actorTap(colony);
            waitFor(1067,17);ui(1,3);
            dialog(1068);
            waitFor(1069,17);
        } else if(action.equals("harvest")) {
            for(int i=0;i<6 && stage()==1069 && n(colony,"D")==3;i++) {
                actorTap(colony);Thread.sleep(350);
            }
            // The loose item bounces, then the native farm transfers it into the barn.
            // Tapping its previous position can activate a building beneath a moving drop.
            boolean sawComb=false;
            long deadline=System.currentTimeMillis()+10000;
            while(stage()==1069 && System.currentTimeMillis()<deadline) {
                Object[] layers=(Object[])field(actor,null,"a",Array.newInstance(actor,0).getClass());
                for(Object drop=layers[2];drop!=null;drop=field(actor,drop,"a",actor)) {
                    if(n(drop,"q")==47 && n(drop,"X")==59 && n(drop,"aa")==((3<<16)|119)) {
                        if(!sawComb) System.out.println("HONEY comb arc="+
                            (n(drop,"r")<n(drop,"Y")?"left":"right")+" quantity=3");
                        sawComb=true;
                    }
                }
                Thread.sleep(80);
            }
            if(!sawComb) throw new AssertionError("No three-comb harvest drop appeared");
            if(stock(119)!=3) throw new AssertionError("Harvest yielded "+stock(119));
            dialog(1070);waitFor(1071,28);Thread.sleep(750);tap(438,750);
            dialog(1072);waitFor(1073,17);
            colony=method(lesson,"colony",actor).invoke(null);
            Thread.sleep(700);
            System.out.println("HONEY smoker phase="+stage()+" state="+n(colony,"D")+" id="+n(colony,"J")+
                " smokeSeen="+field(lesson,null,"smoked",boolean.class)+" screen="+screen());
            if(n(colony,"D")!=5) throw new AssertionError("Hive did not need the smoker");
            for(int i=0;i<4 && n(colony,"D")==5;i++){actorTap(colony);Thread.sleep(450);}
            dialog(1074);waitFor(1075,17);
            if(!(Boolean)field(lesson,null,"smoked",boolean.class))throw new AssertionError("Smoker did not run");
            System.out.println("HONEY_SMOKER_OK hive grew again after cleaning");
        } else if(action.equals("checkpoint") || action.equals("restored")) {
            waitFor(1075,17);
            if(stock(119)!=3 || stock(120)!=0 || !(Boolean)field(lesson,null,"smoked",boolean.class) ||
                    !(Boolean)field(lesson,null,"harvested",boolean.class))
                throw new AssertionError("Hive progress or stock lost");
            System.out.println(action.equals("checkpoint")?"HONEY_SAVE_OK":"HONEY_RELOAD_OK");
        } else if(action.equals("press")) {
            Object machine=method(lesson,"find",actor,int.class,int.class).invoke(null,50,28);
            Thread.sleep(850);
            for(int i=0;i<3 && stage()==1075;i++) actorTap(machine);
            dialog(1076);waitFor(1077,11);
            tap(330,140);waitFor(1078,11);
            if(stock(119)!=4) throw new AssertionError("Free fourth honeycomb missing");
            tap(104,136);waitFor(1079,11);
            if(stock(119)!=0 || stock(120)!=1)throw new AssertionError("Tutorial extraction inventory");
            tap(435,751);dialog(1081);
            int[] status=(int[])field(game,null,"cb",int[].class);
            for(int i=0;i<60 && status[0]!=3;i++)Thread.sleep(100);
            if(status[0]!=3) throw new AssertionError("Quest still active");
            System.out.println("HONEY_OK quest=9304 nativeCombYield=3 guideGift=1 honeyJars=1");
        }
    }
}
