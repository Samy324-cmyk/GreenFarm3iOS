import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Reach each locally stored farm via the touch edition's mailbox and truck. */
final class VisitsProbe {
    private static Class<?> game;
    private static int number(String field) throws Exception {
        return (Integer)MarketProbe.field(game,null,field,int.class);
    }
    private static int menu() throws Exception {
        if (MarketProbe.field(game,null,"a",int[].class)==null) return -1;
        return (Integer)MarketProbe.method(game,"a",int.class).invoke(null);
    }
    private static void tap(int x,int y) throws Exception {
        MobilePlatform.pointerPressed(479-y,x);
        Thread.sleep(150);
        MobilePlatform.pointerReleased(479-y,x);
        Thread.sleep(200);
    }
    private static void waitMenu(int expected,int farm) throws Exception {
        long end=System.nanoTime()+18_000_000_000L;
        while (menu()!=expected || (farm>=0 && number("F")!=farm)) {
            if (System.nanoTime()>end) throw new AssertionError("Expected menu "+expected+
                " farm "+farm+", reached "+menu()+"/"+number("F"));
            Thread.sleep(45);
        }
        Thread.sleep(400);
    }
    private static void returnHome() throws Exception {
        for (int attempt=0; attempt<10 && menu()==36; attempt++) {
            tap(746,431);
            Thread.sleep(800);
        }
        waitMenu(17,0);
    }
    private static void swipeLeft() throws Exception {
        MobilePlatform.pointerPressed(179,690);
        for (int i=1;i<=12;i++) {
            Thread.sleep(32);
            MobilePlatform.pointerDragged(179,690-i*37);
        }
        MobilePlatform.pointerReleased(179,246);
        Thread.sleep(450);
    }
    static void photograph(String name) throws Exception {
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        BufferedImage frame=new BufferedImage(480,800,BufferedImage.TYPE_INT_RGB);
        synchronized(lcd) { frame.setRGB(0,0,480,800,lcd.getDataBuffer(),0,480); }
        ImageIO.write(frame,"png",new File(name+".png"));
    }
    private static void dailyEnergy(int row,int[][] neighbors) throws Exception {
        // On Edwina's original layout these pens and crops surround the player.
        // Tapping the ready animals queues the same help as a physical handset.
        int[][] places={{366,126},{223,251},{655,234},{563,178},{647,70},{490,160},
                        {388,245},{507,359},{580,378},{146,153},{432,101},{630,386},
                        {77,101},{551,121},{710,366}};
        for (int[] at : places) {
            if (neighbors[row][5]==0) break;
            tap(at[0],at[1]);
            Thread.sleep(850);
        }
        long end=System.nanoTime()+10_000_000_000L;
        while (neighbors[row][5]!=0 && System.nanoTime()<end) Thread.sleep(150);
        int energy=neighbors[row][5];
        if (energy!=0) throw new AssertionError("Five physical helps left "+energy+" energy, menu="+menu());
        photograph("energia-agotada");
        long[][] times=(long[][])MarketProbe.field(game,null,"a",long[][].class);
        long now=System.currentTimeMillis()/1000;
        if (Math.abs(now-times[row][0])>120 || Math.abs(now-times[row][3])>120 ||
                (neighbors[row][2]&16)==0 || neighbors[row+1][5]!=5) {
            throw new AssertionError("Local energy or timestamp leaked to another farm");
        }
        // Move the visit timestamp across the one-day boundary. The game loop
        // (rather than the test) must actually refresh the counter on screen.
        times[row][0]=now-86_300;
        Thread.sleep(550);
        if (neighbors[row][5]!=0) throw new AssertionError("Energy replenished early");
        times[row][0]=now-86_401;
        end=System.nanoTime()+5_000_000_000L;
        while (neighbors[row][5]!=5 && System.nanoTime()<end) Thread.sleep(65);
        if (neighbors[row][5]!=5) throw new AssertionError("Energy did not replenish after a day");
        photograph("energia-recuperada");
        System.out.println("ENERGIA_OK farm="+(row+1)+" consumed=5 before24h=0 after24h=5");
    }
    private static void choose(int row) throws Exception {
        for (int attempt=0;attempt<9;attempt++) {
            int slot=row-number("eM");
            if (slot>=0 && slot<5) {
                short[][][] ui=(short[][][])MarketProbe.field(game,null,"a",short[][][].class);
                short[] title=ui[9][13+11*slot];
                int center=title[2]+title[5]/2;
                if (center>=80 && center<=720) {
                    tap(center,249);
                    waitMenu(37,0);
                    if (number("eS")!=row) throw new AssertionError("Unexpected neighbor: "+number("eS")+" target "+row+" x="+center);
                    return;
                }
            }
            swipeLeft();
        }
        throw new AssertionError("Could not scroll to neighbor "+row);
    }
    static void run(int first,int last) throws Exception {
        game=Class.forName("a",true,Mobile.getPlatform().loader);
        MarketProbe.method(game,"X",void.class,int.class).invoke(null,45);
        int[] done=(int[])MarketProbe.field(game,null,"cc",int[].class);
        done[2]=9002;
        for (int row=first;row<=last;row++) {
            tap(431,174);
            waitMenu(38,0);
            choose(row);
            tap(107,263);
            waitMenu(36,row+1);
            Thread.sleep(500);
            int[][] neighbors=(int[][])MarketProbe.field(game,null,"e",int[][].class);
            int energy=neighbors[row][5];
            if (energy!=5) throw new AssertionError("Initial energy "+energy);
            photograph("visita-"+(row+1));
            if (row==1) dailyEnergy(row,neighbors);
            returnHome();
            System.out.println("VISITA_OK id="+(99990+row)+" farm="+(row+1)+" energy="+energy);
        }
    }

    static void predators(boolean wolf) throws Exception {
        game=Class.forName("a",true,Mobile.getPlatform().loader);
        Class<?> extension=Class.forName("GF3VisitPredators",true,Mobile.getPlatform().loader);
        Class<?> actor=Class.forName("f",true,Mobile.getPlatform().loader);
        MarketProbe.method(game,"X",void.class,int.class).invoke(null,45);
        int[] done=(int[])MarketProbe.field(game,null,"cc",int[].class);
        done[2]=9002;done[299]=9301;
        int[][] neighbors=(int[][])MarketProbe.field(game,null,"e",int[][].class);
        long[] cooldown=(long[])MarketProbe.field(extension,null,"last",long[].class);
        if (wolf) {
            // Place a beagle on this controlled farm using the same native
            // factory and placement as the shop. Its level 3 unlocks wolves.
            Object pet=MarketProbe.method(game,"a",actor,int.class,int.class).invoke(null,0,70);
            MarketProbe.method(game,"a",void.class,actor,boolean.class).invoke(null,pet,false);
            MarketProbe.method(game,"fI",void.class).invoke(null);
            Class<?> dogs=Class.forName("GF3Dogs",true,Mobile.getPlatform().loader);
            MarketProbe.method(dogs,"finishToy",void.class,actor,int.class,int.class).invoke(null,pet,100,2);
            if ((Integer)MarketProbe.method(dogs,"level",int.class,actor).invoke(null,pet)!=3)
                throw new AssertionError("Could not prepare level-3 beagle");
        }
        tap(431,174);waitMenu(38,0);choose(1);
        photograph("solicitud");
        if (!(Boolean)MarketProbe.method(extension,"offered",boolean.class,int.class).invoke(null,1))
            throw new AssertionError("Missing predator request");
        int before=neighbors[1][1];
        tap(550,423);waitMenu(36,2);
        long end=System.nanoTime()+5_000_000_000L;
        while((Integer)MarketProbe.field(extension,null,"step",int.class)!=1 && System.nanoTime()<end)
            Thread.sleep(100);
        Object enemy=MarketProbe.field(extension,null,"enemy",actor);
        if(enemy==null) throw new AssertionError("Missing encounter actor");
        int id=(Integer)MarketProbe.field(actor,enemy,"J",int.class);
        if(id!=(wolf?2074:2073)) throw new AssertionError("Wrong predator "+id);
        photograph("depredador-vecino");tap(400,219);
        end=System.nanoTime()+14_000_000_000L;
        while((Integer)MarketProbe.field(extension,null,"step",int.class)!=5 && System.nanoTime()<end)
            Thread.sleep(80);
        int gain=neighbors[1][1]-before,unit=((int[])MarketProbe.field(game,null,"d",int[].class))[25];
        if(neighbors[1][5]!=4 || gain!=(wolf?2:1)*unit || cooldown[1]<=0 || cooldown[0]!=0 ||
              (Integer)MarketProbe.field(extension,null,"step",int.class)!=5)
            throw new AssertionError("Neighbor result energy="+neighbors[1][5]+" gain="+gain+"/"+unit+
                " last="+cooldown[1]+" stage="+MarketProbe.field(extension,null,"step",int.class));
        photograph("vecino-a-salvo");
        returnHome();
        tap(431,174);waitMenu(38,0);choose(1);
        if((Boolean)MarketProbe.method(extension,"offered",boolean.class,int.class).invoke(null,1))
            throw new AssertionError("Request returned inside cooldown");
        if((Boolean)MarketProbe.method(extension,"offered",boolean.class,int.class).invoke(null,2))
            throw new AssertionError("Unexpected predator for excluded neighbor");
        long earned=cooldown[1];
        cooldown[1]=System.currentTimeMillis()/1000-86_300;
        if((Boolean)MarketProbe.method(extension,"offered",boolean.class,int.class).invoke(null,1))
            throw new AssertionError("Second fight offered before 24h");
        cooldown[1]-=150;
        if(!(Boolean)MarketProbe.method(extension,"offered",boolean.class,int.class).invoke(null,1))
            throw new AssertionError("Daily fight did not return");
        tap(388,423);waitMenu(38,0);
        if(cooldown[1]<earned || neighbors[1][5]!=4) throw new AssertionError("Decline timer/energy");
        System.out.println("PREDATOR_VISIT_OK id="+id+" energy=4 friendship="+gain+" last="+cooldown[1]);
    }

    static void restored() throws Exception {
        game=Class.forName("a",true,Mobile.getPlatform().loader);
        waitMenu(17,0);
        Class<?> extension=Class.forName("GF3VisitPredators",true,Mobile.getPlatform().loader);
        long[] last=(long[])MarketProbe.field(extension,null,"last",long[].class);
        int[][] neighbors=(int[][])MarketProbe.field(game,null,"e",int[][].class);
        if(last[1]<=0 || last[0]!=0 || neighbors[1][5]!=4 ||
                (Boolean)MarketProbe.method(extension,"offered",boolean.class,int.class).invoke(null,1))
            throw new AssertionError("Independent neighbor RMS/cooldown did not survive reload");
        System.out.println("PREDATOR_RELOAD_OK last="+last[1]+" energy="+neighbors[1][5]);
    }
}
