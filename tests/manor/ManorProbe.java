import java.lang.reflect.Array;
import java.util.Arrays;
import java.nio.file.Files;
import java.nio.file.Path;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.io.File;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Renovate through MIDP pointer input and inspect the game's actual ledger and RMS. */
final class ManorProbe {
    static Class<?> game, actor;
    static int[][] rooms,speeds;
    static final int[] rows={0,4,5,6,7,8,9,10,11};
    static Object field(String id,Class<?> type)throws Exception {return MarketProbe.field(game,null,id,type);}
    static int count(String key)throws Exception{return (Integer)MarketProbe.method(game,key,int.class).invoke(null);}
    static int integer(String key)throws Exception{return (Integer)field(key,int.class);}
    static int screen()throws Exception{return count("a");}
    static int stage()throws Exception{return ((Short)field("f",short.class)).intValue();}
    static int[] array(String id)throws Exception{return (int[])field(id,int[].class);}
    static boolean awarded(int id)throws Exception{return Arrays.stream(array("cc")).anyMatch(n->n==id);}
    static int pos(Object obj,String key)throws Exception{return (Integer)MarketProbe.field(actor,obj,key,int.class);}
    static void equal(long actual,long expected,String label){if(actual!=expected)throw new AssertionError(label+" was "+actual+", expected "+expected);}
    interface Condition{boolean ok()throws Exception;}
    static void until(Condition cond,String label)throws Exception{
        long end=System.nanoTime()+16000000000L;
        while(!cond.ok() && System.nanoTime()<end)Thread.sleep(80);
        if(!cond.ok()){shot("interrupcion");dump();throw new AssertionError(label);}
    }
    static void touch(int x,int y)throws Exception{
        if(x<0 || x>=480 || y<0 || y>=800)throw new AssertionError("Offscreen "+x+","+y);
        MobilePlatform.pointerPressed(x,y);Thread.sleep(100);MobilePlatform.pointerReleased(x,y);Thread.sleep(270);
    }
    static int[] hit(int id)throws Exception{
        for(int[] h:(int[][])field("i",int[][].class))if(h[5]==id && h[2]>0 && h[3]>0)return h;
        return null;
    }
    static void button(int id)throws Exception{
        until(()->hit(id)!=null,"Missing button "+id);Thread.sleep(600);
        if(hit(id)==null)return;
        int[] h=hit(id);
        System.out.println("MANOR_INPUT button="+id);
        touch(479-h[1]-h[3]/2,h[0]+h[2]/2);
    }
    static void shot(String id)throws Exception{
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        BufferedImage img=new BufferedImage(480,800,BufferedImage.TYPE_INT_RGB);
        synchronized(lcd){img.setRGB(0,0,480,800,lcd.getDataBuffer(),0,480);}
        ImageIO.write(img,"png",new File(id+".png"));
    }
    static void dump()throws Exception{
        System.out.println("MANOR_STATE room="+integer("G")+" substate="+stage()+" screen="+screen()+" level="+count("f")+
            " coins="+count("d")+" xp="+count("x")+" bills="+count("e")+" journal="+Arrays.toString(array("bD"))+
            " states="+Arrays.toString(array("cb"))+" timer="+field("r",long.class)+"/"+field("s",long.class));
        for(int[] h:(int[][])field("i",int[][].class))if(h[2]>0 && h[3]>0 && h[5]>0)System.out.print(h[5]+" ");
        System.out.println();
    }
    static void manor()throws Exception{
        until(()->screen()==17,"Farm not visible");
        Object[] heads=(Object[])MarketProbe.field(actor,null,"a",Array.newInstance(actor,0).getClass());
        Object door=null;
        for(Object f=heads[0];f!=null;f=MarketProbe.field(actor,f,"a",actor))
            if(pos(f,"q")==50 && pos(f,"y")==18){door=f;break;}
        if(door==null)throw new AssertionError("Farmhouse entrance missing");
        for(int i=0;i<6 && screen()==17;i++){
            touch(479-pos(door,"v")+50,pos(door,"u"));Thread.sleep(550);
        }
        until(()->screen()==29,"Touching the manor did not open its plan");
    }
    static void card(int room)throws Exception{
        manor();if(room==0 || room==8)shot("plano-"+room);
        button(851970+room);until(()->screen()==30,"Renovation card");
    }
    static void receipt(int room)throws Exception{
        int[] data=rooms[room];int cash=count("d");
        equal(integer("G"),room,"Restored rooms before purchase");
        equal(integer("dZ"),data[1],"Listed price");equal(integer("ec"),data[2],"Restoration XP");
        equal(integer("ee"),data[3]*60L,"Listed seconds");
        shot("presupuesto-"+room);button(917514);
        until(()->stage()==2 || stage()==3,"Renovation did not begin");
        equal(count("d"),cash-data[1],"Amount charged");
        equal((Long)field("s",long.class),data[3]*60L,"Timer duration");
        System.out.println("MANOR_PURCHASE index="+room+" building="+data[0]+" coins="+data[1]+" xp="+data[2]+" seconds="+data[3]*60L);
    }
    static void first()throws Exception{
        equal(count("f"),3,"Starting level");equal(count("d"),2215,"Tutorial-earned cash");
        button(65580);button(65575);until(()->screen()==19,"Walt");
        shot("walt");button(262155);until(()->screen()==26,"Journal");
        touch(245,670);until(()->screen()==17,"Farm after accepting");Thread.sleep(1600);
        if(screen()==19 && hit(262148)!=null)button(262148);
        card(0);receipt(0);button(917551);
        until(()->screen()==19,"First room congratulations");equal(integer("G"),1,"Kitchen restored");
        equal(count("x"),5,"Kitchen XP");button(262155);button(327733);
        until(()->awarded(9000) && count("x")==9 && count("d")==1740,"Kitchen journal reward");
        equal(count("d"),1740,"Coins after mission");equal(count("e"),40,"Bills after mission");
        shot("cocina-restaurada");System.out.println("MANOR_FIRST_OK quest=9000 coins=1740 xp=9 bills=40");
    }
    static void seedEstate()throws Exception{
        equal(integer("G"),1,"Restored kitchen in second JVM");equal(count("d"),1740,"Kitchen balance on reload");
        if(!awarded(9000))throw new AssertionError("Lost kitchen quest");
        synchronized(Class.forName("GF3Presentation",true,game.getClassLoader())){
            Class<?> db=Class.forName("h",true,game.getClassLoader());
            Object[] t=(Object[])MarketProbe.field(db,null,"a",Array.newInstance(db,0).getClass());
            int[][] q=(int[][])MarketProbe.field(db,t[6],"a",int[][].class);
            int[] cc=array("cc");
            for(int i=0;i<q.length;i++)if(i!=0 && (i<4 || i>11))cc[i]=q[i][1];
            Arrays.fill(array("bD"),-1);Arrays.fill(array("bE"),-1);Arrays.fill(array("cb"),0);
            MarketProbe.method(game,"X",void.class,int.class).invoke(null,50);
            MarketProbe.method(game,"V",void.class,int.class).invoke(null,6000000);
            MarketProbe.method(game,"W",void.class,int.class).invoke(null,1000000);
            Arrays.fill((boolean[])field("a",boolean[].class),true);
        }
        System.out.println("MANOR_FIRST_RELOAD_OK");
    }
    static void offer(int room)throws Exception{
        // Starting with room two, the fixture already includes all unrelated story quests.
        // Each previous room must have been restored and claimed by the native campaign.
        int row=rows[room],id=9000+row;
        if(awarded(id))throw new AssertionError("Target already restored: "+id);
        for(int i=1;i<4;i++){
            int previous=quests[room][i];
            if(previous>=0 && array("cc")[previous]<0)throw new AssertionError("Missing prerequisite "+previous);
        }
        int found=-1;
        for(int i=0;i<array("bD").length;i++)if(array("bD")[i]==id)found=i;
        if(found<0){
            array("bD")[0]=-1;array("bE")[0]=-1;
            MarketProbe.method(game,"u",boolean.class).invoke(null);
            for(int i=0;i<array("bD").length;i++)if(array("bD")[i]==id)found=i;
        }
        if(found<0){dump();throw new AssertionError("Schedule of "+id);}
        if(array("cb")[found]!=1)throw new AssertionError("Already-active quest "+id);
        if(hit(65575+found)==null)button(65580);
        button(65575+found);
        for(int i=0;i<6 && screen()!=26;i++){
            if(screen()==19)button(262155);
            else Thread.sleep(400);
        }
        until(()->screen()==26,"Journal of "+id);
        touch(245,670);
        until(()->screen()==17,"Accepted "+id);
        if(array("cb")[found]!=2)throw new AssertionError("Acceptance of "+id);
    }
    static int quote(int seconds){
        for(int[] rate:speeds)if(seconds<rate[0])return Math.max(1,rate[1]);
        return speeds[speeds.length-1][1];
    }
    static void speedUp()throws Exception{
        until(()->hit(917522)!=null,"Speed-up button");Thread.sleep(1700);
        int bills=count("e"),price=integer("eb");
        long end=(Long)field("r",long.class)+(Long)field("s",long.class);
        int left=(int)(end-System.currentTimeMillis()/1000);
        if(price!=quote(left) && price!=quote(left+1))
            throw new AssertionError("Android skip quote for "+left+"s: "+price);
        button(917522);until(()->hit(917551)!=null,"Completion after speeding up");
        equal(count("e"),bills-price,"Speed-up charge");
        System.out.println("MANOR_SPEEDUP bills="+price);
    }
    static final class Stars implements AutoCloseable{
        volatile boolean running=true;
        volatile int peak;
        final Thread monitor;
        Stars() {
            monitor=new Thread(()->{
                try{
                    while(running){
                        Object[] heads=(Object[])MarketProbe.field(actor,null,"a",Array.newInstance(actor,0).getClass());
                        int total=0;
                        for(Object p=heads[2];p!=null;p=MarketProbe.field(actor,p,"a",actor))
                            if(pos(p,"q")==47 && pos(p,"X")==37)total+=pos(p,"aa");
                        peak=Math.max(peak,total);Thread.sleep(8);
                    }
                }catch(Exception e){throw new IllegalStateException(e);}
            },"restore-stars");monitor.setDaemon(true);monitor.start();
        }
        public void close()throws InterruptedException{running=false;monitor.join();}
    }
    static void finishRoom(int room)throws Exception{
        int id=9000+rows[room],coins=count("d"),bills=count("e");
        try(Stars stars=new Stars()){
            button(917551);until(()->integer("G")==room+1,"Room completion");
            until(()->stars.peak==rooms[room][2],"Room XP stars "+rooms[room][2]+" (peak "+stars.peak+")");
        }
        boolean claimed=false;
        for(int i=0;i<100 && !claimed;i++){
            if(hit(327733)!=null){
                try(Stars stars=new Stars()){
                    button(327733);
                    until(()->stars.peak==quests[room][4],"Mission XP stars "+quests[room][4]+" (peak "+stars.peak+")");
                }
                claimed=true;
            }else if(hit(262155)!=null)button(262155);
            else if(hit(262148)!=null)button(262148);
            else if(hit(786437)!=null)button(786437);
            else if(screen()==17){
                int[] ids=array("bD");
                for(int j=0;j<ids.length;j++)if(ids[j]==id && array("cb")[j]==3){
                    if(hit(65575+j)!=null)button(65575+j);
                    else if(hit(65580)!=null)button(65580);
                    break;
                }
            }
            Thread.sleep(280);
        }
        if(!claimed)throw new AssertionError("Cannot claim quest "+id);
        until(()->awarded(id) && Arrays.stream(array("bD")).noneMatch(v->v==id),"Collect quest "+id);
        equal(count("e"),bills,"Quest premium currency");equal(count("d"),coins+quests[room][5],"Quest coins");
        // Farm-level experience stops at 50. The reward amount is still visible in the airborne stars.
        for(int i=0;i<12 && screen()!=17;i++){
            if(hit(262155)!=null)button(262155);
            else if(hit(262148)!=null)button(262148);
            else if(hit(786437)!=null)button(786437);
            Thread.sleep(300);
        }
        shot("terminada-"+room);System.out.println("MANOR_ROOM_OK index="+room+" quest="+id+" xpStars="+quests[room][4]+" bills="+count("e")+" wallet="+count("d"));
    }
    static int[][] quests;
    static void estate()throws Exception{
        seedEstate();
        for(int i=1;i<9;i++){
            offer(i);card(i);receipt(i);
            if(i<8){speedUp();finishRoom(i);}
        }
        dump();System.out.println("MANOR_CLOCK_STARTED "+field("r",long.class)+" "+field("s",long.class)+" "+count("d")+" "+count("e"));
    }
    static void attic()throws Exception{
        equal(integer("G"),8,"Attic still under renovation");equal(stage(),2,"Restored work in progress");
        System.out.println("MANOR_CLOCK_LOADED "+field("r",long.class)+" "+field("s",long.class)+" "+count("d")+" "+count("e"));
        card(8);speedUp();finishRoom(8);
        System.out.println("MANOR_FINAL "+integer("G")+" "+count("d")+" "+count("e")+" "+count("x"));
    }
    static void reopened()throws Exception{
        equal(integer("G"),9,"All rooms on restart");
        for(int i:rows)if(!awarded(9000+i))throw new AssertionError("Lost renovation quest "+(9000+i));
        System.out.println("MANOR_FINAL "+integer("G")+" "+count("d")+" "+count("e")+" "+count("x"));
        manor();shot("mansion-completa");
        for(int i=0;i<9;i++)if(hit(851970+i)==null)throw new AssertionError("Restored room inaccessible: "+i);
    }
    static void run(String action)throws Exception{
        if(game==null){
            long startup=System.currentTimeMillis()+45000;
            while((Mobile.midlet==null || Mobile.getDisplay()==null || Mobile.getDisplay().getCurrent()==null)
                    && System.currentTimeMillis()<startup)Thread.sleep(100);
            if(Mobile.midlet==null || Mobile.getDisplay()==null || Mobile.getDisplay().getCurrent()==null)
                throw new AssertionError("The emulator did not open its MIDlet display");
            ClassLoader cl=Mobile.getPlatform().loader;game=Class.forName("a",true,cl);actor=Class.forName("f",true,cl);
            rooms=Files.readAllLines(Path.of("rooms.txt")).stream().map(s->Arrays.stream(s.split(" ")).mapToInt(Integer::parseInt).toArray()).toArray(int[][]::new);
            speeds=Files.readAllLines(Path.of("speeds.txt")).stream().map(s->Arrays.stream(s.split(" ")).mapToInt(Integer::parseInt).toArray()).toArray(int[][]::new);
            quests=Files.readAllLines(Path.of("quests.txt")).stream().map(s->Arrays.stream(s.split(" ")).mapToInt(Integer::parseInt).toArray()).toArray(int[][]::new);
        }
        if(action.equals("ready")){
            long end=System.currentTimeMillis()+45000;
            while(System.currentTimeMillis()<end){
                try{
                    if(screen()==17 && integer("C")==-1 && count("f")>=3 && hit(65595)!=null){
                        Thread.sleep(600);return;
                    }
                }catch(java.lang.reflect.InvocationTargetException | NullPointerException ignored){
                    // The MIDlet allocates the screen tree asynchronously.
                }
                Thread.sleep(100);
            }
            throw new AssertionError("The saved farm did not become ready");
        }
        if(action.equals("first")){first();return;}
        if(action.equals("estate")){estate();return;}
        if(action.equals("attic")){attic();return;}
        if(action.equals("reopened")){reopened();return;}
        if(action.equals("dump")){dump();return;}
        throw new IllegalArgumentException(action);
    }
}
