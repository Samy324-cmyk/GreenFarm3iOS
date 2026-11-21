import java.lang.reflect.Field;
import javax.microedition.lcdui.Image;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Compare the real emulator LCD, including letterboxing, to the MIDlet's painted portrait frame. */
final class ViewportProbe {
    static void check() throws Exception {
        ClassLoader loader=Mobile.getPlatform().loader;
        Class<?> presentation=Class.forName("GF3Presentation",false,loader);
        Field portrait=Class.forName("GF3Viewport",false,loader).getDeclaredField("portrait");
        portrait.setAccessible(true);
        int w=MobilePlatform.lcdWidth,h=MobilePlatform.lcdHeight;
        int sw=w>h?800:480,sh=w>h?480:800;
        int dw=Math.min(w,h*sw/sh),dh=Math.min(h,w*sh/sw);
        int left=(w-dw)/2,top=(h-dh)/2;
        int[] frame=new int[480*800];
        int differences=-1;
        for(int retry=0;retry<20;retry++) {
            synchronized(presentation) {
                Image image=(Image)portrait.get(null);
                image.getRGB(frame,0,480,0,0,480,800);
                PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
                synchronized(lcd) {
                    differences=0;
                    int[] actual=lcd.getDataBuffer();
                    for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
                        int wanted=0;
                        if(x>=left && y>=top && x<left+dw && y<top+dh) {
                            int u=(x-left)*sw/dw,v=(y-top)*sh/dh;
                            wanted=w>h?frame[u*480+479-v]:frame[v*480+u];
                        }
                        if(((wanted^actual[y*w+x])&0xffffff)!=0) differences++;
                    }
                }
            }
            if(differences==0) {
                System.out.println("VIEWPORT_OK lcd="+w+"x"+h+" game="+dw+"x"+dh+" pixels="+w*h);
                return;
            }
            Thread.sleep(25);
        }
        throw new AssertionError("Physical screen differs at "+differences+" pixels");
    }
}
