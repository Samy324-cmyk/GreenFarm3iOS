import java.lang.reflect.Array;
import java.util.Arrays;
import java.util.Random;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** A local request from Harold while the last opened card belongs to Edwina. */
final class MailboxProbe {
    private static Class<?> game, sprite;
    private static Object field(String name,Class<?> type)throws Exception {
        return MarketProbe.field(game,null,name,type);
    }
    private static int[] ints(String name)throws Exception{return (int[])field(name,int[].class);}
    private static boolean flag(String name,int slot)throws Exception{return ((boolean[])field(name,boolean[].class))[slot];}
    private static int value(String name)throws Exception{return (Integer)field(name,int.class);}
    private static int amount(String name)throws Exception{return (Integer)MarketProbe.method(game,name,int.class).invoke(null);}
    private static int stock(int row)throws Exception {
        return (Integer)MarketProbe.method(game,"gf3Stored",int.class,int.class,int.class).invoke(null,0,row);
    }
    private static int[][] friends()throws Exception{return (int[][])field("e",int[][].class);}
    private static long[][] clocks()throws Exception{return (long[][])field("a",long[][].class);}
    private static void tap(int x,int y)throws Exception {
        System.out.println("MAIL touch "+x+","+y+" screen="+amount("a"));
        MobilePlatform.pointerPressed(479-y,x);Thread.sleep(110);
        MobilePlatform.pointerReleased(479-y,x);Thread.sleep(420);
    }
    private static void screen(int page)throws Exception {
        long end=System.currentTimeMillis()+5500;
        while(amount("a")!=page && System.currentTimeMillis()<end)Thread.sleep(80);
        if(amount("a")!=page)throw new AssertionError("Expected "+page+" got "+amount("a"));
        Thread.sleep(450);
    }
    private static void control(int page,int index)throws Exception {
        short[] w=((short[][][])field("a",short[][][].class))[page][index];
        if(w[10]==0 || w[18]==0)throw new AssertionError("Inactive control "+page+"/"+index+" "+Arrays.toString(w));
        Object[] sheets=(Object[])field("a",Array.newInstance(sprite,0).getClass());
        int[] box=new int[4];
        MarketProbe.method(sprite,"a",void.class,int.class,int.class,int[].class,int.class)
            .invoke(sheets[w[5]],(int)w[6],0,box,0);
        tap(w[2]+box[0]+box[2]/2,w[3]+box[1]+box[3]/2);
    }
    private static void choose(int row)throws Exception {
        screen(38);
        short[] title=((short[][][])field("a",short[][][].class))[9][13+11*row];
        tap(title[2]+title[5]/2,249);screen(37);
        if(value("eS")!=row)throw new AssertionError("Wrong neighbor");
    }
    private static void message()throws Exception {
        screen(19);Thread.sleep(850);
        VisitsProbe.photograph("carta-"+value("eS"));tap(400,306);
        screen(37);
    }
    private static void selectGift(int product)throws Exception {
        control(17,3);screen(16);
        short[] ids=(short[])field("y",short[].class);
        int at=0;while(at<value("eg") && ids[at]!=product)at++;
        if(at==value("eg"))throw new AssertionError("Gift SKU absent "+product);
        System.out.println("MAIL gift sku="+product+" position="+at);
        for(int n=0;n<10;n++){
            int local=at-value("ef");
            if(local>=0 && local<6){
                short[] row=((short[][][])field("a",short[][][].class))[10][13+7*local];
                int x=row[2]+row[5]/2;
                if(x>=50 && x<=740){tap(x,225);Thread.sleep(700);message();return;}
            }
            MobilePlatform.pointerPressed(229,680);
            for(int gap=1;gap<=12;gap++){Thread.sleep(28);MobilePlatform.pointerDragged(229,680-37*gap);}
            MobilePlatform.pointerReleased(229,236);Thread.sleep(480);
        }
        throw new AssertionError("Could not scroll to gift "+product);
    }
    private static void request()throws Exception {
        control(17,8);screen(15);
        int row=ints("aM")[0],before=stock(row);
        Class<?> lib=Class.forName("g",true,game.getClassLoader());
        Random rng=(Random)MarketProbe.field(lib,null,"a",Random.class);
        long seed=0;while(Math.abs(new Random(seed).nextInt())%100!=0)seed++;
        // The original gift acceptance is probabilistic. Keep its native draw
        // repeatable while exercising the same callback as a normal touch.
        rng.setSeed(seed);tap(105,225);Thread.sleep(700);message();
        if(friends()[0][4]!=row || clocks()[0][1]<=0 || stock(row)!=before)
            throw new AssertionError("Request was not accepted or inventory credited before collection");
        System.out.println("MAIL_REQUEST_PENDING row="+row+" previousInventory="+before);
    }
    private static void setup()throws Exception {
        MarketProbe.method(game,"X",void.class,int.class).invoke(null,12);
        ints("cc")[2]=9002;
        int[] quests={48,73,61};
        for(int i=0;i<quests.length;i++){
            MarketProbe.method(game,"f",void.class,int.class,int.class,boolean.class).invoke(null,quests[i],i,true);
            ints("cb")[i]=2;
        }
        // Complete the original recipe prerequisites in the disposable save.
        // The actual donations and inventory changes are performed by touch.
        for(int row:new int[]{70,75})MarketProbe.method(game,"d",void.class,int.class,int.class,int.class).invoke(null,0,row,1);
        int unit=ints("d")[25];
        friends()[1][1]=3*unit-1;
        System.out.println("MAIL initial friendship="+friends()[1][1]+" firstHeart="+3*unit+
            " quests="+Arrays.toString(Arrays.copyOf(ints("bD"),3)));
    }
    static void run()throws Exception {
        ClassLoader loader=Mobile.getPlatform().loader;
        game=Class.forName("a",true,loader);sprite=Class.forName("e",true,loader);
        screen(17);
        synchronized(Class.forName("GF3Presentation",false,loader)){setup();}
        tap(431,174);screen(38);choose(0);
        request();
        selectGift(4075);
        if(stock(75)!=0 || !flag("l",0) || !flag("j",1) || clocks()[0][4]<=0)
            throw new AssertionError("Jam or gift to Harold not credited");
        control(17,49);screen(38);choose(1);
        int friendship=friends()[1][1];
        selectGift(4070);
        if(stock(70)!=0 || !flag("k",0) || !flag("k",1) || clocks()[1][4]<=0 || friends()[1][1]<=friendship)
            throw new AssertionError("Pie or gift to Edwina not credited");
        control(17,49);screen(38);
        if(!flag("j",2))throw new AssertionError("Friendship heart objective not credited");
        if(value("eS")!=1 || friends()[0][4]<0)throw new AssertionError("Missing cross-neighbor test");
        VisitsProbe.photograph("buzon-de-harold");
        int pending=friends()[0][4],inventory=stock(pending),coins=amount("d"),xp=amount("x");
        control(9,14);
        if(stock(pending)!=inventory+1 || friends()[0][4]!=-1 || !flag("j",0))
            throw new AssertionError("Requested item not credited to Harold");
        control(9,145);screen(26);VisitsProbe.photograph("un-vecindario-amistoso");
        for(int i=0;i<3 && ints("bD")[0]==9047;i++){tap(479,424);Thread.sleep(550);}
        long end=System.currentTimeMillis()+9000;
        while(amount("d")==coins && System.currentTimeMillis()<end)Thread.sleep(60);
        if(amount("d")!=coins+350 || amount("x")!=xp+40)throw new AssertionError("Wrong 9047 reward");
        System.out.println("MAILBOX_OK quest=9047 coins=350 xp=40 giftRows=70,75 collected="+pending+
            " sender=99990 lastProfile=99991 friendship="+friends()[1][1]+" heart=true");
    }
}
