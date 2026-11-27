import java.lang.reflect.Method;
import org.recompile.mobile.MobilePlatform;

/** Exercise the new native panel, its real hitbox and an atomic wallet update. */
final class WheelProbe {
    private static void waitScreen(Method screen,int id)throws Exception {
        long end=System.currentTimeMillis()+12000;
        while(System.currentTimeMillis()<end){
            if((Integer)screen.invoke(null)==id){Thread.sleep(900);return;}
            Thread.sleep(80);
        }
        throw new AssertionError("Wheel screen "+screen.invoke(null)+" expected "+id);
    }
    static void check(ClassLoader loader)throws Exception{
        Class<?> wheel=Class.forName("GF3Wheel",true,loader),game=Class.forName("a",true,loader);
        Method screen=MarketProbe.method(game,"a",int.class),wallet=MarketProbe.method(game,"e",int.class);
        Method money=MarketProbe.method(game,"d",int.class);
        Method sector=MarketProbe.method(wheel,"sector",int.class,int.class);
        int[] counts=new int[5];
        for(int i=0;i<360;i++)counts[(Integer)sector.invoke(null,i)]++;
        if(!java.util.Arrays.equals(counts,new int[]{120,80,40,60,60}))throw new AssertionError("Android sector geometry");
        MarketProbe.method(game,"h",void.class,int.class).invoke(null,10);
        int bills=(Integer)wallet.invoke(null),coins=(Integer)money.invoke(null);
        if(!(Boolean)MarketProbe.method(wheel,"openBuilding",boolean.class,int.class).invoke(null,29))
            throw new AssertionError("Native building 1019 is not connected");
        waitScreen(screen,50);
        for(String resource:new String[]{"/gf3-wheel-bg.png","/gf3-wheel-rim.png","/gf3-wheel-coin.png","/gf3-wheel-bill.png","/gf3-bills.png","/gf3-cash-shop.png","/gf3-coin-shop.png"}){
            java.io.InputStream in=wheel.getResourceAsStream(resource);
            if(in==null || in.read()!=137 || in.read()!=80)throw new AssertionError("Missing original PNG "+resource);
            in.close();
        }
        int[][] hits=(int[][])MarketProbe.field(game,null,"i",int[][].class);
        boolean pressed=false;
        for(int[] r:hits)if(r[5]==1966086 && r[2]>0 && r[3]>0){
            int x=479-r[1]-r[3]/2,y=r[0]+r[2]/2;
            MobilePlatform.pointerPressed(x,y);Thread.sleep(100);MobilePlatform.pointerReleased(x,y);
            pressed=true;break;
        }
        if(!pressed)throw new AssertionError("Wheel spin touch target missing");
        Thread.sleep(4100);
        int prize=(Integer)MarketProbe.field(wheel,null,"result",int.class);
        if(prize<0 || prize>=5 || (Boolean)MarketProbe.field(wheel,null,"spinning",boolean.class))
            throw new AssertionError("Wheel animation did not complete");
        int[] cash=(int[])MarketProbe.field(wheel,null,"BILLS",int[].class),gold=(int[])MarketProbe.field(wheel,null,"COINS",int[].class);
        for(int value:cash)if(value>0 && value<3)throw new AssertionError("Minimum wheel cash prize");
        if((Integer)wallet.invoke(null)!=bills-3+cash[prize] || (Integer)money.invoke(null)!=coins+gold[prize])
            throw new AssertionError("Wheel payout incorrect");
        for(int[] r:(int[][])MarketProbe.field(game,null,"i",int[][].class))
            if(r[5]==1966084 && r[2]>0 && r[3]>0){
                int x=479-r[1]-r[3]/2,y=r[0]+r[2]/2;
                MobilePlatform.pointerPressed(x,y);Thread.sleep(100);MobilePlatform.pointerReleased(x,y);break;
            }
        waitScreen(screen,17);
        MarketProbe.method(wheel,"hit",void.class,int.class).invoke(null,65550);
        waitScreen(screen,51);
        MarketProbe.method(wheel,"hit",void.class,int.class).invoke(null,(31<<16)|23);
        if((Boolean)MarketProbe.field(wheel,null,"cashTab",boolean.class))throw new AssertionError("Gold selector");
        MarketProbe.method(wheel,"hit",void.class,int.class).invoke(null,(31<<16)|25);
        if(!(Boolean)MarketProbe.field(wheel,null,"cashTab",boolean.class))throw new AssertionError("Cash selector");
        MarketProbe.method(wheel,"hit",void.class,int.class).invoke(null,(31<<16)|2);
        waitScreen(screen,17);
        System.out.println("WHEEL_OK paid=3 prize="+prize);
    }
}
