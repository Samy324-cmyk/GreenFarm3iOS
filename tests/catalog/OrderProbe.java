import java.lang.reflect.Array;
import java.lang.reflect.Method;
import java.util.Arrays;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Deliver and discard real orders, then resume the saved half-hour timer. */
final class OrderProbe {
    private static Class<?> game,actor,sprite,orders;

    private static Object field(Class<?> cls,Object obj,String key,Class<?> type)throws Exception {
        return MarketProbe.field(cls,obj,key,type);
    }
    private static Method method(Class<?> cls,String key,Class<?> result,Class<?>... args) {
        return MarketProbe.method(cls,key,result,args);
    }
    private static int cash(String name)throws Exception {
        return (Integer)method(game,name,int.class).invoke(null);
    }
    private static int screen()throws Exception{return cash("a");}
    private static int stock(int row)throws Exception {
        return (Integer)method(game,"g",int.class,int.class,int.class).invoke(null,0,row);
    }
    private static void screen(int target)throws Exception {
        long end=System.currentTimeMillis()+8500;
        while(screen()!=target && System.currentTimeMillis()<end)Thread.sleep(80);
        if(screen()!=target)throw new AssertionError("Stand screen "+screen()+" expected "+target);
        Thread.sleep(550);
    }
    private static void tap(int x,int y)throws Exception {
        System.out.println("ORDERS tap "+x+","+y);
        MobilePlatform.pointerPressed(x,y);Thread.sleep(105);
        MobilePlatform.pointerReleased(x,y);Thread.sleep(450);
    }
    private static void button(int index)throws Exception {
        short[] row=((short[][][])field(game,null,"a",short[][][].class))[3][index];
        if(row[10]==0 || row[18]==0)throw new AssertionError("Missing sales control "+index);
        Object[] sheets=(Object[])field(game,null,"a",Array.newInstance(sprite,0).getClass());
        int[] box=new int[4];
        method(sprite,"a",void.class,int.class,int.class,int[].class,int.class)
            .invoke(sheets[row[5]],(int)row[6],0,box,0);
        tap(479-row[3]-box[1]-box[3]/2,row[2]+box[0]+box[2]/2);
    }
    private static void open()throws Exception {
        screen(17);
        Object list=Array.newInstance(actor,1);
        method(actor,"a",int.class,int.class,int.class,int.class,list.getClass(),int.class)
            .invoke(null,0,50,9,list,1);
        Object stand=Array.get(list,0);
        if(stand==null)throw new AssertionError("Missing original roadside stand");
        Object camera=field(game,null,"c",actor);
        method(actor,"a",void.class,int.class,int.class,int.class).invoke(camera,
            field(actor,stand,"r",int.class),field(actor,stand,"s",int.class),0);
        Thread.sleep(800);
        int u=(Integer)field(actor,stand,"u",int.class),v=(Integer)field(actor,stand,"v",int.class);
        for(int dy:new int[]{28,46,12}){tap(479-v+dy,u);if(screen()==8)break;}
        screen(8);
        if(!(Boolean)field(game,null,"aw",boolean.class))throw new AssertionError("Expected customer orders");
    }
    private static long[] clocks()throws Exception {
        return (long[])field(orders,null,"since",long[].class);
    }
    private static void deliver()throws Exception {
        int[] lines=((int[][])field(game,null,"g",int[][].class))[0].clone();
        int[] terms=((int[][])field(game,null,"h",int[][].class))[0];
        int quote=(Integer)method(game,"p",int.class,int.class).invoke(null,terms[0]);
        int xp=(Integer)method(game,"p",int.class,int.class).invoke(null,terms[1]);
        int[] before=new int[3];
        for(int i=0;i<3;i++){
            int row=lines[2*i],qty=lines[2*i+1];
            if(row<0)continue;
            if(stock(row)<qty)
                method(game,"a",boolean.class,int.class,int.class,int.class).invoke(null,0,row,qty-stock(row));
            before[i]=stock(row);
        }
        button(10);
        int wallet=cash("d"),experience=cash("x");
        button(199);screen(17);
        for(int i=0;i<3;i++)if(lines[2*i]>=0 && stock(lines[2*i])!=before[i]-lines[2*i+1])
            throw new AssertionError("Customer did not take product "+lines[2*i]);
        long end=System.currentTimeMillis()+14000;
        while(cash("d")!=wallet+quote && System.currentTimeMillis()<end)Thread.sleep(80);
        if(cash("d")!=wallet+quote || cash("x")!=experience+xp)
            throw new AssertionError("Order payout "+wallet+"->"+cash("d")+" XP "+experience+"->"+cash("x")+
                                     " expected "+quote+"/"+xp);
        System.out.println("ORDERS_DELIVERED products="+Arrays.toString(lines)+" coins="+quote+" xp="+xp);
    }
    static void check(ClassLoader loader,boolean reload)throws Exception {
        game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);
        sprite=Class.forName("e",true,loader);orders=Class.forName("GF3CustomerOrders",true,loader);
        if(!reload){
            open();deliver();open();button(198);
            long delta=System.currentTimeMillis()-clocks()[0];
            if(delta<0 || delta>5500 || (Boolean)method(game,"n",boolean.class,int.class).invoke(null,0))
                throw new AssertionError("Discarded order was not blocked for 30 minutes");
            int seconds=(Integer)method(orders,"remaining",int.class,int.class,long.class)
                .invoke(null,0,System.currentTimeMillis());
            if(seconds<1795 || seconds>1800)throw new AssertionError("Unexpected wait "+seconds);
            button(21);button(198);
            if(clocks()[0]==0 || clocks()[1]==0)throw new AssertionError("Customer clocks overlap");
            button(10);
            System.out.println("ORDERS_OK remainingSeconds="+seconds);
        }else{
            open();
            if(clocks()[0]==0 || clocks()[1]==0 || (Boolean)method(game,"n",boolean.class,int.class).invoke(null,0))
                throw new AssertionError("Customer timer missing after reload");
            int bills=cash("e");
            button(211);
            if(cash("e")!=bills-4 || clocks()[0]!=0 || clocks()[1]==0)
                throw new AssertionError("Express renewal did not apply to the selected customer alone");
            button(21);
            // Move the recorded start to the last two seconds to exercise the
            // same expiry calculation without a half-hour test timeout.
            clocks()[1]=System.currentTimeMillis()-1798000L;
            long end=System.currentTimeMillis()+5000;
            while(clocks()[1]!=0 && System.currentTimeMillis()<end)Thread.sleep(100);
            if(clocks()[1]!=0 || cash("e")!=bills-4)throw new AssertionError("Natural renewal failed");
            System.out.println("ORDERS-RELOAD_OK expressBills=4 expiredNaturally=true");
        }
    }
}
