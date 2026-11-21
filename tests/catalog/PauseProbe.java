import java.io.File;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Use only pointer input. Read the native control rectangles and label states as assertions. */
final class PauseProbe {
    private static Class<?> game,menu;
    private static boolean flag(Class<?> c,String name)throws Exception {
        return (Boolean)MarketProbe.field(c,null,name,boolean.class);
    }
    private static void expect(Class<?> c,String name,boolean value)throws Exception {
        for(int i=0;i<70;i++) {
            if(flag(c,name)==value)return;
            Thread.sleep(70);
        }
        throw new AssertionError(name+" did not become "+value);
    }
    private static void tap(int x,int y)throws Exception {
        MobilePlatform.pointerPressed(479-y,x);
        Thread.sleep(110);
        MobilePlatform.pointerReleased(479-y,x);
        Thread.sleep(210);
    }
    private static void button(int index)throws Exception {button(15,index);}
    private static void button(int panel,int index)throws Exception {
        for(int i=0;i<25;i++) {
            int[][] hits=(int[][])MarketProbe.field(game,null,"i",int[][].class);
            for(int[] h:hits)if(h[5]==(panel<<16|index) && h[2]>0 && h[3]>0){
                tap(h[0]+h[2]/2,h[1]+h[3]/2);
                return;
            }
            Thread.sleep(60);
        }
        throw new AssertionError("Missing touch target "+panel+"/"+index);
    }
    private static void shot(String name)throws Exception {
        Thread.sleep(200);
        PlatformImage screen=Mobile.getPlatform().getLcdFrontbuffer();
        BufferedImage image=new BufferedImage(800,480,BufferedImage.TYPE_INT_RGB);
        synchronized(screen){
            int[] pixels=screen.getDataBuffer();
            for(int x=0;x<800;x++)for(int y=0;y<480;y++)image.setRGB(x,y,pixels[x*480+479-y]);
        }
        ImageIO.write(image,"png",new File(name+".png"));
    }
    private static boolean setting(String name)throws Exception{return flag(game,name);}
    static void check(ClassLoader loader)throws Exception {
        game=Class.forName("a",true,loader);menu=Class.forName("GF3Pause",true,loader);
        int farm=(Integer)MarketProbe.method(game,"a",int.class).invoke(null);
        if(farm!=17 && farm!=18)throw new AssertionError("Expected loaded farm, state "+farm);
        tap(755,40);expect(game,"J",true);
        short[][] c=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[15];
        if(c[1][2]!=198 || c[1][3]!=20 || c[4][2]!=404 || c[4][3]!=88
                || c[13][2]!=57 || c[13][3]!=34)throw new AssertionError("Wrong Android layout");
        shot("pausa");
        for(int id:new int[]{2,9,151,153}){
            button(id);
            if((Long)MarketProbe.field(menu,null,"messageUntil",long.class)<=System.currentTimeMillis())
                throw new AssertionError("Missing offline message "+id);
        }
        Thread.sleep(1000);
        shot("sin-conexion");
        for(int i=0;i<70 && (Long)MarketProbe.field(menu,null,"messageUntil",long.class)!=0;i++)Thread.sleep(70);
        if((Long)MarketProbe.field(menu,null,"messageUntil",long.class)!=0)throw new AssertionError("Offline message did not expire");
        button(7);expect(game,"K",true);shot("acerca-de");
        String credits=(String)MarketProbe.field(game,null,"n",String.class);
        if(!credits.contains("4.4.4") || !credits.contains("2018") || credits.split("\n").length<470)
            throw new AssertionError("Original rolling credits missing");
        button(18);expect(game,"J",true);
        button(4);expect(game,"N",true);shot("opciones");
        button(24);expect(game,"M",true);
        boolean music=setting("T"),sound=setting("S");
        button(40);button(43);
        if(setting("T")==music || setting("S")==sound)throw new AssertionError("Sound toggles did not change");
        button(40);button(43);
        if(setting("T")!=music || setting("S")!=sound)throw new AssertionError("Sound settings did not restore");
        shot("sonido");button(46);expect(game,"N",true);
        button(26);expect(game,"L",true);shot("ayuda");
        java.util.HashSet<String> topics=new java.util.HashSet<>();
        for(int i=0;i<21;i++) {
            String heading=(String)MarketProbe.method(menu,"heading",String.class,int.class).invoke(null,0);
            String page=(String)MarketProbe.method(menu,"body",String.class,int.class).invoke(null,0);
            if(!topics.add(heading) || page.length()<15)throw new AssertionError("Empty or duplicate help topic "+heading);
            if(heading.toLowerCase().contains("extractor"))shot("ayuda-extractor");
            button(55);
        }
        if((Integer)MarketProbe.field(game,null,"et",int.class)!=1 || !topics.contains("Ayuda del perro"))
            throw new AssertionError("Android help did not wrap to its beginning");
        button(54);button(161);button(48);expect(game,"N",true);
        button(28);expect(menu,"choosingLanguage",true);shot("idioma");
        button(156);button(159);expect(menu,"choosingLanguage",false);expect(game,"N",true);
        button(34);expect(game,"J",true);
        button(13);
        if((Integer)MarketProbe.method(game,"a",int.class).invoke(null)!=42)
            throw new AssertionError("Exit confirmation did not open");
        shot("confirmacion-salir");button(27,6);expect(game,"J",true);button(145);
        for(int i=0;i<70;i++){
            int screen=(Integer)MarketProbe.method(game,"a",int.class).invoke(null);
            if(screen==farm){
                int level=(Integer)MarketProbe.method(game,"f",int.class).invoke(null);
                if(level!=3)throw new AssertionError("Wrong farm after closing pause");
                shot("granja");System.out.println("PAUSE_OK four offline links, options and return to level 3");return;
            }
            Thread.sleep(70);
        }
        shot("regreso-interrumpido");
        throw new AssertionError("Pause did not return to farm "+farm+", state "+MarketProbe.method(game,"a",int.class).invoke(null));
    }
}
