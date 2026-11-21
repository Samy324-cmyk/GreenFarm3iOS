import java.awt.image.BufferedImage;
import java.io.File;
import java.lang.reflect.Method;
import javax.imageio.ImageIO;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Render the actual circular terrain buffer, without the HUD, into a FreeJ2ME LCD image. */
final class HorizonProbe {
    static void check(ClassLoader loader) throws Exception {
        capture(loader,100);
        scenes(loader,100);
        Class<?> game=Class.forName("a",true,loader),tiles=Class.forName("k",true,loader);
        ZoomProbe.toggle(game);
        long until=System.currentTimeMillis()+10000;
        while ((Integer)MarketProbe.field(game,null,"B",int.class)!=50 ||
               ((int[])MarketProbe.field(tiles,null,"p",int[].class))[2]!=36) {
            if(System.currentTimeMillis()>until) throw new AssertionError("Half zoom did not become ready");
            Thread.sleep(25);
        }
        Thread.sleep(500);
        capture(loader,50);
        scenes(loader,50);
        System.out.println("HORIZON_OK");
    }
    /** Capture three complete playable farms through the normal Canvas paint call. */
    static void scenes(ClassLoader loader,int zoom) throws Exception {
        Class<?> game=Class.forName("a",true,loader),actor=Class.forName("f",true,loader);
        Class<?> render=Class.forName("GF3Presentation",false,loader);
        Object camera=MarketProbe.field(game,null,"c",actor);
        Method move=MarketProbe.method(actor,"c",void.class,int.class,int.class);
        for(int[] pos:new int[][]{{0,0},{313,219},{909,576}}) {
            int x=pos[0]*zoom/100,y=pos[1]*zoom/100;
            synchronized(render) {
                MarketProbe.variable(actor,"D",int.class).setInt(camera,0);
                move.invoke(camera,x,y);
                MarketProbe.method(Class.forName("k",true,loader),"f",void.class).invoke(null);
                MarketProbe.variable(game,"l",boolean.class).setBoolean(null,true);
            }
            Thread.sleep(400);
            synchronized(render) {
                if((Integer)MarketProbe.field(actor,camera,"r",int.class)!=x ||
                   (Integer)MarketProbe.field(actor,camera,"s",int.class)!=y)
                    throw new AssertionError("Farm camera moved while capturing the horizon");
                org.recompile.mobile.PlatformImage screen=org.recompile.mobile.Mobile.getPlatform().getLcdFrontbuffer();
                BufferedImage out=new BufferedImage(800,480,BufferedImage.TYPE_INT_RGB);
                synchronized(screen) {
                    int[] pixels=screen.getDataBuffer();
                    for(int sy=0;sy<480;sy++) for(int sx=0;sx<800;sx++)
                        out.setRGB(sx,sy,pixels[sx*480+479-sy]);
                }
                ImageIO.write(out,"png",new File("farm-"+zoom+"-"+x+"-"+y+".png"));
            }
        }
    }
    static void capture(ClassLoader loader,int zoom) throws Exception {
        synchronized(Class.forName("GF3Presentation",false,loader)) {
            Class<?> a=Class.forName("a",true,loader), f=Class.forName("f",true,loader);
            Class<?> k=Class.forName("k",true,loader), h=Class.forName("GF3Horizon",true,loader);
            Object camera=MarketProbe.field(a,null,"c",f);
            Method move=MarketProbe.method(f,"c",void.class,int.class,int.class);
            Method terrain=MarketProbe.method(k,"a",void.class,Graphics.class,int.class,int.class,int.class);
            Method backdrop=MarketProbe.method(h,"draw",boolean.class);
            Method startScene=MarketProbe.method(h,"worldActors",java.lang.reflect.Array.newInstance(f,0).getClass());
            int[][] poses={{0,0},{117,207},{372,478},{902,575},{1739,612},{3199,647},{3199,649},
                           {901,576},{909,583},{914,586},{929,590},{935,589},{919,580}};
            for(int i=0;i<poses.length;i++) {
                int[] pose=poses[i];
                int x=Math.min(pose[0],zoom==50?2457:3199),y=pose[1];
                x=x*zoom/100; y=y*zoom/100;
                move.invoke(camera,x,y);
                if(i<8) MarketProbe.method(k,"f",void.class).invoke(null);
                terrain.invoke(null,null,0,0,0);
                MarketProbe.variable(a,"l",boolean.class).setBoolean(null,i<8);
                startScene.invoke(null);backdrop.invoke(null);
                Image screen=Image.createImage(480,800);
                Graphics g=screen.getGraphics();
                g.setColor(0xfa05e1);g.fillRect(0,0,480,800);
                terrain.invoke(null,g,0,0,0);
                int[] rgb=new int[480*800];screen.getRGB(rgb,0,480,0,0,480,800);
                BufferedImage out=new BufferedImage(800,480,BufferedImage.TYPE_INT_RGB);
                for(int sy=0;sy<480;sy++) for(int sx=0;sx<800;sx++)
                    out.setRGB(sx,sy,rgb[sx*480+479-sy]);
                String name="horizon-"+zoom+"-"+x+"-"+y;
                ImageIO.write(out,"png",new File(name+".png"));
                java.security.MessageDigest hash=java.security.MessageDigest.getInstance("SHA-256");
                for(int sy=0;sy<480;sy++) for(int sx=0;sx<800;sx++) {
                    int c=out.getRGB(sx,sy);
                    hash.update((byte)(c>>16));hash.update((byte)(c>>8));hash.update((byte)c);
                }
                StringBuilder hex=new StringBuilder();
                for(byte b:hash.digest()) hex.append(String.format("%02x",b));
                try(java.io.PrintWriter file=new java.io.PrintWriter(name+".sha256")) {file.println(hex);}
            }
        }
    }
}
