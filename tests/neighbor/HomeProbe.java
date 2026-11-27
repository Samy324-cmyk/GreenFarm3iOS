import java.lang.reflect.Method;
import java.util.Arrays;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Feed a level-ten checkpoint to the MIDlet, then drive the encounter by touch. */
final class HomeProbe {
    private static Class<?> game,actor,home,dogs;
    private static Object dog;
    private static int wallet;

    private static Object get(Class<?> c,Object target,String field,Class<?> type) throws Exception {
        return MarketProbe.field(c,target,field,type);
    }

    private static Method call(Class<?> c,String name,Class<?> result,Class<?>... args) throws Exception {
        return MarketProbe.method(c,name,result,args);
    }

    private static int stage() throws Exception {return (Integer)get(home,null,"step",int.class);}
    private static int menu() throws Exception {return (Integer)call(game,"a",int.class).invoke(null);}
    private static void finishPrerequisite(int quest) throws Exception {
        int[] done=(int[])get(game,null,"cc",int[].class);
        for(int i=0;i<done.length;i++) {
            if(done[i]==quest) return;
            if(done[i]==-1) {done[i]=quest;return;}
        }
        throw new AssertionError("No space in quest ledger");
    }
    private static void tap(int x,int y) throws Exception {
        MobilePlatform.pointerPressed(x,y);
        Thread.sleep(110);
        MobilePlatform.pointerReleased(x,y);
    }

    private static void waitFor(int step,int screen) throws Exception {
        long end=System.currentTimeMillis()+21000;
        while((stage()!=step || menu()!=screen) && System.currentTimeMillis()<end) Thread.sleep(50);
        if(stage()!=step || menu()!=screen) {
            PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
            java.awt.image.BufferedImage img=new java.awt.image.BufferedImage(480,800,java.awt.image.BufferedImage.TYPE_INT_RGB);
            synchronized(lcd) {img.setRGB(0,0,480,800,lcd.getDataBuffer(),0,480);}
            javax.imageio.ImageIO.write(img,"png",new java.io.File("pantalla-inesperada.png"));
            throw new AssertionError("home "+stage()+"/"+menu()+" expected "+step+"/"+screen);
        }
        System.out.println("HOME step="+step+" menu="+screen);
    }

    private static int[] terrainPatch() {
        PlatformImage screen=Mobile.getPlatform().getLcdFrontbuffer();
        int[] pixels=new int[45*52];
        synchronized(screen) {
            int[] rgb=screen.getDataBuffer();
            for(int row=0;row<52;row++)
                System.arraycopy(rgb,(45+row)*480+120,pixels,row*45,45);
        }
        return pixels;
    }

    private static void checkTerrain() throws Exception {
        ClassLoader loader=Mobile.getPlatform().loader;
        // Wait for the camera jump to reach the LCD. Then compare the visible
        // trees to an independent fresh draw without advancing a frame.
        int[] previous=terrainPatch();
        int stable=0;
        long deadline=System.currentTimeMillis()+4000;
        while(stable<3 && System.currentTimeMillis()<deadline){
            Thread.sleep(65);
            int[] next=terrainPatch();
            stable=Arrays.equals(previous,next)?stable+1:0;
            previous=next;
        }
        if(stable<3)throw new AssertionError("The farm did not settle after the fox camera jump");
        synchronized(Class.forName("GF3Presentation",false,loader)){
            int[] shown=terrainPatch();
            int[] terrain=SceneCacheProbe.compare(loader,"zorro");
            int diff=0;
            for(int y=0;y<52;y++)for(int x=0;x<45;x++)
                if(((shown[y*45+x]^terrain[(45+y)*480+120+x])&0xffffff)!=0)diff++;
            if(diff!=0)throw new AssertionError("Fox camera LCD differs from the fresh terrain at "+diff+" pixels");
        }
        System.out.println("HOME_TERRAIN_OK");
    }

    private static void checkAlert(int kind) throws Exception {
        Class<?> sprite=Class.forName("k",true,Mobile.getPlatform().loader);
        long deadline=System.currentTimeMillis()+2500;
        short[] row=null;
        while(System.currentTimeMillis()<deadline) {
            row=((short[][][])get(game,null,"a",short[][][].class))[1][96];
            if(row[2]!=47 || row[3]!=151 || row[5]!=1 || row[6]!=70)
                throw new AssertionError("Unexpected Android alert position or sprite");
            if(kind==0 && row[10]==0 && row[17]==-1) return;
            if(kind!=0 && row[10]!=0 && row[7]==kind && row[17]>=0) {
                Class<?> array=java.lang.reflect.Array.newInstance(sprite,0).getClass();
                Object anim=((Object[])get(game,null,"a",array))[row[17]];
                if(anim!=null && (Integer)call(sprite,"a",int.class).invoke(anim)==kind) return;
            }
            Thread.sleep(25);
        }
        throw new AssertionError("Predator HUD "+kind+" "+Arrays.toString(row));
    }

    static void run(String action) throws Exception {
        if(game==null) {
            long until=System.currentTimeMillis()+25000;
            while(Mobile.midlet==null && System.currentTimeMillis()<until) Thread.sleep(50);
            if(Mobile.midlet==null) throw new AssertionError("MIDlet has not started");
            ClassLoader loader=Mobile.getPlatform().loader;
            game=Class.forName("a",true,loader); actor=Class.forName("f",true,loader);
            home=Class.forName("GF3HomePredator",true,loader); dogs=Class.forName("GF3Dogs",true,loader);
        }
        if(action.equals("wolf")) {
            ClassLoader loader=Mobile.getPlatform().loader;
            Class<?> clock=Class.forName("GF3ThiefClock",true,loader);
            call(game,"X",void.class,int.class).invoke(null,10);
            finishPrerequisite(9297);finishPrerequisite(9299);
            dog=call(game,"a",actor,int.class,int.class).invoke(null,0,70);
            call(game,"a",void.class,actor,boolean.class).invoke(null,dog,false);
            call(game,"fI",void.class).invoke(null);
            call(dogs,"finishToy",void.class,actor,int.class,int.class).invoke(null,dog,100,2);
            call(home,"trained",void.class).invoke(null);
            // Select a reproducible RNG seed for the real population sampler.
            Object[] heads=(Object[])get(actor,null,"a",java.lang.reflect.Array.newInstance(actor,0).getClass());
            int victims=0;
            for(int layer=0;layer<2;layer++) for(Object f=heads[layer];f!=null;f=get(actor,f,"a",actor)) {
                int id=(Integer)get(actor,f,"J",int.class);
                if((Integer)get(actor,f,"q",int.class)==54 && (Boolean)call(actor,"a",boolean.class,int.class).invoke(f,512)
                        && !(Boolean)call(actor,"a",boolean.class,int.class).invoke(f,4096)
                        && !(Boolean)call(dogs,"dog",boolean.class,actor).invoke(null,f) && id!=2073 && id!=2074) victims++;
            }
            java.util.Random trial=new java.util.Random(), live=(java.util.Random)get(Class.forName("g",true,loader),
                    null,"a",java.util.Random.class);
            int seed=0;
            for(;;seed++) {
                trial.setSeed(seed);
                for(int i=0;i<victims;i++) trial.nextInt();
                if(Math.abs(trial.nextInt())%10>5) break;
            }
            live.setSeed(seed);
            MarketProbe.variable(clock,"elapsed",int.class).setInt(null,300000);
            call(clock,"ready",boolean.class).invoke(null);
            waitFor(5,17);
            if((Integer)call(home,"thief",int.class).invoke(null)!=2)throw new AssertionError("Expected wolf");
            checkAlert(2);
            System.out.println("HOME_WOLF_READY level=3 energy=8");
        } else if(action.equals("wolf-attack")) {
            Thread.sleep(850);
            Object enemy=get(home,null,"fox",actor);
            int u=(Integer)get(actor,enemy,"u",int.class),v=(Integer)get(actor,enemy,"v",int.class);
            tap(480-v+20,u);
            waitFor(5,19);
            if((Integer)call(dogs,"happiness",int.class,actor).invoke(null,dog)!=8)
                throw new AssertionError("An exhausted attack cost energy");
            Thread.sleep(900);tap(145,450);waitFor(5,17);
            call(dogs,"finishToy",void.class,actor,int.class,int.class).invoke(null,dog,0,1);
            Thread.sleep(350);
            tap(480-v+20,u);
            waitFor(0,17);
            checkAlert(0);
            int xp=(Integer)call(dogs,"xp",int.class,actor).invoke(null,dog);
            int energy=(Integer)call(dogs,"happiness",int.class,actor).invoke(null,dog);
            if(xp!=112 || energy!=0)throw new AssertionError("Wolf payout "+xp+"/"+energy);
            System.out.println("HOME_WOLF_WIN xp="+xp+" energy="+energy);
        } else if(action.equals("raid") || action.equals("raid-reload")) {
            Class<?> clock=Class.forName("GF3ThiefClock",true,Mobile.getPlatform().loader);
            if(action.equals("raid")) {
                call(game,"X",void.class,int.class).invoke(null,10);
                finishPrerequisite(9297);
                finishPrerequisite(9299);
                dog=call(game,"a",actor,int.class,int.class).invoke(null,0,70);
                call(game,"a",void.class,actor,boolean.class).invoke(null,dog,false);
                call(game,"fI",void.class).invoke(null);
                call(dogs,"finishToy",void.class,actor,int.class,int.class).invoke(null,dog,11,0);
                call(home,"trained",void.class).invoke(null);
                MarketProbe.variable(clock,"elapsed",int.class).setInt(null,299750);
            }
            waitFor(5,17);
            dog=call(home,"ownedDog",actor).invoke(null);
            checkAlert(1);
            if((Integer)get(clock,null,"count",int.class)!=1
                    || (Integer)call(home,"thief",int.class).invoke(null)!=1)
                throw new AssertionError("Unexpected predator or quota");
            System.out.println("HOME_RAID_READY count=1 fox=1");
        } else if(action.equals("raid-win")) {
            Object enemy=get(home,null,"fox",actor);
            Thread.sleep(850);
            int u=(Integer)get(actor,enemy,"u",int.class),v=(Integer)get(actor,enemy,"v",int.class);
            tap(480-v+20,u);
            waitFor(0,17);
            int xp=(Integer)call(dogs,"xp",int.class,actor).invoke(null,dog);
            if(xp!=15 || (Integer)call(home,"thief",int.class).invoke(null)!=0)
                throw new AssertionError("Repeat fox did not leave or incorrect XP "+xp);
            checkAlert(0);
            System.out.println("HOME_RAID_WIN dogXP=15");
        } else if(action.equals("quota")) {
            Class<?> clock=Class.forName("GF3ThiefClock",true,Mobile.getPlatform().loader);
            long day=(Long)get(clock,null,"day",long.class);
            // One completed ambush came from the saved game. Advance the
            // active wait twice and then move only the persisted day boundary.
            MarketProbe.variable(clock,"elapsed",int.class).setInt(null,300000);
            waitFor(5,17);
            if((Integer)get(clock,null,"count",int.class)!=2) throw new AssertionError("Second encounter did not count");
            call(dogs,"finishToy",void.class,actor,int.class,int.class).invoke(null,dog,0,6);
            Thread.sleep(900);
            Object enemy=get(home,null,"fox",actor);
            tap(480-(Integer)get(actor,enemy,"v",int.class)+20,(Integer)get(actor,enemy,"u",int.class));
            waitFor(0,17);
            MarketProbe.variable(clock,"elapsed",int.class).setInt(null,300000);
            if((Boolean)call(clock,"ready",boolean.class).invoke(null) || (Integer)get(clock,null,"count",int.class)!=2)
                throw new AssertionError("A third predator spawned on one day");
            MarketProbe.variable(clock,"day",long.class).setLong(null,day-86400);
            waitFor(5,17);
            if((Integer)get(clock,null,"count",int.class)!=1) throw new AssertionError("Daily count failed to reset");
            System.out.println("HOME_DAILY_QUOTA two raids, third blocked, new day one raid");
        } else if(action.equals("seed") || action.equals("adopt") || action.equals("empty")) {
            call(game,"X",void.class,int.class).invoke(null,10);
            if(action.equals("empty")) {
                Object[] layers=(Object[])get(actor,null,"a",java.lang.reflect.Array.newInstance(actor,0).getClass());
                for(Object living=layers[0];living!=null;living=get(actor,living,"a",actor)) {
                    if((Integer)get(actor,living,"q",int.class)==54)
                        call(actor,"k",void.class,int.class).invoke(living,4096);
                }
                wallet=(Integer)call(game,"d",int.class).invoke(null);
            }
            // No manual status assignment. Let the live farm automatically
            // accept the level-ten quest even if it was queued as status 1.
            int[] journal=(int[])get(game,null,"bD",int[].class);
            int[] status=(int[])get(game,null,"cb",int[].class);
            int slot=-1;
            for(int i=0;i<journal.length;i++)if(journal[i]==9297)slot=i;
            if(slot<0){
                journal[0]=-1;
                ((int[])get(game,null,"bE",int[].class))[0]=-1;
            }
            call(home,"automatic",void.class).invoke(null);
            for(int i=0;i<journal.length;i++)if(journal[i]==9297)slot=i;
            if(slot<0 || status[slot]!=2)
                throw new AssertionError("Level-ten farm failed to activate 9297 automatically");
            System.out.println("HOME_AUTO_9297 slot="+slot);
            if(action.equals("empty")) return;
            dog=call(home,"ownedDog",actor).invoke(null);
            if(action.equals("adopt")) {
                if(dog!=null) throw new AssertionError("Expected a farm without a dog");
                wallet=(Integer)call(game,"d",int.class).invoke(null);
                return;
            }
            if(dog==null) {
                dog=call(game,"a",actor,int.class,int.class).invoke(null,0,70);
                call(game,"a",void.class,actor,boolean.class).invoke(null,dog,false);
                call(game,"fI",void.class).invoke(null);
                call(dogs,"finishToy",void.class,actor,int.class,int.class).invoke(null,dog,11,0);
            }
            call(game,"b",int.class,int.class,int.class,int.class).invoke(null,2070,1,17);
        } else if(action.equals("chicken")) {
            waitFor(15,19);
            Thread.sleep(1000);tap(145,450);waitFor(16,7);
            int row=((int[])get(game,null,"M",int[].class))[0];
            int coins=((int[])get(game,null,"Q",int[].class))[0],cash=((int[])get(game,null,"R",int[].class))[0];
            if(row!=4 || coins!=0 || cash!=0) throw new AssertionError("Chicken row "+row+"/"+coins+"/"+cash);
            Thread.sleep(650);tap(81,128);waitFor(16,17);Thread.sleep(550);
            Object chick=get(game,null,"a",actor);
            if(chick==null || (Integer)get(actor,chick,"J",int.class)!=2004) throw new AssertionError("Missing chick");
            int[][] hits=(int[][])get(game,null,"i",int[][].class);
            int[] confirm=null;
            for(int[] hit:hits) if(hit[5]==65598 && hit[2]>0 && hit[3]>0) confirm=hit;
            if(confirm==null) throw new AssertionError("Missing chick placement control");
            tap(480-confirm[1]-confirm[3]/2,confirm[0]+confirm[2]/2);
            Thread.sleep(900);
            int[] pos={(Integer)get(actor,chick,"r",int.class),(Integer)get(actor,chick,"s",int.class)},tile=new int[2];
            call(game,"c",void.class,int[].class,int[].class).invoke(null,pos,tile);
            System.out.println("HOME chick position="+Arrays.toString(pos)+" tile="+Arrays.toString(tile)+
                " flags="+get(actor,chick,"C",int.class)+" size="+get(actor,chick,"w",int.class)+"/"+
                get(actor,chick,"x",int.class)+" owned="+Arrays.toString((boolean[])get(game,null,"a",boolean[].class))+
                " placing="+(chick==get(game,null,"a",actor)));
            waitFor(1,19);
            if((Integer)call(game,"d",int.class).invoke(null)!=wallet ||
                !(Boolean)call(home,"livestockOnFarm",boolean.class).invoke(null)) throw new AssertionError("Free chick placement");
            System.out.println("HOME_CHICKEN_PLACED id=2004 coins=0 fox=1");
        } else if(action.equals("shelf")) {
            for(int step=1;step<=3;step++) {
                waitFor(step,19);
                Thread.sleep(1000);
                tap(145,450);
            }
            waitFor(3,7);
            int row=((int[])get(game,null,"M",int[].class))[0];
            int price=((int[])get(game,null,"Q",int[].class))[0];
            int cash=((int[])get(game,null,"R",int[].class))[0];
            if(row!=69 || price!=0 || cash!=0)
                throw new AssertionError("Adoption offer "+row+"/"+price+"/"+cash);
            System.out.println("HOME_ADOPTION_OFFER row=69 coins=0 bills=0");
        } else if(action.equals("select")) {
            tap(81,128);
            Thread.sleep(950);
            Object selected=get(game,null,"a",actor);
            if(selected==null || (Integer)get(actor,selected,"J",int.class)!=2069 || menu()!=17 || stage()!=3)
                throw new AssertionError("Pet placement "+menu()+"/"+stage());
            System.out.println("HOME_SELECTED id=2069");
        } else if(action.equals("place")) {
            int[][] hits=(int[][])get(game,null,"i",int[][].class);
            boolean found=false;
            for(int[] hit:hits) if(hit[5]==65598 && hit[2]>0 && hit[3]>0) {
                int x=480-hit[1]-hit[3]/2,y=hit[0]+hit[2]/2;
                System.out.println("HOME placement tap="+x+","+y);
                tap(x,y);
                found=true;
                break;
            }
            if(!found) throw new AssertionError("Missing placement control");
            waitFor(11,19);
            dog=call(home,"ownedDog",actor).invoke(null);
            if(dog==null || (Integer)get(actor,dog,"J",int.class)!=2069
                    || (Integer)call(game,"d",int.class).invoke(null)!=wallet)
                throw new AssertionError("The player did not adopt the first beagle for free");
            System.out.println("HOME_ADOPTED id=2069 wallet="+wallet);
        } else if(action.equals("mill")) {
            Thread.sleep(1100);
            tap(145,450);
            waitFor(12,27);
            Thread.sleep(800);
            System.out.println("HOME_MILL menu=27 offset="+get(game,null,"dp",int.class)+" scroll="+
                    Arrays.toString(((int[][])get(game,null,"b",int[][].class))[1]));
        } else if(action.equals("puppy")) {
            waitFor(13,19);
            Thread.sleep(950);
            tap(145,450);
            waitFor(13,17);
            Thread.sleep(800);
            int u=(Integer)get(actor,dog,"u",int.class),v=(Integer)get(actor,dog,"v",int.class);
            tap(480-v+20,u);
            waitFor(14,19);
            Thread.sleep(950);tap(145,450);
            waitFor(5,19);
            System.out.println("HOME_PUPPY_GROWN id="+get(actor,dog,"J",int.class));
        } else if(action.equals("restore")) {
            waitFor(9,19);
            dog=call(home,"ownedDog",actor).invoke(null);
            if(dog==null || (Integer)call(dogs,"xp",int.class,actor).invoke(null,dog)!=15
                    || (Integer)call(dogs,"happiness",int.class,actor).invoke(null,dog)!=0)
                throw new AssertionError("Dog changed across the post-fight save");
            System.out.println("HOME_RELOAD_OK dogXP=15 energy=0");
        } else if(action.equals("intro")) {
            for(int step:new int[]{1,2,3,5}) {
                waitFor(step,19);
                Thread.sleep(950);
                tap(145,450);
            }
            waitFor(5,17);
            Thread.sleep(900);
            checkTerrain();
        } else if(action.equals("fox")) {
            Object fox=get(home,null,"fox",actor);
            int u=(Integer)get(actor,fox,"u",int.class), v=(Integer)get(actor,fox,"v",int.class);
            // The touch edition rotates its landscape canvas clockwise.
            System.out.println("HOME touch fox at "+(480-v+20)+","+u+" world="+
                get(actor,fox,"r",int.class)+","+get(actor,fox,"s",int.class)+" flags="+get(actor,fox,"C",int.class));
            tap(480-v+20,u);
            // Camera drag while the dog approaches must not reset the encounter.
            Thread.sleep(150);MobilePlatform.pointerPressed(220,400);MobilePlatform.pointerDragged(220,525);MobilePlatform.pointerReleased(220,525);
            waitFor(9,19);
            if((Integer)get(actor,fox,"r",int.class)!=0 || (Integer)get(actor,fox,"s",int.class)!=0)
                throw new AssertionError("Fox remains in world after battle");
        } else if(action.equals("done")) {
            int xp=(Integer)call(dogs,"xp",int.class,actor).invoke(null,dog);
            int mood=(Integer)call(dogs,"happiness",int.class,actor).invoke(null,dog);
            if(xp<15 || mood>3) throw new AssertionError("dog xp/mood "+xp+"/"+mood);
            Thread.sleep(1100); tap(145,450);
            waitFor(10,19);
            Thread.sleep(1100); tap(145,450);
            long end=System.currentTimeMillis()+6000;
            int[] status=(int[])get(game,null,"cb",int[].class);
            while(status[0]!=3 && System.currentTimeMillis()<end) Thread.sleep(50);
            if(status[0]!=3) throw new AssertionError("Unfinished objective "+status[0]);
            System.out.println("HOME_OK quest=9297 dogXP="+xp+" energy="+mood);
        } else if(action.equals("claim")) {
            long until=System.currentTimeMillis()+8000;
            while(menu()!=26 && System.currentTimeMillis()<until) Thread.sleep(60);
            if(menu()!=26) throw new AssertionError("Missing reward screen");
            int before=(Integer)call(game,"d",int.class).invoke(null);
            int previousXp=(Integer)call(game,"x",int.class).invoke(null);
            Thread.sleep(950);
            int[] ledger=(int[])get(game,null,"cc",int[].class);
            int[] active=(int[])get(game,null,"bD",int[].class);
            for(int attempt=0;attempt<3 && menu()==26 && active[0]==9297;attempt++) {
                System.out.println("HOME reward slot="+get(game,null,"fE",int.class)+" status="+
                    Arrays.toString((int[])get(game,null,"cb",int[].class)));
                tap(55,479);Thread.sleep(900);
            }
            until=System.currentTimeMillis()+6500;
            while((active[0]==9297 || (Integer)call(game,"d",int.class).invoke(null)==before)
                    && System.currentTimeMillis()<until) Thread.sleep(70);
            int coins=(Integer)call(game,"d",int.class).invoke(null)-before;
            int xp=(Integer)call(game,"x",int.class).invoke(null)-previousXp;
            if(coins!=100 || xp!=4 || ledger[297]!=9297 || active[0]==9297)
                throw new AssertionError("First pet quest payout "+coins+"/"+xp);
            System.out.println("HOME_REWARD_CLAIMED coins=100 xp=4");
        }
    }
}
