import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.Arrays;
import java.io.File;
import java.io.PrintWriter;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import org.recompile.mobile.PlatformImage;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Observe the MIDlet and send pointer events. The active campaign is never modified. */
final class IntroProbe {
    private static Class<?> game,actor;
    private static Object get(Class<?> c,Object ob,String field,Class<?> type)throws Exception {
        return MarketProbe.field(c,ob,field,type);
    }
    private static int n(Object ob,String name)throws Exception {
        return (Integer)get(ob==null?game:actor,ob,name,int.class);
    }
    private static int menu()throws Exception {return (Integer)MarketProbe.method(game,"a",int.class).invoke(null);}
    private static int count(String name)throws Exception {return (Integer)MarketProbe.method(game,name,int.class).invoke(null);}
    private static ArrayList<Object> objects(int layer,int kind)throws Exception {
        Object[] heads=(Object[])get(actor,null,"a",Array.newInstance(actor,0).getClass());
        ArrayList<Object> found=new ArrayList<>();
        for(Object f=heads[layer];f!=null;f=get(actor,f,"a",actor))
            if(n(f,"q")==kind)found.add(f);
        return found;
    }
    private static void touch(int x,int y)throws Exception{
        if(x<0 || x>=480 || y<0 || y>=800)return;
        MobilePlatform.pointerPressed(x,y);Thread.sleep(100);MobilePlatform.pointerReleased(x,y);Thread.sleep(220);
    }
    private static void tapObject(Object f,int dx,int dy)throws Exception {touch(479-(n(f,"v")+dy),n(f,"u")+dx);}
    private static boolean button(int id)throws Exception {
        for(int[] h:(int[][])get(game,null,"i",int[][].class))if(h[5]==id && h[2]>0 && h[3]>0){
            touch(479-h[1]-h[3]/2,h[0]+h[2]/2);return true;
        }
        return false;
    }
    private static void byRow(int kind,int row,int dx,int dy)throws Exception{
        for(Object obj:objects(0,kind))if(n(obj,"y")==row){tapObject(obj,dx,dy);return;}
    }
    private static void sweep(int stage,int kind,int dy)throws Exception {
        for(Object obj:objects(kind==47?2:0,kind)){
            if(n(null,"C")!=stage)return;
            tapObject(obj,0,dy);
        }
    }
    private static void snapshot(String label)throws Exception{
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        BufferedImage img=new BufferedImage(480,800,BufferedImage.TYPE_INT_RGB);
        synchronized(lcd){img.setRGB(0,0,480,800,lcd.getDataBuffer(),0,480);}
        ImageIO.write(img,"png",new File(label+".png"));
    }
    private static void levelCard()throws Exception{
        // The backdrop can be on the LCD for several frames before the title and unlocks are drawn.
        long end=System.currentTimeMillis()+9000;
        int outline=0,letters=0;
        while(System.currentTimeMillis()<end){
            PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
            outline=letters=0;
            synchronized(lcd){
                int[] rgb=lcd.getDataBuffer();
                for(int y=38;y<69;y++)for(int x=206;x<585;x++){
                    int c=rgb[x*480+479-y]&0xffffff;
                    if(c==0xe85400)outline++;
                    else if(c==0xf8fcf8)letters++;
                }
            }
            if(outline>120 && letters>120 && n(null,"em")>0){
                Class<?> sprite=Class.forName("e",true,game.getClassLoader());
                Object[] ui=(Object[])get(game,null,"a",Array.newInstance(sprite,0).getClass());
                short[][] panel=((short[][][])get(game,null,"a",short[][][].class))[12];
                for(int i=6;i<=7;i++)if(ui[panel[i][5]]==null)
                    throw new AssertionError("Level-up portrait is missing its layer "+i);
                snapshot("nivel-"+count("f"));return;
            }
            Thread.sleep(60);
        }
        snapshot("nivel-"+count("f")+"-incompleto");
        System.out.println("INTRO_CARD level="+count("f")+" screen="+menu()+" outline="+outline+" letters="+letters+
                " em="+n(null,"em")+" el="+n(null,"el")+" en="+n(null,"en"));
        throw new AssertionError("Level-up title and unlocks did not render");
    }
    private static void monitor() {
        Thread observer=new Thread(()->{
            try(PrintWriter out=new PrintWriter("transitions.csv","UTF-8")){
                long start=System.nanoTime();int previous=-999,view=-999;
                out.println("elapsed_ms,tutorial,screen,level,coins,experience");
                while(true){
                    int step=n(null,"C"),screen=menu();
                    if(step!=previous || screen!=view){
                        out.println((System.nanoTime()-start)/1000000+","+step+","+screen+","+count("f")+","+count("d")+","+count("x"));
                        out.flush();previous=step;view=screen;
                    }
                    Thread.sleep(10);
                }
            }catch(Exception e){throw new IllegalStateException(e);}
        },"intro-observer");
        observer.setDaemon(true);observer.start();
    }
    private static void autoplay()throws Exception{
        int previous=-99,previousScreen=-99;
        long lastChange=System.currentTimeMillis();
        while(n(null,"C")>=0){
            int stage=n(null,"C"),screen=menu();
            if(stage!=previous || screen!=previousScreen) {
                state();previous=stage;previousScreen=screen;lastChange=System.currentTimeMillis();
                Thread.sleep(500);
                if(n(null,"C")!=stage || menu()!=screen)continue;
                if(stage==8 && screen==18){
                    int found=0;
                    for(Object obj:objects(0,54)){
                        int id=n(obj,"J");
                        if(id==2073 || id==2074){
                            if(n(obj,"r")!=0 || n(obj,"s")!=0)throw new AssertionError("Predator visible during planting");
                            found++;
                        }
                    }
                    if(found!=2)throw new AssertionError("Missing farm spawn markers");
                    SceneCacheProbe.check(Mobile.getPlatform().loader);
                }
                if((stage==8 && screen==18) || (stage==21 && screen==19) || (stage==14 && screen==7)
                        || (stage==24 && screen==27) || (stage==41 && screen==7) || (stage==43 && screen==19))
                    snapshot("paso-"+stage);
            }
            if(System.currentTimeMillis()-lastChange>30000){
                snapshot("etapa-interrumpida");
                throw new AssertionError("Stalled at stage "+stage+" screen "+screen);
            }
            if(screen==19){if(!button(262148))button(262155);}
            else if(screen==35){Thread.sleep(150);}
            else if(screen==13){levelCard();button(786437);}
            else switch(stage){
            case 5:case 38:sweep(stage,49,-10);sweep(stage,47,-4);break;
            case 7:byRow(49,0,0,-4);break;
            case 8:
                button(65607);sweep(stage,49,-3);
                sweep(stage,47,-4);break;
            case 10:button(65580);break;
            case 11:button(65574);break;
            case 12:button(327685);break;
            case 13:button(65595);break;
            case 14:
                if(screen==7 && !button(131128) && !button(131114))button(131100);
                break;
            case 15:case 42:button(65598);break;
            case 17:byRow(54,16,0,-22);break;
            case 18:button(65539);break;
            case 23:byRow(50,14,0,-48);break;
            case 24:button(1441951);break;
            case 25:button(1441888);break;
            case 26:button(393242);break;
            case 27:button(393247);break;
            case 28:button(1441806);break;
            case 29:button(1441809);break;
            case 30:button(1441879);break;
            case 32:case 34:byRow(54,17,-22,-26);break;
            case 35:button(65539);break;
            case 36:
                if(screen==26){snapshot("primera-recompensa");button(327733);}
                else {byRow(54,17,-25,-30);sweep(stage,47,-4);}
                break;
            case 40:button(65595);break;
            case 41:button(131100);break;
            case 44:byRow(49,0,0,-4);break;
            case 45:button(65607);sweep(stage,49,-3);break;
            case 49:byRow(50,10,0,-40);break;
            case 50:button(655365);break;
            case 51:button(655373);break;
            case 52:button(65598);break;
            case 54:byRow(50,9,0,-40);break;
            case 56:button(196807);break;
            case 57:sweep(stage,47,-4);break;
            default:break;
            }
            Thread.sleep(180);
        }
        state();
    }
    private static void state()throws Exception {
        System.out.println("INTRO stage="+n(null,"C")+" screen="+menu()+" progress="+n(null,"q")+
                " level="+count("f")+" coins="+count("d")+" xp="+count("x"));
    }
    static void run(String[] cmd)throws Exception {
        if(game==null) {
            ClassLoader cl=Mobile.getPlatform().loader;game=Class.forName("a",true,cl);actor=Class.forName("f",true,cl);
        }
        switch(cmd[1]) {
        case "monitor":monitor();break;
        case "play":autoplay();break;
        case "finish":
            long end=System.currentTimeMillis()+30000;
            while((n(null,"C")!=-1 || menu()!=17) && System.currentTimeMillis()<end)Thread.sleep(150);
            if(n(null,"C")!=-1 || menu()!=17)throw new AssertionError("The farm did not open");
            int[] quests=(int[])get(game,null,"cc",int[].class);
            if(Arrays.stream(quests).noneMatch(id->id==9001))throw new AssertionError("Missing first quest award");
            int plots=(Integer)MarketProbe.method(actor,"a",int.class,int.class,int.class).invoke(null,0,49);
            if(count("f")!=3 || count("d")!=2215 || count("x")!=0 || plots!=8)
                throw new AssertionError("Unexpected farm after its first sale. Plots="+plots+" coins="+count("d"));
            snapshot("granja-libre");
            System.out.println("INTRO_COMPLETE level=3 coins=2215 bills="+count("e")+" xp=0 plots=8 quest=9001");
            break;
        default:throw new IllegalArgumentException(cmd[1]);
        }
    }
}
