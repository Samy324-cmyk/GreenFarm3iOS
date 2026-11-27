import java.lang.reflect.Field;
import java.lang.reflect.Method;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Exercise the presented animation at fractional positions on the northern camera limit. */
final class SceneMotionProbe {
    static void check(ClassLoader loader) throws Exception {
        Class<?> a=Class.forName("a",true,loader),f=Class.forName("f",true,loader),
            k=Class.forName("k",true,loader),engine=Class.forName("g",true,loader),
            draw=Class.forName("GF3Draw",true,loader);
        Object camera=MarketProbe.field(a,null,"c",f);
        Method move=MarketProbe.method(f,"c",void.class,int.class,int.class);
        Method terrain=MarketProbe.method(k,"a",void.class,Graphics.class,int.class,int.class,int.class);
        Field target=MarketProbe.variable(engine,"a",Graphics.class);
        synchronized(Class.forName("GF3Presentation",false,loader)) {
            Object saved=target.get(null);
            try {
                Image first=Image.createImage(480,800);
                Image second=Image.createImage(480,800);
                Image intermediate=Image.createImage(480,800);
                for(int i=0;i<2;i++) {
                    move.invoke(camera,100+i*12,0);
                    MarketProbe.method(k,"f",void.class).invoke(null);
                    terrain.invoke(null,null,0,0,0);
                    MarketProbe.variable(a,"l",boolean.class).setBoolean(null,true);
                    Graphics g=(i==0?first:second).getGraphics();
                    target.set(null,g);
                    MarketProbe.method(draw,"begin",void.class,Graphics.class).invoke(null,g);
                    MarketProbe.method(draw,"world",void.class).invoke(null);
                    MarketProbe.method(draw,"stop",void.class).invoke(null);
                    MarketProbe.method(draw,"match",int.class).invoke(null);
                }
                // Slot 79 anchors the cloud bank horizontally to the LCD.
                // The mountain and tree layers are below this 800x130-band.
                int[] expected=new int[800*130],now=new int[800*130],test=new int[800*130];
                first.getRGB(expected,0,130,130,0,130,800);
                second.getRGB(now,0,130,130,0,130,800);
                if(!java.util.Arrays.equals(expected,now)) throw new AssertionError("Native cloud projection moved");
                int errors=0;
                for(int remaining:new int[]{13,25,38}) {
                    MarketProbe.method(draw,"replay",void.class,Graphics.class,int.class,int.class)
                        .invoke(null,intermediate.getGraphics(),remaining,50);
                    intermediate.getRGB(test,0,130,130,0,130,800);
                    int diff=0;for(int p=0;p<expected.length;p++)if(expected[p]!=test[p])diff++;
                    errors+=diff;
                    System.out.println("SKY_INTERMEDIATE "+remaining+" "+diff);
                }
                if(errors!=0)throw new AssertionError("Fixed clouds jittered by "+errors+" pixels");
            } finally {target.set(null,saved);}
        }
        System.out.println("MOTION_OK");
    }
}
