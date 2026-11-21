import java.awt.image.BufferedImage;
import java.io.File;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.zip.ZipFile;
import javax.imageio.ImageIO;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Compare the rendered title with an actual screenshot from the unmodified APK. */
final class LoadingProbe {
    private static Method menu;
    private static volatile boolean verified;
    private static BufferedImage reference;
    private static BufferedImage spanish;

    static void prepare(String file, String game) throws Exception {
        reference = ImageIO.read(new File(file));
        if (reference.getWidth() != 800 || reference.getHeight() != 480)
            throw new AssertionError("Unexpected reference size");
        // These RGBA digests come from an independent alpha composition of the
        // Android font frames over transparency using the original LATAM text.
        try (ZipFile jar=new ZipFile(game)) {
            spanish=originalGlyphs(jar,"cargando.png",131,27,
                "524c2b32ea35057571d6df18d4e55603167f49a69ffd76e62ff47421270e1295");
            originalGlyphs(jar,"copyright.png",218,23,
                "4708fc25853d98634c8bf74bfa947dedff3509cd043e8e683e1e98b78efdaf43");
        }
    }

    private static BufferedImage originalGlyphs(ZipFile jar,String name,int width,int height,
                                                String expected) throws Exception {
        BufferedImage art;
        try (InputStream data=jar.getInputStream(jar.getEntry(name))) {
            art=ImageIO.read(data);
        }
        if (art.getWidth()!=width || art.getHeight()!=height) throw new AssertionError(name+" bounds");
        MessageDigest hash=MessageDigest.getInstance("SHA-256");
        for (int y=0;y<height;y++) for (int x=0;x<width;x++) {
            int pixel=art.getRGB(x,y);
            hash.update((byte)(pixel>>16));
            hash.update((byte)(pixel>>8));
            hash.update((byte)pixel);
            hash.update((byte)(pixel>>24));
        }
        if (!expected.equals(HexFormat.of().formatHex(hash.digest()))) throw new AssertionError(name+" glyphs");
        return art;
    }

    private static int spanishInk(BufferedImage lcd) {
        int hits=0;
        for (int y=0;y<spanish.getHeight();y++) for (int x=0;x<spanish.getWidth();x++) {
            int glyph=spanish.getRGB(x,y);
            if ((glyph>>>24)==255 && glyph==lcd.getRGB(336+x,379+y)) hits++;
        }
        return hits;
    }

    static void observe(MobilePlatform platform) {
        if (verified || platform.loader == null) return;
        try {
            if (menu == null) {
                for (Method method : Class.forName("a",false,platform.loader).getDeclaredMethods()) {
                    if (method.getName().equals("a") && method.getParameterCount()==0 && method.getReturnType()==int.class) {
                        method.setAccessible(true);
                        menu=method;
                        break;
                    }
                }
            }
            if (menu == null || (Integer)menu.invoke(null)!=4) return;
            PlatformImage lcd=platform.getLcdFrontbuffer();
            BufferedImage result=new BufferedImage(800,480,BufferedImage.TYPE_INT_RGB);
            synchronized(lcd) {
                int[] pixels=lcd.getDataBuffer();
                for (int y=0;y<480;y++) for (int x=0;x<800;x++)
                    result.setRGB(x,y,pixels[x*480+479-y]);
            }
            // The APK's EGL surface uses 16-bit display colors. The JAR retains its
            // source texture colors. Compare positions including every edge of the logo.
            int maximum=0, footerMaximum=0;
            long error=0, footerError=0;
            for (int y=0;y<480;y++) for (int x=0;x<800;x++) {
                // The Android reference has an English status and a dynamic bar.
                if (y>=375 && y<440) continue;
                int android=reference.getRGB(x,y), midp=result.getRGB(x,y);
                for (int shift=0;shift<=16;shift+=8) {
                    int delta=Math.abs(((android>>shift)&255)-((midp>>shift)&255));
                    if (y<375) {
                        maximum=Math.max(maximum,delta);
                        error+=delta;
                    } else {
                        footerMaximum=Math.max(footerMaximum,delta);
                        footerError+=delta;
                    }
                }
            }
            int ink=spanishInk(result);
            ImageIO.write(result,"png",new File("carga.png"));
            if (maximum<=24 && error<=6L*800*375*3 && footerMaximum<=24 &&
                    footerError<=6L*800*40*3 && ink==2296) {
                System.out.println("LOADING_OK pixels=332000 artMax="+maximum+
                        " artMean="+error/(3.0*800*375)+" footerMax="+footerMaximum+
                        " footerMean="+footerError/(3.0*800*40)+" spanishOpaque="+ink);
                verified=true;
            }
        } catch (ReflectiveOperationException | java.io.IOException failure) {
            throw new AssertionError(failure);
        }
    }

    static void await() throws Exception {
        long end=System.nanoTime()+45_000_000_000L;
        while (!verified && System.nanoTime()<end) Thread.sleep(100);
        if (!verified) throw new AssertionError("The original loading artwork was not shown");
    }
}
