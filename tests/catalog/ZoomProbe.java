import java.awt.image.BufferedImage;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.lang.reflect.Method;
import java.util.Arrays;
import javax.imageio.ImageIO;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Verify the unobstructed farm, single-pointer options and multipoint input. */
final class ZoomProbe {
    private static void tap(int x,int y)throws Exception {
        MobilePlatform.pointerPressed(479-y,x);
        Thread.sleep(110);
        MobilePlatform.pointerReleased(479-y,x);
        Thread.sleep(350);
    }
    static void toggle(Class<?> game)throws Exception {
        tap(755,40);
        tap(492,134);
        if(!(Boolean)MarketProbe.field(game,null,"N",boolean.class))throw new AssertionError("Options unavailable");
        tap(275,287);
        tap(106,72);
        tap(755,42);
    }
    private static void checkView(Class<?> game,Class<?> tiles,int zoom) throws Exception {
        long end=System.currentTimeMillis()+10000;
        int width=zoom==50?36:72,height=zoom==50?18:36;
        do {
            int current=(Integer)MarketProbe.field(game,null,"B",int.class);
            int[] metrics=(int[])MarketProbe.field(tiles,null,"p",int[].class);
            if(current==zoom && metrics!=null && metrics[2]==width && metrics[5]==height)
                return;
            Thread.sleep(30);
        } while(System.currentTimeMillis()<end);
        throw new AssertionError("Touch did not select the "+width+"x"+height+" terrain tiles");
    }

    static void check(ClassLoader loader) throws Exception {
        Class<?> game=Class.forName("a",true,loader),tiles=Class.forName("k",true,loader);
        checkView(game,tiles,100);
        short[] old=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[1][58];
        if(old[10]!=0 || old[18]!=0)throw new AssertionError("Legacy zoom button present");
        for(int[] hit:(int[][])MarketProbe.field(game,null,"i",int[][].class))
            if(hit[5]==65594 && hit[2]>0 && hit[3]>0)throw new AssertionError("Legacy zoom hotspot present");
        for(int zoom:new int[]{50,100}) {
            Thread.sleep(750);
            toggle(game);
            checkView(game,tiles,zoom);
        }
        Class<?> f=Class.forName("f",true,loader);
        Object canvas=Mobile.getDisplay().getCurrent(),camera=MarketProbe.field(game,null,"c",f);
        int centerX=value(f,camera,"r")+400,centerY=value(f,camera,"s")+240;
        Thread.sleep(400);
        byte[] hud=hudMask();
        try {
            finger(game,canvas,0,"Pressed",80,240);
            finger(game,canvas,1,"Pressed",700,240);
            for(int z:new int[]{87,75,67,57,51,50,64,82,75}) {
                finger(game,canvas,1,"Dragged",700-(100-z)*10,240);
                checkView(game,tiles,z);
                Thread.sleep(190);
                if(Math.abs(value(f,camera,"r")+400-centerX*z/100)>1 ||
                   Math.abs(value(f,camera,"s")+240-centerY*z/100)>1)
                    throw new AssertionError("Viewport center drift at "+z);
                if(z==67 || z==75){
                    if(!Arrays.equals(hud,hudMask()))throw new AssertionError("HUD glyphs moved at "+z);
                    saveLCD("farm-zoom-"+z);
                }
            }
            finger(game,canvas,1,"Released",450,240);
            finger(game,canvas,0,"Released",80,240);
        } finally {System.clearProperty("com.nokia.pointer.number");}
        Thread.sleep(240);
        Object[] layers=(Object[])MarketProbe.field(f,null,"a",java.lang.reflect.Array.newInstance(f,0).getClass());
        Object crop=null;
        for(Object cur=layers[0];cur!=null;cur=MarketProbe.field(f,cur,"a",f)) {
            int x=value(f,cur,"u"),y=value(f,cur,"v");
            if(value(f,cur,"q")==49 && value(f,cur,"D")==5 && x>240 && x<575 && y>150 && y<385) {
                crop=cur;break;
            }
        }
        if(crop==null)throw new AssertionError("No wheat in fixture viewport");
        tap(value(f,crop,"u"),value(f,crop,"v")-12);
        long end=System.currentTimeMillis()+5000;
        while(value(f,crop,"D")!=1 && System.currentTimeMillis()<end)Thread.sleep(40);
        if(value(f,crop,"D")!=1 || value(f,crop,"y")!=0)throw new AssertionError("Projected wheat tap missed");
        terrain(loader,camera);
        System.out.println("ZOOM_OK native options, centered pinch across 50..100%, fixed HUD, wheat harvest at 75%");
    }

    static int value(Class<?> type,Object o,String field)throws Exception {
        return (Integer)MarketProbe.field(type,o,field,int.class);
    }

    private static void finger(Class<?> game,Object canvas,int number,String phase,int x,int y)throws Exception {
        System.setProperty("com.nokia.pointer.number",Integer.toString(number));
        MarketProbe.method(game,"pointer"+phase,void.class,int.class,int.class).invoke(canvas,479-y,x);
    }

    private static byte[] hudMask()throws Exception {
        // Coin, cash, experience, level. The outline/letter masks exclude farm scenery.
        int[][] boxes={{98,16,70,38,0x1979eb},{97,60,61,31,0x1979eb},
                       {389,26,60,23,0xffffff},{246,12,32,34,0x1979eb}};
        java.io.ByteArrayOutputStream mask=new java.io.ByteArrayOutputStream();
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        synchronized(lcd){
            int[] data=lcd.getDataBuffer();
            for(int[] b:boxes){
                int ink=0;
                for(int y=b[1];y<b[1]+b[3];y++)for(int x=b[0];x<b[0]+b[2];x++){
                    int hit=(data[x*480+479-y]&0xffffff)==b[4]?1:0;
                    mask.write(hit);ink+=hit;
                }
                if(ink<4)throw new AssertionError("Missing native HUD text at "+b[0]+","+b[1]);
            }
        }
        return mask.toByteArray();
    }

    private static void saveLCD(String name)throws Exception{
        BufferedImage img=new BufferedImage(800,480,BufferedImage.TYPE_INT_RGB);
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        synchronized(lcd){
            int[] pixels=lcd.getDataBuffer();
            for(int y=0;y<480;y++)for(int x=0;x<800;x++)img.setRGB(x,y,pixels[x*480+479-y]);
        }
        ImageIO.write(img,"png",new File(name+".png"));
    }

    private static void terrain(ClassLoader loader,Object camera)throws Exception{
        Class<?> f=Class.forName("f",true,loader),k=Class.forName("k",true,loader);
        Class<?> game=Class.forName("a",true,loader);
        Method scale=MarketProbe.method(f,"e",void.class,int.class),move=MarketProbe.method(f,"c",void.class,int.class,int.class);
        Method paint=MarketProbe.method(k,"a",void.class,Graphics.class,int.class,int.class,int.class);
        int savedX=value(f,camera,"r"),savedY=value(f,camera,"s");
        synchronized(Class.forName("GF3Presentation",false,loader)){
            try(DataInputStream reference=new DataInputStream(new FileInputStream("zoom-ground.rgb"))){
                for(int z:new int[]{100,67,75}){
                    scale.invoke(null,z);move.invoke(camera,1400*z/100,(864*z+50)/100);
                    MarketProbe.method(k,"f",void.class).invoke(null);
                    paint.invoke(null,null,0,0,0);
                    Image screen=Image.createImage(480,800);
                    Graphics g=screen.getGraphics();g.setColor(0xfa05e1);g.fillRect(0,0,480,800);
                    paint.invoke(null,g,0,0,0);
                    int[] rgb=new int[480*800];screen.getRGB(rgb,0,480,0,0,480,800);
                    int mismatch=0,max=0,count=0;
                    for(int y=4;y<480;y+=11)for(int x=2;x<800;x+=11){
                        int color=rgb[x*480+479-y],error=0;
                        for(int shift=16;shift>=0;shift-=8)
                            error=Math.max(error,Math.abs(((color>>shift)&255)-reference.readUnsignedByte()));
                        max=Math.max(max,error);
                        if(error>(z==100?0:z==75?1:3))mismatch++;
                        count++;
                    }
                    System.out.println("ZOOM_GROUND "+z+" samples="+count+" overTolerance="+mismatch+" max="+max);
                    if(z==100 && mismatch!=0 || z==75 && mismatch>2 || z==67 && mismatch>count/20)
                        throw new AssertionError("Android terrain differs at "+z);
                }
            }finally{
                scale.invoke(null,75);move.invoke(camera,savedX,savedY);
                MarketProbe.method(k,"f",void.class).invoke(null);
                MarketProbe.variable(game,"l",boolean.class).setBoolean(null,true);
            }
        }
    }
}
