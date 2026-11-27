import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Array;
import java.lang.reflect.Method;
import org.recompile.mobile.MobilePlatform;

/** Buy missing mill ingredients with the native touchscreen and reopen the wallet and barn. */
final class MillProbe {
    private static Class<?> game, actor, sprite;

    private static int value(String name)throws Exception {
        return MarketProbe.variable(game,name,int.class).getInt(null);
    }
    private static int amount(String name)throws Exception {
        return (Integer)MarketProbe.method(game,name,int.class).invoke(null);
    }
    private static int stock(int row)throws Exception {
        return (Integer)MarketProbe.method(game,"g",int.class,int.class,int.class).invoke(null,0,row);
    }
    private static void screen(int expected)throws Exception {
        long until=System.currentTimeMillis()+6500;
        while(amount("a")!=expected && System.currentTimeMillis()<until)Thread.sleep(60);
        if(amount("a")!=expected)throw new AssertionError("Mill screen "+amount("a")+" expected "+expected);
        Thread.sleep(450);
    }
    private static void tap(int x,int y)throws Exception {
        System.out.println("MILL tap="+x+","+y+" screen="+amount("a"));
        MobilePlatform.pointerPressed(x,y);Thread.sleep(110);
        MobilePlatform.pointerReleased(x,y);Thread.sleep(475);
    }
    private static void button(int panel,int index)throws Exception {
        short[] row=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[panel][index];
        if(row[10]==0 || row[18]==0)throw new AssertionError("Disabled mill control "+panel+"/"+index);
        Object[] sheets=(Object[])MarketProbe.field(game,null,"a",Array.newInstance(sprite,0).getClass());
        int[] box=new int[4];
        MarketProbe.method(sprite,"a",void.class,int.class,int.class,int[].class,int.class)
            .invoke(sheets[row[5]],(int)row[6],0,box,0);
        int x=row[2]+box[0]+box[2]/2, y=row[3]+box[1]+box[3]/2;
        if(x<0 || x>=800 || y<0 || y>=480)throw new AssertionError("Mill button offscreen "+x+","+y);
        tap(479-y,x);
    }
    private static void visit()throws Exception {
        screen(17);
        Object list=Array.newInstance(actor,1);
        MarketProbe.method(actor,"a",int.class,int.class,int.class,int.class,list.getClass(),int.class)
            .invoke(null,0,50,14,list,1);
        Object mill=Array.get(list,0), camera=MarketProbe.field(game,null,"c",actor);
        if(mill==null)throw new AssertionError("Mill missing from test farm");
        MarketProbe.method(actor,"a",void.class,int.class,int.class,int.class).invoke(camera,
            MarketProbe.field(actor,mill,"r",int.class),MarketProbe.field(actor,mill,"s",int.class),0);
        Thread.sleep(900);
        int u=(Integer)MarketProbe.field(actor,mill,"u",int.class), v=(Integer)MarketProbe.field(actor,mill,"v",int.class);
        for(int up:new int[]{34,60,15}) {tap(479-v+up,u);if(amount("a")==27)break;}
        screen(27);
    }
    private static void recipe(int index)throws Exception {
        if(!MarketProbe.variable(game,"aF",boolean.class).getBoolean(null)) {
            button(22,159);Thread.sleep(650);
        }
        if(index>3){
            MobilePlatform.pointerPressed(120,680);Thread.sleep(100);
            for(int y=640;y>=240;y-=40){MobilePlatform.pointerDragged(120,y);Thread.sleep(55);}
            MobilePlatform.pointerReleased(120,240);Thread.sleep(800);
        }
        button(22,96+9*(index-value("dp")));screen(9);
        if(value("dD")!=6500+index)throw new AssertionError("Opened the wrong mill recipe");
    }
    private static void charges(int index,int first,int second,int xp,int minutes)throws Exception {
        recipe(index);
        if(value("dD")!=6500+index || value("dK")!=first || value("dL")!=second ||
           value("dx")!=xp || value("dy")!=minutes*60)throw new AssertionError("Wrong mill recipe "+index+
               " id="+value("dD")+" prices="+value("dK")+","+value("dL")+" XP="+value("dx")+" time="+value("dy"));
        for(int i=0;i<2;i++) {
            int ingredient=value(i==0?"dG":"dH"),need=value(i==0?"dI":"dJ"),price=i==0?first:second;
            int wallet=amount("e");
            if(stock(ingredient)!=0)throw new AssertionError("Test ingredient not empty "+ingredient);
            button(6,i==0?7:12);
            if(amount("e")!=wallet-price || stock(ingredient)!=need)
                throw new AssertionError("Mill charge did not restore ingredient "+ingredient+" for "+price);
            System.out.println("MILL_CHARGED recipe="+value("dD")+" ingredient="+ingredient+" stock=0->"+need+
                    " bills="+wallet+"->"+amount("e"));
        }
    }
    private static void puppyLesson()throws Exception {
        recipe(6);
        if(value("dK")!=3 || value("dL")!=3 || value("dy")!=120 || value("dA")!=2)
            throw new AssertionError("Normal dog feed should cost bills and take two minutes");
        button(6,31);screen(27);
        // Model the already accepted 9297 quest only. All purchases and the queue
        // below still use the running game's unmodified touchscreen handlers.
        ((int[])MarketProbe.field(game,null,"bD",int[].class))[0]=9297;
        ((int[])MarketProbe.field(game,null,"cb",int[].class))[0]=2;
        recipe(6);
        if(value("dK")!=0 || value("dL")!=0 || value("dy")!=0 || value("dA")!=0)
            throw new AssertionError("The first puppy's feed is not free and immediate");
        int bills=amount("e");
        for(int i=0;i<2;i++){
            int ingredient=value(i==0?"dG":"dH"),need=value(i==0?"dI":"dJ");
            if(stock(ingredient)<need)button(6,i==0?7:12);
            if(stock(ingredient)<need || amount("e")!=bills)
                throw new AssertionError("The puppy lesson charged for missing supplies");
        }
        int queued=value("dm");
        button(6,26);
        if(value("dm")!=queued+1 || amount("e")!=bills)throw new AssertionError("Puppy feed was not queued");
        System.out.println("MILL_LESSON_OK normal=3,3,120,2 lesson=0,0,0,0 savedBills="+bills);
    }
    static void check(ClassLoader loader,boolean reload)throws Exception {
        game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);sprite=Class.forName("e",true,loader);
        screen(17);
        int[] products={7,6,10,11};
        if(reload) {
            try(DataInputStream in=new DataInputStream(new FileInputStream("mill-wallet.bin"))) {
                if(in.readInt()!=amount("e"))throw new AssertionError("Wallet changed after restart");
                for(int row:products)if(in.readInt()!=stock(row))throw new AssertionError("Ingredient lost "+row);
            }
            visit();
            puppyLesson();
            System.out.println("MILL-RELOAD_OK savedBills="+amount("e")+" ingredients=4");
            return;
        }
        // Give this loaded level-15 fixture an empty barn for the four inputs.
        Method add=MarketProbe.method(game,"a",boolean.class,int.class,int.class,int.class);
        for(int row:products)if(stock(row)>0)add.invoke(null,0,row,-stock(row));
        int before=amount("e");
        visit();
        charges(2,3,2,5,10);
        button(6,31);screen(27);
        charges(5,4,4,8,30);
        if(amount("e")!=before-13)throw new AssertionError("Wallet debit across both recipes");
        try(DataOutputStream out=new DataOutputStream(new FileOutputStream("mill-wallet.bin"))) {
            out.writeInt(amount("e"));for(int row:products)out.writeInt(stock(row));
        }
        System.out.println("MILL_OK paid=13 xp=5,8 times=600,1800");
    }
}
