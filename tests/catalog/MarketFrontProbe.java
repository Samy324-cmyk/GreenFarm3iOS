import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Compare the live, touch-selected shelves to the independent Android table oracle. */
final class MarketFrontProbe {
    private static Class<?> game,sprite,front;
    private static List<String> expected;
    private static int cash,toyCount;

    private static int integer(Class<?> type,String key)throws Exception {
        return (Integer)MarketProbe.field(type,null,key,int.class);
    }
    private static void tap(int x,int y)throws Exception {
        MobilePlatform.pointerPressed(x,y);Thread.sleep(95);
        MobilePlatform.pointerReleased(x,y);Thread.sleep(280);
    }
    private static int[] rect(int idx)throws Exception {
        short[] item=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[2][idx];
        Object[] art=(Object[])MarketProbe.field(game,null,"a",Array.newInstance(sprite,0).getClass());
        int[] r=new int[4];
        MarketProbe.method(sprite,"a",void.class,int.class,int.class,int[].class,int.class)
            .invoke(art[item[5]],(int)item[6],0,r,0);
        r[0]+=item[2];r[1]+=item[3];
        return r;
    }
    private static void hit(int[] bounds)throws Exception {
        tap(479-bounds[1]-bounds[3]/2,bounds[0]+bounds[2]/2);
    }
    private static void scroll()throws Exception {
        MobilePlatform.pointerPressed(175,710);
        for(int i=1;i<=16;i++){Thread.sleep(25);MobilePlatform.pointerDragged(175,710-i*34);}
        MobilePlatform.pointerReleased(175,166);Thread.sleep(500);
    }
    private static int[] meta(int wanted) {
        return Arrays.stream(expected.get(wanted).split(" ")).mapToInt(Integer::parseInt).toArray();
    }

    private static void doghouse(String action)throws Exception {
        ClassLoader loader=Mobile.getPlatform().loader;
        Class<?> actor=Class.forName("f",true,loader);
        if(action.equals("seed-house")) {
            Class<?> house=Class.forName("GF3Doghouse",true,loader);
            Object placed=MarketProbe.method(house,"placed",actor,actor).invoke(null,new Object[]{null});
            if(placed!=null)MarketProbe.method(game,"c",void.class,actor).invoke(null,placed);
            MarketProbe.method(game,"f",void.class,int.class,int.class,boolean.class).invoke(null,298,0,false);
            ((int[])MarketProbe.field(game,null,"cb",int[].class))[0]=2;
            return;
        }
        Class<?> tutorial=Class.forName("GF3DogTutorial",true,loader);
        Method menu=MarketProbe.method(game,"a",int.class);
        long end=System.currentTimeMillis()+20000;
        while(System.currentTimeMillis()<end) {
            if((Integer)menu.invoke(null)==19) {Thread.sleep(600);tap(145,450);}
            if((Integer)menu.invoke(null)==7 && integer(tutorial,"phase")==1029
                    && (Boolean)MarketProbe.field(tutorial,null,"shelfReady",boolean.class))break;
            Thread.sleep(100);
        }
        int count=(Character)MarketProbe.field(game,null,"c",char.class);
        int[] ids=(int[])MarketProbe.field(game,null,"V",int[].class);
        int[] prices=(int[])MarketProbe.field(game,null,"Q",int[].class);
        int[] bills=(int[])MarketProbe.field(game,null,"R",int[].class);
        if((Integer)menu.invoke(null)!=7 || count!=3 || prices[0]!=0 || bills[0]!=0
                || !Arrays.equals(Arrays.copyOf(ids,count),new int[]{1014,1015,1016}))
            throw new AssertionError("Training doghouse shelf, phase="+integer(tutorial,"phase")+" screen="+menu.invoke(null));
        System.out.println("SHOP_TRAINING_OK items=1014,1015,1016 firstPrice=0");
    }

    private static void firstPlot(String action)throws Exception {
        Method menu=MarketProbe.method(game,"a",int.class);
        if(action.equals("seed-plot")) {
            int stage=integer(game,"C"),screen=(Integer)menu.invoke(null);
            if(stage!=5 || screen!=18)
                throw new AssertionError("Expected the first wheat harvest, tutorial="+stage+" menu="+screen);
            // Resume at the guided purchase, well after the initial six wheat.
            MarketProbe.variable(game,"C",int.class).setInt(null,39);
            MarketProbe.variable(game,"f",boolean.class).setBoolean(null,false);
            MarketProbe.variable(game,"g",boolean.class).setBoolean(null,false);
            return;
        }
        if(action.equals("open-plot")) {
            long end=System.currentTimeMillis()+12000;
            while((Integer)menu.invoke(null)!=19 && System.currentTimeMillis()<end)Thread.sleep(80);
            Thread.sleep(600);tap(145,450);
            end=System.currentTimeMillis()+8000;
            while(integer(game,"C")!=40 && System.currentTimeMillis()<end)Thread.sleep(80);
            Thread.sleep(500);tap(44,745);
            end=System.currentTimeMillis()+9000;
            while((integer(front,"first")!=9 || (Integer)menu.invoke(null)!=7)
                    && System.currentTimeMillis()<end)Thread.sleep(80);
            if(integer(game,"C")!=41 || integer(front,"first")!=9)
                throw new AssertionError("Expected crop families, tutorial="+integer(game,"C")+" menu="+menu.invoke(null));
            int count=(Character)MarketProbe.field(game,null,"c",char.class);
            if(count!=3)throw new AssertionError("Expected crops, trees and hives");
            hit(rect(42));
            if(integer(front,"first")!=9)throw new AssertionError("An unrelated category advanced the introduction");
            System.out.println("FIRST_PLOT_CATEGORIES count=3");
        } else if(action.equals("select-plot")) {
            hit(rect(28));
            if((Integer)menu.invoke(null)!=7 || integer(front,"shelf")!=9 || integer(game,"C")!=41)
                throw new AssertionError("The crop-family tap did not lead to the plot shelf");
            int[] ids=(int[])MarketProbe.field(game,null,"V",int[].class);
            if(ids[0]!=3000)throw new AssertionError("First crop shelf shows "+ids[0]);
            System.out.println("FIRST_PLOT_SHELF first=3000");
        } else if(action.equals("buy-plot")) {
            hit(rect(28));Thread.sleep(900);
            Class<?> actor=Class.forName("f",true,Mobile.getPlatform().loader);
            Object placing=MarketProbe.field(game,null,"a",actor);
            if(placing==null || (Integer)menu.invoke(null)!=18 || integer(game,"C")!=42)
                throw new AssertionError("Plot did not enter placement, tutorial="+integer(game,"C")+" menu="+menu.invoke(null));
            System.out.println("FIRST_PLOT_OK stage=42 actor="+MarketProbe.field(actor,placing,"J",int.class));
        } else {
            Class<?> actor=Class.forName("f",true,Mobile.getPlatform().loader);
            Method total=MarketProbe.method(actor,"a",int.class,int.class,int.class);
            Method coins=MarketProbe.method(game,"d",int.class);
            int before=(Integer)total.invoke(null,0,49),cashBefore=(Integer)coins.invoke(null);
            int[][] buttons=(int[][])MarketProbe.field(game,null,"i",int[][].class);
            for(int[] box:buttons)if(box[5]==65598 && box[2]>0 && box[3]>0){hit(box);break;}
            Thread.sleep(600);
            int after=(Integer)total.invoke(null,0,49),paid=cashBefore-(Integer)coins.invoke(null);
            boolean finished=action.equals("finish-plot");
            if((!finished && after!=before+1) || paid!=10)
                throw new AssertionError("Confirmed plot count "+before+" -> "+after+", paid "+paid);
            if(finished) {
                long end=System.currentTimeMillis()+8000;
                while((Integer)menu.invoke(null)!=19 && System.currentTimeMillis()<end)Thread.sleep(100);
                if(integer(game,"C")!=43 || (Integer)menu.invoke(null)!=19)
                    throw new AssertionError("Tomato lesson did not follow both plots, stage="+integer(game,"C"));
                System.out.println("FIRST_PLOT_COMPLETE stage=43 totalCoinsSpent=20");
            } else System.out.println("FIRST_PLOT_PLACED count="+after+" cost="+paid);
        }
    }
    private static void select(int id)throws Exception {
        int[] expectedRow=meta(id);
        int tab=expectedRow[0],position=expectedRow[1];
        hit(rect(tab==4?122:tab==5?14:10+tab));
        if(integer(front,"tab")!=tab) throw new AssertionError("Tab did not open "+tab);
        if(position>=0) {
            boolean visible=false;
            for(int attempt=0;attempt<4 && !visible;attempt++){
                int local=position-integer(game,"ct");
                if(local>=0 && local<6){
                    int[] box=rect(28+14*local);
                    int center=box[0]+box[2]/2;
                    if(box[2]>0 && center>38 && center<759){hit(box);visible=true;break;}
                }
                scroll();
            }
            if(!visible)throw new AssertionError("Could not touch category "+id);
        }
        if(integer(front,"shelf")!=id) throw new AssertionError("Selected shelf "+integer(front,"shelf")+" expected "+id);
        int[] actual=(int[])MarketProbe.field(game,null,"V",int[].class);
        int count=(Character)MarketProbe.field(game,null,"c",char.class);
        if(count!=expectedRow.length-2 || !Arrays.equals(Arrays.copyOf(actual,count),Arrays.copyOfRange(expectedRow,2,expectedRow.length)))
            throw new AssertionError("Live SKU mismatch for "+id+": "+Arrays.toString(actual));
        System.out.println("SHOP shelf="+id+" ids="+Arrays.toString(Arrays.copyOf(actual,count)));
    }
    static void run(String command)throws Exception {
        if(game==null){
            ClassLoader l=Mobile.getPlatform().loader;
            game=Class.forName("a",true,l);sprite=Class.forName("e",true,l);front=Class.forName("GF3MarketFront",true,l);
            expected=Files.readAllLines(Paths.get("shelves.txt"));
        }
        if(command.endsWith("-plot")) {
            firstPlot(command);
        } else if(command.equals("seed-house") || command.equals("doghouse")) {
            doghouse(command);
        } else if(command.equals("offers")) {
            hit(rect(14));
            short[][] entries=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[2];
            if(integer(front,"tab")!=5 || (Character)MarketProbe.field(game,null,"c",char.class)!=0 ||
                    entries[125][15]!=1 || entries[126][10]!=1)
                throw new AssertionError("Offline offers tab="+integer(front,"tab")+" count="+
                    (int)(Character)MarketProbe.field(game,null,"c",char.class)+" caption="+entries[125][15]+" sign="+entries[126][10]);
            System.out.println("SHOP_OFFLINE_OFFERS_OK");
        } else if(command.equals("buy")) {
            Class<?> toys=Class.forName("GF3DogToys",true,Mobile.getPlatform().loader);
            Method items=MarketProbe.method(toys,"quantity",int.class,int.class);
            Method wallet=MarketProbe.method(game,"d",int.class);
            toyCount=(Integer)items.invoke(null,0);cash=(Integer)wallet.invoke(null);
            hit(rect(28));Thread.sleep(550);
            if((Integer)items.invoke(null,0)!=toyCount+1 || (Integer)wallet.invoke(null)!=cash-125)
                throw new AssertionError("Purchasing a ball from the dedicated shelf failed");
            System.out.println("SHOP_BUY_OK item=7064 amount=1 coins=125");
        } else select(Integer.parseInt(command));
    }
}
