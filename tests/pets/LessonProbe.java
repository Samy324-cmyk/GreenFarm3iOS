import java.lang.reflect.Array;
import java.lang.reflect.Method;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Touch through the original doghouse and toy lesson after the first fox. */
final class LessonProbe {
    private static Class<?> game,actor,lesson,house,dogs,toys;
    private static Object dog;
    private static int wallet,balls;

    private static Class<?> type(String name)throws Exception {
        return Class.forName(name,true,Mobile.getPlatform().loader);
    }
    private static Object field(Class<?> cls,Object value,String name,Class<?> type)throws Exception {
        return MarketProbe.field(cls,value,name,type);
    }
    private static Method method(Class<?> cls,String name,Class<?> result,Class<?>... args) {
        return MarketProbe.method(cls,name,result,args);
    }
    private static int integer(Class<?> cls,String name)throws Exception {
        return (Integer)field(cls,null,name,int.class);
    }
    private static int number(String name)throws Exception {
        return (Integer)method(game,name,int.class).invoke(null);
    }
    private static void waitFor(int phase,int menu)throws Exception {
        long end=System.currentTimeMillis()+26000;
        while(System.currentTimeMillis()<end){
            if(integer(lesson,"phase")==phase && number("a")==menu){Thread.sleep(500);return;}
            Thread.sleep(90);
        }
        throw new AssertionError("Lesson "+integer(lesson,"phase")+"/"+number("a")+
            " expected "+phase+"/"+menu);
    }
    private static void tap(int x,int y)throws Exception {
        MobilePlatform.pointerPressed(x,y);Thread.sleep(105);
        MobilePlatform.pointerReleased(x,y);Thread.sleep(390);
    }
    private static void control(int id)throws Exception {
        for(int[] h:(int[][])field(game,null,"i",int[][].class)){
            if(h[5]==id && h[2]>0 && h[3]>0){
                tap(479-h[1]-h[3]/2,h[0]+h[2]/2);return;
            }
        }
        throw new AssertionError("Missing touch target "+id+" screen "+number("a"));
    }
    private static void dialog(int phase)throws Exception {
        waitFor(phase,19);Thread.sleep(600);control(262148);
    }
    private static void market(int tab)throws Exception {
        method(game,"d",void.class,int.class,int.class,boolean.class).invoke(null,tab,3,true);
    }
    private static void dogTap()throws Exception {
        Class<?> animation=type("k"),sheet=type("e");
        Object pose=field(actor,dog,"a",animation);
        Object[] art=(Object[])field(game,null,"b",Array.newInstance(sheet,0).getClass());
        int[] r=new int[4];
        method(sheet,"a",void.class,int[].class,int.class,int.class,int.class,int.class,int.class)
            .invoke(art[(Integer)field(actor,dog,"E",int.class)],r,
                method(animation,"a",int.class).invoke(pose),method(animation,"b",int.class).invoke(pose),
                0,0,(Integer)field(animation,pose,"a",int.class));
        int zoom=integer(game,"B"),u=(Integer)field(actor,dog,"u",int.class),v=(Integer)field(actor,dog,"v",int.class);
        tap(479-v-(r[1]+r[3])*zoom/200,u+(r[0]+r[2])*zoom/200);
    }
    static void run(String command)throws Exception {
        if(game==null){
            game=type("a");actor=type("f");lesson=type("GF3DogTutorial");house=type("GF3Doghouse");
            dogs=type("GF3Dogs");toys=type("GF3DogToys");
        }
        if(command.equals("seed")){
            method(game,"X",void.class,int.class).invoke(null,10);
            ((int[])field(game,null,"cc",int[].class))[297]=9297;
            dog=method(game,"a",actor,int.class,int.class).invoke(null,0,70);
            method(game,"a",void.class,actor,boolean.class).invoke(null,dog,false);
            method(game,"fI",void.class).invoke(null);
            method(dogs,"setStats",void.class,actor,int.class,int.class,int.class).invoke(null,dog,15,0,1);
            // The lesson starts with the just-adopted, grown beagle. Give the
            // owned silo one feed so its normal hunger prompt can be satisfied.
            method(game,"q",void.class,int.class,int.class).invoke(null,6,1);
            method(game,"f",void.class,int.class,int.class,boolean.class).invoke(null,298,0,false);
            ((int[])field(game,null,"cb",int[].class))[0]=2;
            wallet=number("d");
            balls=(Integer)method(toys,"quantity",int.class,int.class).invoke(null,0);
        }else if(command.equals("house")){
            waitFor(1026,17);market(3);
            dialog(1027);dialog(1028);dialog(1029);waitFor(1029,7);
            int row=((int[])field(game,null,"M",int[].class))[0],price=((int[])field(game,null,"Q",int[].class))[0];
            if(row!=24 || price!=0)throw new AssertionError("Expected free house");
            tap(81,128);waitFor(1029,17);control(65598);dialog(1031);
            waitFor(1031,17);
            Object building=method(house,"placed",actor,actor).invoke(null,new Object[]{null});
            if(building==null || number("d")!=wallet)throw new AssertionError("Free house missing");
            method(house,"openBuilding",boolean.class,int.class).invoke(null,24);
            dialog(1033);waitFor(1033,48);control(1835079);waitFor(1034,48);
            if(number("d")!=wallet+50)throw new AssertionError("Doghouse reward "+(number("d")-wallet));
            System.out.println("LESSON_HOUSE_OK house=1014 bonus=50");
        }else if(command.equals("ball")){
            control(1835064);dialog(1036);waitFor(1036,7);
            int[] row=(int[])field(game,null,"M",int[].class),price=(int[])field(game,null,"Q",int[].class);
            if(row[0]!=64 || price[0]!=0)throw new AssertionError("Expected free ball");
            tap(81,128);waitFor(1037,7);
            int qty=(Integer)method(toys,"quantity",int.class,int.class).invoke(null,0);
            if(qty!=balls+1 || price[0]!=125)throw new AssertionError("Bonus ball/regular price "+qty+"/"+price[0]);
            control(131185);waitFor(1038,17);
            System.out.println("LESSON_BALL_OK gift=1 regularPrice=125");
        }else if(command.equals("play")){
            waitFor(1038,17);
            dog=method(house,"resident",actor,actor).invoke(null,new Object[]{null});
            Thread.sleep(1100);
            dogTap();
            // If the first press serves the dog a meal, let it walk to the
            // farmer and finish its native eating animation before playing.
            if(field(toys,null,"selected",actor)==null)Thread.sleep(9500);
            long end=System.currentTimeMillis()+22000;
            while(field(toys,null,"selected",actor)==null && System.currentTimeMillis()<end){
                if(number("a")!=17)throw new AssertionError("Dog tap opened "+number("a"));
                System.out.println("LESSON dog state="+field(actor,dog,"D",int.class)+" flags="+field(actor,dog,"C",int.class));
                dogTap();Thread.sleep(950);
            }
            if(field(toys,null,"selected",actor)==null)throw new AssertionError("Dog's toy wheel did not open");
            Method pointer=method(toys,"pointer",boolean.class,int.class,int.class,int.class);
            int offset=integer(game,"aF");
            pointer.invoke(null,60,400,0);pointer.invoke(null,60,520,2);pointer.invoke(null,60,520,1);
            Thread.sleep(350);
            if(integer(game,"aF")==offset)throw new AssertionError("Pet ribbon did not scroll");
            pointer.invoke(null,300,400,0);pointer.invoke(null,300,400,1);
            Thread.sleep(350);
            if(field(toys,null,"selected",actor)!=null)throw new AssertionError("Outside touch did not dismiss pet ribbon");
            dogTap();Thread.sleep(500);
            if(field(toys,null,"selected",actor)==null)throw new AssertionError("Pet ribbon did not reopen");
            int prev=(Integer)method(dogs,"xp",int.class,actor).invoke(null,dog);
            int oldQty=(Integer)method(toys,"quantity",int.class,int.class).invoke(null,0);
            control(65603);
            Thread.sleep(250);
            int animation=(Integer)method(type("k"),"a",int.class).invoke(field(actor,dog,"a",type("k")));
            if(animation!=17)throw new AssertionError("Ball animation did not begin: "+animation);
            if((Integer)method(toys,"quantity",int.class,int.class).invoke(null,0)!=oldQty-1)
                throw new AssertionError("Toy consumption");
            waitFor(0,26);
            int xp=(Integer)method(dogs,"xp",int.class,actor).invoke(null,dog);
            long day=(Long)field(type("GF3ThiefClock"),null,"day",long.class);
            if(xp!=prev+3 || day<=0)throw new AssertionError("Play reward "+prev+" -> "+xp+" day="+day);
            int cash=number("d"),score=number("x");
            int[] active=(int[])field(game,null,"bD",int[].class);
            int slot=integer(game,"fE");
            if(active[slot]!=9299)throw new AssertionError("Reward popup for "+active[slot]+", expected 9299");
            Thread.sleep(650);
            for(int i=0;i<3 && active[slot]==9299;i++){tap(55,479);Thread.sleep(850);}
            end=System.currentTimeMillis()+12000;
            while(number("d")==cash && System.currentTimeMillis()<end)Thread.sleep(90);
            if(number("d")!=cash+200 || number("x")!=score+10
                    || ((int[])field(game,null,"cc",int[].class))[298]!=9299)
                throw new AssertionError("Wrong 9299 journal payout coins="+cash+"->"+number("d")+
                        " xp="+score+"->"+number("x")+" menu="+number("a")+" slot="+active[slot]);
            System.out.println("LESSON_REWARD_OK id=9299 dogXP=3 coins=200 xp=10");
        }
    }
}
