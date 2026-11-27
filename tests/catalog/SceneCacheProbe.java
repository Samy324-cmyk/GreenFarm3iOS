import java.awt.image.BufferedImage;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import javax.imageio.ImageIO;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

final class SceneCacheProbe {
    static int[] capture(Method terrain) throws Exception {
        Image image=Image.createImage(480,800);
        terrain.invoke(null,image.getGraphics(),0,0,0);
        int[] pixels=new int[480*800];
        image.getRGB(pixels,0,480,0,0,480,800);
        return pixels;
    }
    static void save(int[] pixels,String name) throws Exception {
        BufferedImage out=new BufferedImage(800,480,BufferedImage.TYPE_INT_RGB);
        for(int y=0;y<480;y++)for(int x=0;x<800;x++)out.setRGB(x,y,pixels[x*480+479-y]);
        ImageIO.write(out,"png",new File(name+".png"));
    }
    static void edges(ClassLoader loader) throws Exception {
        Class<?> a=Class.forName("a",true,loader),f=Class.forName("f",true,loader),k=Class.forName("k",true,loader);
        Object camera=MarketProbe.field(a,null,"c",f);
        Method move=MarketProbe.method(f,"c",void.class,int.class,int.class);
        synchronized(Class.forName("GF3Presentation",false,loader)) {
            Class<?> engine=Class.forName("g",true,loader);
            Field target=MarketProbe.variable(engine,"a",Graphics.class);
            Object saved=target.get(null);
            target.set(null,Image.createImage(480,800).getGraphics());
            try {
                int[][] poses={{0,0},{3375,0},{140,554},{70,570},{65,597},{1000,617},{1030,643},
                    {1058,648},{1065,668},{1234,830},{1470,696},{1500,678},{1523,667},{1544,660},
                    {1556,657},{1567,653},{1574,646},{1601,639},{3375,1607},{0,1607},
                    // The level-three farm exposes both wrap axes and the
                    // crowns of the trees as the camera moves behind the HUD.
                    {1756,456},{1757,455},{1776,451},{1799,451},{1800,451},{1814,447},
                    {1822,432},{1823,431},{1805,435},{1786,441},{1756,456}};
                int zoom=(Integer)MarketProbe.field(a,null,"B",int.class);
                int index=0;
                for(int[] pos:poses) {
                    move.invoke(camera,pos[0]*zoom/100,pos[1]*zoom/100);
                    MarketProbe.method(k,"a",void.class,Graphics.class,int.class,int.class,int.class).invoke(null,null,0,0,0);
                    MarketProbe.method(f,"b",void.class).invoke(null);
                    compare(loader,"edge-"+index++);
                }
                System.out.println("SCENERY_OK edgeViews="+poses.length);
            } finally { target.set(null,saved); }
        }
    }
    static void check(ClassLoader loader) throws Exception { compare(loader,"tutorial"); }
    static int[] compare(ClassLoader loader,String label) throws Exception {
        Class<?> root=Class.forName("a",true,loader),actor=Class.forName("f",true,loader),
                 tiles=Class.forName("k",true,loader),engine=Class.forName("g",true,loader);
        synchronized(Class.forName("GF3Presentation",false,loader)) {
            Method terrain=MarketProbe.method(tiles,"a",void.class,Graphics.class,int.class,int.class,int.class);
            Object camera=MarketProbe.field(root,null,"c",actor);
            System.out.println("CACHE_CAMERA "+MarketProbe.field(actor,camera,"r",int.class)+","+MarketProbe.field(actor,camera,"s",int.class));
            Field target=MarketProbe.variable(engine,"a",Graphics.class);
            Object saved=target.get(null);
            target.set(null,Image.createImage(480,800).getGraphics());
            try {
                int[] before=capture(terrain);
                MarketProbe.method(tiles,"f",void.class).invoke(null);
                terrain.invoke(null,null,0,0,0);
                MarketProbe.variable(root,"l",boolean.class).setBoolean(null,true);
                MarketProbe.method(actor,"b",void.class).invoke(null);
                int[] after=capture(terrain);
                int diff=0;
                for(int i=0;i<before.length;i++)if(before[i]!=after[i])diff++;
                System.out.println("CACHE_DIFF "+diff);
                if(diff!=0) {
                    save(before,label+"-incremental");save(after,label+"-fresh");
                    throw new AssertionError("Incremental object layer differs from fresh draw at "+diff+" pixels");
                }
                System.out.println("SCENERY_CACHE_OK");
                return after;
            } finally {target.set(null,saved);}
        }
    }
}
