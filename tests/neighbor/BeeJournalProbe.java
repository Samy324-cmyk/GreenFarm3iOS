import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.util.Arrays;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Exercise the offline ledger, physical market cards and reward popups. */
final class BeeJournalProbe {
    private static Class<?> game,actor,sprite;
    private static int coinsBefore,xpBefore,marketWallet,pendingSku;

    private static Method method(Class<?> cls,String name,Class<?> result,Class<?>... args) {
        return MarketProbe.method(cls,name,result,args);
    }
    private static Object field(Class<?> cls,Object value,String name,Class<?> type)throws Exception {
        return MarketProbe.field(cls,value,name,type);
    }
    private static int n(String name)throws Exception {return (Integer)field(game,null,name,int.class);}
    private static int[] ints(String name)throws Exception {return (int[])field(game,null,name,int[].class);}
    private static int number(String name)throws Exception {
        return (Integer)method(game,name,int.class).invoke(null);
    }
    private static void tap(int x,int y)throws Exception {
        System.out.println("BEE tap "+x+","+y);
        MobilePlatform.pointerPressed(x,y);Thread.sleep(105);
        MobilePlatform.pointerReleased(x,y);Thread.sleep(380);
    }
    private static int[] rect(int menu,int control)throws Exception {
        short[] ctl=((short[][][])field(game,null,"a",short[][][].class))[menu][control];
        Object[] sheets=(Object[])field(game,null,"a",Array.newInstance(sprite,0).getClass());
        int[] r=new int[4];
        method(sprite,"a",void.class,int.class,int.class,int[].class,int.class)
            .invoke(sheets[ctl[5]],(int)ctl[6],0,r,0);
        r[0]+=ctl[2];r[1]+=ctl[3];return r;
    }
    private static void control(int menu,int index)throws Exception {
        int[] r=rect(menu,index);
        tap(479-r[1]-r[3]/2,r[0]+r[2]/2);
    }
    private static void screen(int expected)throws Exception {
        long end=System.currentTimeMillis()+14000;
        while(number("a")!=expected && System.currentTimeMillis()<end)Thread.sleep(90);
        if(number("a")!=expected)throw new AssertionError("screen "+number("a")+" expected "+expected+
                " ledger "+Arrays.toString(ints("bD"))+" statuses "+Arrays.toString(ints("cb")));
        Thread.sleep(450);
    }
    private static void swipe()throws Exception {
        MobilePlatform.pointerPressed(175,710);
        for(int i=1;i<=16;i++){Thread.sleep(25);MobilePlatform.pointerDragged(175,710-i*34);}
        MobilePlatform.pointerReleased(175,166);Thread.sleep(470);
    }
    private static void accept(int row)throws Exception {
        int id=9302+row-300;
        int slot=index(ints("bD"),id);
        if(slot<0) {
            // Make room in the four-entry log of the lower-level fixture.
            // Exercise the live quest scheduler with all prerequisites met.
            ints("bD")[0]=-1;ints("bE")[0]=-1;
            method(game,"u",boolean.class).invoke(null);
            slot=index(ints("bD"),id);
        }
        if(slot<0)throw new AssertionError("Scheduler did not offer "+id+" "+Arrays.toString(ints("bD")));
        if(ints("cb")[slot]==1) {
            method(game,"I",void.class,int.class).invoke(null,65575+slot);
            long deadline=System.currentTimeMillis()+16000;
            while(number("a")!=26 && System.currentTimeMillis()<deadline){
                if(number("a")==19){Thread.sleep(800);tap(145,450);}
                else Thread.sleep(100);
            }
            screen(26);
            if(ints("cb")[slot]!=2)throw new AssertionError("Journal did not accept "+id);
            control(5,57);screen(17);
        }
        System.out.println("BEE accepted "+id+" "+((String[])field(game,null,"i",String[].class))[slot]);
    }
    private static int index(int[] a,int v) {for(int i=0;i<a.length;i++)if(a[i]==v)return i;return -1;}
    private static void choose(int item)throws Exception {
        if(number("a")==17){tap(44,745);screen(7);}else screen(7);
        boolean hive=item==3022 || item==3023;
        control(2,hive?10:12);
        if(hive)control(2,56);
        int position=index(ints("V"),item);
        if(position<0)throw new AssertionError("Missing SKU "+item+" "+Arrays.toString(ints("V")));
        for(int attempt=0;attempt<10;attempt++){
            int local=position-n("ct");
            if(local>=0 && local<6){
                int[] r=rect(2,28+14*local);
                int center=r[0]+r[2]/2;
                if(center>40 && center<755){
                    // The premium card has an overlapping information hotspot. Its
                    // purchase strip runs below the image and above the card edge.
                    if(item==3023)tap(479-(r[1]+r[3]-24),center);
                    else control(2,28+14*local);
                    break;
                }
            }
            swipe();
        }
    }
    private static void market(int item)throws Exception {
        int cash=number("d");
        choose(item);
        screen(17);
        Object pending=field(game,null,"a",actor);
        if(pending==null || !(Integer.valueOf(item)).equals(field(actor,pending,"J",int.class)))
            throw new AssertionError("Missing placing actor "+item+" screen="+number("a")+" mode="+n("d"));
        // More than one empty tile can be chosen. The market positions the
        // item at a legal tile when possible, before the green check appears.
        for(int[] hit:(int[][])field(game,null,"i",int[][].class)) if(hit[5]==65598){
            tap(479-hit[1]-hit[3]/2,hit[0]+hit[2]/2);break;
        }
        marketWallet=cash;pendingSku=item;
    }
    private static void refuse(int item,String title)throws Exception {
        int coins=number("d"),cash=number("e");
        choose(item);
        screen(19);
        String actual=(String)field(game,null,"o",String.class),body=(String)field(game,null,"p",String.class);
        if(!actual.equals(title)||!body.contains("colmenas")||number("d")!=coins||number("e")!=cash)
            throw new AssertionError("Hive refusal title="+actual+" detail="+body+" wallet="+number("d")+"/"+number("e"));
        System.out.println("HIVE_REFUSED sku="+item+" title="+actual+" wallet="+coins+"/"+cash);
        control(4,11);Thread.sleep(600);
    }
    private static void takeStoredHive()throws Exception{
        screen(17);
        // Open the warehouse with the same state as tapping the barn, then select its native card.
        MarketProbe.variable(game,"dW",int.class).setInt(null,0);
        method(game,"a",void.class,int.class).invoke(null,28);
        screen(28);control(10,3);
        int position=-1;
        for(int i=0;i<n("dS");i++)if(ints("aD")[i]==4 && ints("aE")[i]==23)position=i;
        if(position<0)throw new AssertionError("Premium hive absent from warehouse cards");
        for(int attempt=0;attempt<16;attempt++){
            int relative=position-n("dT");
            if(relative>=0 && relative<6){
                int[] box=rect(10,13+relative*7);int x=box[0]+box[2]/2;
                if(x>35 && x<765){control(10,13+relative*7);return;}
            }
            swipe();
        }
        throw new AssertionError("Cannot reach stored hive");
    }
    private static void limits()throws Exception {
        Class<?> rules=Class.forName("GF3HiveLimits",true,game.getClassLoader());
        Method level=method(game,"X",void.class,int.class);
        Method stored=method(game,"d",void.class,int.class,int.class,int.class);
        Method owned=method(rules,"owned",int.class);
        Method trees=method(rules,"trees",int.class);
        level.invoke(null,15);method(game,"V",void.class,int.class).invoke(null,100000);
        method(game,"W",void.class,int.class).invoke(null,1500);
        int[] ledger=ints("cc");ledger[2]=9002;
        int[] ids={9297,9299,9301,9302,9303,9304,9305};
        for(int i=0;i<ids.length;i++)ledger[297+i]=ids[i];
        int initial=(Integer)trees.invoke(null);
        method(game,"aa",void.class,int.class).invoke(null,initial);
        if((Integer)owned.invoke(null)!=0 || (Integer)method(rules,"capacity",int.class).invoke(null)!=1)
            throw new AssertionError("Unexpected fixture inventory");
        stored.invoke(null,4,11,1);
        refuse(3022,"\u00a1Demasiadas colmenas!");
        stored.invoke(null,4,11,0);
        int coins=number("d");
        market(3022);Thread.sleep(850);
        if(number("d")!=coins-1000 || (Integer)owned.invoke(null)!=1 || (Integer)trees.invoke(null)!=initial)
            throw new AssertionError("Hive first unit / tree limit / wallet "+number("d")+" owned="+owned.invoke(null));
        System.out.println("HIVE_BOUGHT first=1000 trees="+initial+" hiveCap=1");
        refuse(3023,"\u00a1Demasiadas colmenas!");
        level.invoke(null,16);coins=number("d");
        market(3022);Thread.sleep(850);
        if(number("d")!=coins-2500 || (Integer)owned.invoke(null)!=2 || (Integer)trees.invoke(null)!=initial)
            throw new AssertionError("Hive second unit / tree limit / wallet "+number("d"));
        level.invoke(null,48);stored.invoke(null,4,11,18);
        refuse(3023,"\u00a1M\u00e1ximo de colmenas!");
        if(number("a")==7){control(2,113);screen(17);}
        int wallet=number("d"),bills=number("e");
        stored.invoke(null,4,11,19);
        takeStoredHive();screen(19);
        if(!field(game,null,"o",String.class).equals("\u00a1M\u00e1ximo de colmenas!") ||
           (Integer)method(game,"gf3Stored",int.class,int.class,int.class).invoke(null,4,11)!=19)
            throw new AssertionError("A rejected placement did not restore the warehouse unit");
        control(4,11);screen(17);
        stored.invoke(null,4,11,18);
        takeStoredHive();screen(17);
        Object selected=field(game,null,"a",actor);
        if(selected==null || (Integer)field(actor,selected,"J",int.class)!=3023 || n("d")!=4)
            throw new AssertionError("The stored premium hive did not enter placement");
        for(int[] hit:(int[][])field(game,null,"i",int[][].class))if(hit[5]==65598){
            tap(479-hit[1]-hit[3]/2,hit[0]+hit[2]/2);break;
        }
        Thread.sleep(500);
        if((Integer)owned.invoke(null)!=20 ||
           (Integer)method(game,"gf3Stored",int.class,int.class,int.class).invoke(null,4,11)!=17 ||
           (Integer)trees.invoke(null)!=initial || number("d")!=wallet || number("e")!=bills)
            throw new AssertionError("Incorrect warehouse restoration balance or placement");
        checkTreeAward(initial);
        System.out.println("HIVE_LIMITS_OK placed=3 stored=17 max=20 secondHiveCoins=2500");
    }

    private static void checkTreeAward(int initial)throws Exception {
        int row=index(ints("t"),3999);
        Method decode=method(game,"p",int.class,int.class);
        Method recount=method(game,"a",void.class,boolean.class);
        Method factory=method(game,"a",actor,int.class,int.class);
        Method flag=method(actor,"k",void.class,int.class);
        boolean[] finished=(boolean[])field(game,null,"d",boolean[].class);
        if(row!=6 || ints("w")[row]!=38 || (Integer)decode.invoke(null,ints("v")[row])!=15)
            throw new AssertionError("Missing original 15-tree award");
        recount.invoke(null,false);
        int observed=(Integer)decode.invoke(null,ints("u")[row]);
        if(observed!=initial || finished[row])
            throw new AssertionError("Hive actors counted as fruit trees: "+observed);
        for(int i=initial;i<14;i++)flag.invoke(factory.invoke(null,2,12),512);
        recount.invoke(null,false);
        if((Integer)decode.invoke(null,ints("u")[row])!=14 || finished[row])
            throw new AssertionError("The grove reward was granted before tree 15");
        flag.invoke(factory.invoke(null,2,12),512);
        recount.invoke(null,false);
        if(!finished[row] || (Integer)decode.invoke(null,ints("u")[row])!=15)
            throw new AssertionError("The 15th fruit tree did not complete achievement 3999");
        System.out.println("GROVE_3999_OK hives=3 trees=0,14,15");
    }
    static void run(String command)throws Exception {
        if(game==null){
            ClassLoader loader=Mobile.getPlatform().loader;
            game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);
            sprite=Class.forName("e",true,loader);
        }
        if(command.equals("limits")){limits();return;}
        if(command.equals("seed") || command.equals("candy")){
            method(game,"X",void.class,int.class).invoke(null,15);
            method(game,"V",void.class,int.class).invoke(null,100000);
            // Restore the prerequisite entries into their original indexed
            // positions. Every per-test purchase, dose and reward is live.
            int[] ledger=ints("cc");
            ledger[2]=9002;ledger[297]=9297;ledger[298]=9299;ledger[299]=9301;
            if(command.equals("candy")){
                for(int i=300;i<=302;i++)ledger[i]=9302+i-300;
                accept(303);
            }else accept(300);
        } else if(command.equals("ripen")){
            screen(11);
            int seconds=ints("al")[0];
            if(seconds!=300)throw new AssertionError("Honey candy timer was "+seconds);
            System.out.println("BEE candy realTimerSeconds="+seconds);
            Thread.sleep((seconds+1)*1000L);
            tap(119,368);Thread.sleep(750);tap(150,366);
        } else if(command.equals("sell")){
            screen(17);
            method(game,"a",void.class,int.class).invoke(null,8);
            screen(8);control(3,4);
            int pos=index(ints("Y"),121);
            if(pos<0 || pos>=15)throw new AssertionError("Candy is absent from selling tab");
            control(3,10+11*pos);control(3,195);
            int wallet=number("d");
            if(n("cC")!=pos || (int)method(game,"D",int.class).invoke(null)!=114)
                throw new AssertionError("Candy sale quote");
            control(3,201);screen(17);
            long end=System.currentTimeMillis()+18000;
            while(number("d")==wallet && System.currentTimeMillis()<end)Thread.sleep(80);
            int stock=(Integer)method(game,"g",int.class,int.class,int.class).invoke(null,0,121);
            if(stock!=0 || number("d")!=wallet+114)
                throw new AssertionError("Candy sale wallet="+number("d")+" stock="+stock+" previous="+wallet);
            System.out.println("BEE_SOLD_OK candy=4121 units=1 coins=114");
        } else if(command.equals("hive"))market(3022);
        else if(command.equals("extractor")){accept(301);market(1018);}
        else if(command.startsWith("reward")){
            int id=Integer.parseInt(command.substring(6));screen(26);
            int slot=index(ints("bD"),id);
            if(slot<0 || ints("cb")[slot]!=3)throw new AssertionError("Expected completed "+id);
            coinsBefore=number("d");xpBefore=number("x");
            if(pendingSku!=0){
                int price=pendingSku==3022?1000:25000;
                if(marketWallet-coinsBefore!=price)throw new AssertionError("Wrong market charge "+pendingSku+
                        ": "+marketWallet+" -> "+coinsBefore);
                System.out.println("BEE_PURCHASE_OK sku="+pendingSku+" coins="+price);
                pendingSku=0;
            }
            Thread.sleep(650);
            for(int attempt=0;attempt<3 && ints("bD")[slot]==id;attempt++){
                tap(55,479);Thread.sleep(850);
            }
            long timeout=System.currentTimeMillis()+8000;
            while(number("d")==coinsBefore && System.currentTimeMillis()<timeout)Thread.sleep(70);
            int coins=number("d")-coinsBefore,xp=number("x")-xpBefore;
            int expected=640+(id-9302)*40;
            if(coins!=expected || xp!=90 || ints("cc")[id-9302+300]!=id)
                throw new AssertionError("Wrong reward "+id+" coins="+coins+" xp="+xp);
            System.out.println("BEE_REWARD_OK id="+id+" coins="+coins+" xp="+xp);
        }
    }
}
