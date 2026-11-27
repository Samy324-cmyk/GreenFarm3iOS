import java.awt.image.BufferedImage;
import java.io.File;
import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Random;
import javax.imageio.ImageIO;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Exercise the pond from its land contract, farm actor, poles and water ripples. */
final class PondProbe {
    private static Class<?> game, actor, sprite, base;
    private static int number(String key)throws Exception {
        return (Integer)MarketProbe.field(game,null,key,int.class);
    }
    private static int amount(String key)throws Exception {
        return (Integer)MarketProbe.method(game,key,int.class).invoke(null);
    }
    private static void set(String key,int value)throws Exception {
        MarketProbe.variable(game,key,int.class).setInt(null,value);
    }
    private static void tap(int x,int y)throws Exception {
        System.out.println("POND touch "+x+","+y+" screen="+amount("a"));
        MobilePlatform.pointerPressed(x,y);Thread.sleep(100);
        MobilePlatform.pointerReleased(x,y);Thread.sleep(400);
    }
    private static void screen(int want)throws Exception {
        long end=System.currentTimeMillis()+8000;
        while(amount("a")!=want && System.currentTimeMillis()<end)Thread.sleep(100);
        if(amount("a")!=want)throw new AssertionError("Expected pond screen "+want+" got "+amount("a"));
        Thread.sleep(400);
    }
    private static void shot(String name)throws Exception {
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        BufferedImage image=new BufferedImage(480,800,BufferedImage.TYPE_INT_RGB);
        synchronized(lcd){image.setRGB(0,0,480,800,lcd.getDataBuffer(),0,480);}
        ImageIO.write(image,"png",new File(name+".png"));
    }
    private static void button(int page,int index)throws Exception {
        short[] row=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[page][index];
        if(row[10]==0 || row[18]==0)throw new AssertionError("Inactive pond button "+page+"/"+index);
        Object[] sheets=(Object[])MarketProbe.field(game,null,"a",Array.newInstance(sprite,0).getClass());
        int[] box=new int[4];
        MarketProbe.method(sprite,"a",void.class,int.class,int.class,int[].class,int.class)
            .invoke(sheets[row[5]],(int)row[6],0,box,0);
        tap(479-row[3]-box[1]-box[3]/2,row[2]+box[0]+box[2]/2);
    }
    private static Object pond()throws Exception {
        Object list=Array.newInstance(actor,1);
        MarketProbe.method(actor,"a",int.class,int.class,int.class,int.class,list.getClass(),int.class)
            .invoke(null,0,50,17,list,1);
        return Array.get(list,0);
    }
    private static void deed()throws Exception {
        boolean[] land=(boolean[])MarketProbe.field(game,null,"a",boolean[].class);
        if(land[3])throw new AssertionError("Expected unclaimed Quiet Acre");
        // Supply the preceding deed, the qualifying livestock/tree and funds in the fixture.
        land[2]=true;
        MarketProbe.method(game,"f",void.class,int.class,int.class,boolean.class).invoke(null,59,0,true);
        ((int[])MarketProbe.field(game,null,"cb",int[].class))[0]=2;
        Method stock=MarketProbe.method(game,"d",void.class,int.class,int.class,int.class);
        stock.invoke(null,3,31,1);stock.invoke(null,4,1,2);
        MarketProbe.method(game,"aa",void.class,int.class).invoke(null,100);
        MarketProbe.method(game,"ab",void.class,int.class).invoke(null,100);
        MarketProbe.method(game,"V",void.class,int.class).invoke(null,5000);
        set("r",3);
        MarketProbe.method(game,"fV",void.class).invoke(null);
        if(!(Boolean)MarketProbe.field(game,null,"ar",boolean.class))throw new AssertionError("Deed ineligible");
        MarketProbe.method(game,"di",void.class).invoke(null);Thread.sleep(2000);
        if(!land[3] || amount("d")!=0)throw new AssertionError("Native deed not awarded");
        System.out.println("POND_DEED quest=9064 coins=5000 screen="+amount("a"));
    }
    private static void settleDeed()throws Exception {
        screen(17);Thread.sleep(2400);
        if(amount("a")==26){tap(55,479);Thread.sleep(1300);}
        if(amount("a")==13){button(12,5);Thread.sleep(650);}
    }
    private static void open()throws Exception {
        screen(17);
        Object pond=pond();
        if(pond==null)throw new AssertionError("Quiet Acre has no pond");
        Object cam=MarketProbe.field(game,null,"c",actor);
        int r=(Integer)MarketProbe.field(actor,pond,"r",int.class),s=(Integer)MarketProbe.field(actor,pond,"s",int.class);
        boolean active=(Boolean)MarketProbe.method(actor,"a",boolean.class,int.class).invoke(pond,512);
        System.out.println("POND_WORLD x="+r+" y="+s+" accessible="+active);
        if(!active)throw new AssertionError("Purchased land did not activate the original pond");
        MarketProbe.method(actor,"a",void.class,int.class,int.class,int.class).invoke(cam,r,s,0);
        Thread.sleep(800);shot("parcela");
        int u=(Integer)MarketProbe.field(actor,pond,"u",int.class),v=(Integer)MarketProbe.field(actor,pond,"v",int.class);
        for(int dy:new int[]{16,32,0,48}){tap(479-v+dy,u);if(amount("a")==19)break;}
        screen(19);
        String help=(String)MarketProbe.field(game,null,"p",String.class);
        if(!help.contains("ondas") || !help.contains("recompensa"))throw new AssertionError(help);
        System.out.println("POND_HELP "+help);shot("instrucciones");
        button(4,11);screen(25);shot("tres-canas");
    }
    private static int[] values(String key)throws Exception {
        return (int[])MarketProbe.field(game,null,key,int[].class);
    }
    private static void reserves()throws Exception {
        int cap=number("dR");
        int active=(Integer)MarketProbe.method(actor,"a",int.class,int.class,int.class).invoke(null,0,54);
        Method stored=MarketProbe.method(game,"gf3Stored",int.class,int.class,int.class);
        Method write=MarketProbe.method(game,"d",void.class,int.class,int.class,int.class);
        int original=(Integer)stored.invoke(null,3,0), elsewhere=0;
        int[][] inventory=(int[][])MarketProbe.field(game,null,"j",int[][].class);
        for(int i=1;i<inventory[3].length;i++)elsewhere+=(Integer)stored.invoke(null,3,i);
        Class<?> pond=Class.forName("GF3Pond",true,game.getClassLoader());
        Method blocked=MarketProbe.method(pond,"blocked",boolean.class);
        set("dR",1000);
        write.invoke(null,3,0,95-active-elsewhere);
        int ordinaryStock=(Integer)stored.invoke(null,0,20);
        write.invoke(null,0,20,120);
        if((Boolean)blocked.invoke(null))throw new AssertionError("95 animals should fit");
        write.invoke(null,0,20,ordinaryStock);
        write.invoke(null,3,0,96-active-elsewhere);
        if(!(Boolean)blocked.invoke(null))throw new AssertionError("96 animals should block");
        for(int button:new int[]{19,23,21}){
            int bills=amount("e");
            button(24,button);screen(19);
            String warning=(String)MarketProbe.field(game,null,"p",String.class);
            if(!warning.contains("demasiados animales") || bills!=amount("e"))
                throw new AssertionError("Pond reserve or refund failed: "+warning);
            if(((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[4][30][10]!=0)
                throw new AssertionError("Livestock warning displayed barn expansion hint");
            shot("limite-animales");button(4,11);screen(17);open();
        }
        set("dR",15);
        button(24,19);screen(19);
        String ordinaryWarning=(String)MarketProbe.method(base,"c",String.class,int.class).invoke(null,402);
        if(!ordinaryWarning.equals(MarketProbe.field(game,null,"p",String.class)))
            throw new AssertionError("A full barn should take priority over the livestock cap");
        button(4,11);screen(17);open();
        write.invoke(null,3,0,original);set("dR",cap);
        System.out.println("POND_RESERVES active="+active+" threshold=95 rejected=96 pricesRefunded=0,30,50");
    }
    private static long coinSeed(int rod)throws Exception {
        int[] types=values("bu"),weights=values("bt");
        int total=number("fx"),count=number("fw");
        if(total!=new int[]{9978,9982,9993}[rod] || count!=new int[]{34,22,18}[rod])
            throw new AssertionError("Incorrect weighted prize pool "+rod+" "+total+"/"+count);
        // Android 4.4.4 table 19, positive rows in source order, big-endian
        // integers [type, stable item ID, quantity, weight for this pole].
        String[] expected={"f6d0a3b1a969dac03380c61001f9104c1c8691aef08a5437b1bc76bf87a1d36d",
            "cfac8147c339a98a177e9b9756bcc46d6e11c3287c57d100fe5e26f8519eb325",
            "ee3b61f5196d9c24e77b1592e72b620b0360fabfc84e3f119c3b2979756c81c6"};
        ByteBuffer pool=ByteBuffer.allocate(16*count);
        int[] items=values("bv"),quantities=values("bw");
        for(int i=0;i<count;i++)pool.putInt(types[i]).putInt(items[i]).putInt(quantities[i]).putInt(weights[i]);
        StringBuilder hash=new StringBuilder();
        for(byte b:MessageDigest.getInstance("SHA-256").digest(pool.array()))hash.append(String.format("%02x",b&255));
        if(!expected[rod].equals(hash.toString()))throw new AssertionError("Altered prizes for rod "+rod);
        for(long seed=0;seed<10000;seed++){
            int pick=Math.abs(new Random(seed).nextInt())%total;
            for(int i=0;i<count;i++){
                if(pick<weights[i]){if(types[i]==2)return seed;break;}
                pick-=weights[i];
            }
        }
        throw new AssertionError("No coin prize for rod "+rod);
    }
    private static void cast(int rod)throws Exception {
        int bills=amount("e"),coins=amount("d");
        button(24,new int[]{19,23,21}[rod]);
        long end=System.currentTimeMillis()+5500;
        while(number("fs")!=7 && System.currentTimeMillis()<end)Thread.sleep(50);
        if(number("fL")!=1 || number("fs")!=7 || number("fu")!=rod ||
            amount("e")!=bills-new int[]{0,30,50}[rod])throw new AssertionError("Pole purchase "+rod);
        long deadline=(Long)MarketProbe.field(game,null,"b",long.class);
        long cooldown=deadline-System.currentTimeMillis();
        if(rod==0 && (cooldown<86390000 || cooldown>86400000))throw new AssertionError("Free timer "+cooldown);
        if(rod==0)Files.write(Paths.get("pond-deadline.txt"),Long.toString(deadline).getBytes(StandardCharsets.US_ASCII));
        long seed=coinSeed(rod);
        Random random=(Random)MarketProbe.field(base,null,"a",Random.class);
        shot("ondas-"+rod);
        int gained=0;
        for(int i=0;i<5;i++){
            end=System.currentTimeMillis()+3000;
            while(number("fD")!=-1 && System.currentTimeMillis()<end)Thread.sleep(40);
            boolean[] used=new boolean[7];
            for(int j=0;j<number("ft");j++)used[values("by")[j]]=true;
            int point=0;while(used[point])point++;
            // Select a repeatable cash prize in the native weighted draw.
            // The actual touch, catch handler and balance mutation run in the MIDlet.
            random.setSeed(seed);
            tap(479-values("bs")[point],values("br")[point]);
            if(number("ft")!=i+1)throw new AssertionError("Ripple "+i+" accepted="+number("ft"));
            if(i<3){
                int row=values("bx")[i];
                if(values("bu")[row]!=2)throw new AssertionError("Wrong weighted prize "+row);
                gained+=values("bw")[row];
            }
        }
        end=System.currentTimeMillis()+5000;
        while(number("fL")!=2 && System.currentTimeMillis()<end)Thread.sleep(80);
        if(number("fL")!=2 || number("fv")!=3 || amount("d")!=coins+gained)
            throw new AssertionError("Pond credit "+coins+"->"+amount("d")+" expected "+gained);
        shot("premios-"+rod);
        System.out.println("POND_CAST rod="+rod+" price="+(bills-amount("e"))+
            " ripples=5 rewarded=3 coins="+gained+" totalWeight="+number("fx"));
        button(20,4);
        if(number("fL")!=0)throw new AssertionError("Results did not return to the pole selection");
        if(rod==0){
            button(24,19);
            if(number("fL")!=0)throw new AssertionError("Free pole reset early");
        }
    }
    static void check(ClassLoader loader,boolean reload)throws Exception {
        game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);
        sprite=Class.forName("e",true,loader);base=Class.forName("g",true,loader);
        if(reload){
            if(!((boolean[])MarketProbe.field(game,null,"a",boolean[].class))[3])
                throw new AssertionError("Quiet Acre was lost after reopening");
            open();
            long original=Long.parseLong(new String(Files.readAllBytes(Paths.get("pond-deadline.txt")),StandardCharsets.US_ASCII));
            long loaded=(Long)MarketProbe.field(game,null,"b",long.class);
            long remaining=loaded-System.currentTimeMillis();
            if(loaded!=original || remaining<=0 || remaining>=86400000)
                throw new AssertionError("Daily timer changed across RMS reload: "+original+" -> "+loaded);
            int wallet=amount("e");
            button(24,19);
            if(number("fL")!=0 || amount("e")!=wallet)throw new AssertionError("Daily cast reused after reload");
            shot("espera-diaria");
            System.out.println("POND-RELOAD_OK remainingSeconds="+remaining/1000);return;
        }
        synchronized(Class.forName("GF3Presentation",false,loader)) {deed();}
        settleDeed();open();
        if(number("fB")!=30 || number("fC")!=50)throw new AssertionError("Premium pole prices");
        reserves();
        for(int i=0;i<3;i++)cast(i);
        button(24,12);screen(17);
        System.out.println("POND_OK");
    }
}
