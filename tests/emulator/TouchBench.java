import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.file.*;
import java.net.SocketPermission;
import java.security.Permission;
import java.util.*;
import java.security.MessageDigest;
import javax.imageio.ImageIO;
import org.recompile.mobile.*;

/** External MIDP test front end. The game JAR is loaded unchanged by FreeJ2ME-Plus. */
public final class TouchBench {
    private static long started, first, last;
    private static int count;
    private static long[] intervals = new long[4096];
    private static int intervalCount;
    private static int changedCount, previousHash;
    private static int[] countersBefore;
    private static String scenario="";
    private static java.lang.reflect.Field camera,cameraX,cameraY;
    private static java.lang.reflect.Field drawFrame,groundEnd;
    private static int cameraFrames,lastCameraX,lastCameraY,traveled;
    private static int groundFrames;
    private static void sampleCamera() {
        if(scenario.isEmpty()) return;
        try {
            if(camera==null) {
                ClassLoader loader=Mobile.getPlatform().loader;
                Class<?> actor=Class.forName("f",false,loader);
                for(java.lang.reflect.Field field:Class.forName("a",false,loader).getDeclaredFields())
                    if(field.getName().equals("c") && field.getType()==actor) camera=field;
                camera.setAccessible(true);
                cameraX=actor.getDeclaredField("r");cameraX.setAccessible(true);
                cameraY=actor.getDeclaredField("s");cameraY.setAccessible(true);
                try {
                    drawFrame=Class.forName("GF3Draw",false,loader).getDeclaredField("current");
                    drawFrame.setAccessible(true);
                    groundEnd=drawFrame.getType().getDeclaredField("groundEnd");
                    groundEnd.setAccessible(true);
                } catch(ClassNotFoundException | NoSuchFieldException original) {groundEnd=null;}
            }
            if(groundEnd!=null && groundEnd.getInt(drawFrame.get(null))>0) groundFrames++;
            Object actor=camera.get(null);
            if(actor==null) return;
            int x=cameraX.getInt(actor),y=cameraY.getInt(actor);
            if(count>0 && (x!=lastCameraX || y!=lastCameraY)) {
                cameraFrames++;
                traveled+=Math.abs(x-lastCameraX)+Math.abs(y-lastCameraY);
            }
            lastCameraX=x;lastCameraY=y;
        } catch(ReflectiveOperationException e) {throw new IllegalStateException(e);}
    }
    private static int[] counters() {
        final String[] names = {"ticks","presentations","interpolated","matchedSprites"};
        try {
            Class<?> perf = Class.forName("GF3Presentation",false,Mobile.getPlatform().loader);
            int[] values = new int[names.length];
            for(int i=0;i<names.length;i++) {
                java.lang.reflect.Field field = perf.getDeclaredField(names[i]);
                field.setAccessible(true);
                values[i]=field.getInt(null);
            }
            return values;
        } catch (ClassNotFoundException e) {return null;}
        catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
    }
    private static boolean sampling = false;
    private static final ArrayList<String> samples = new ArrayList<>();
    private static synchronized void present() {
        long now = System.nanoTime();
        if (sampling) {
            sampleCamera();
            PlatformImage lcd = Mobile.getPlatform().getLcdFrontbuffer();
            int hash;
            synchronized (lcd) { hash = Arrays.hashCode(lcd.getDataBuffer()); }
            if (count == 0 || previousHash != hash) changedCount++;
            previousHash = hash;
            samples.add(now + "," + Integer.toUnsignedString(hash));
        }
        if (count == 0) first = now;
        else if (intervalCount < intervals.length) intervals[intervalCount++] = now - last;
        last = now;
        count++;
    }
    private static synchronized void reset(String name) {
        scenario=name;count=0;intervalCount=0;changedCount=0;cameraFrames=0;traveled=0;groundFrames=0;
        countersBefore=counters();sampling=true;samples.clear();
    }
    private static synchronized void report() {
        long[] sorted = Arrays.copyOf(intervals, intervalCount);
        Arrays.sort(sorted);
        if(!scenario.isEmpty()) System.out.println("SCENARIO "+scenario+" cameraMoves="+cameraFrames+
                " cameraPixels="+traveled+" capturedTerrainFrames="+groundFrames);
        System.out.printf(Locale.ROOT, "METRIC presents=%d span=%.3f fps=%.3f p50_ms=%.3f p95_ms=%.3f%n", count,
            (last - first) / 1e9, count > 1 ? (count - 1)*1e9 / (last-first) : 0,
            sorted.length > 0 ? sorted[sorted.length/2] / 1e6 : 0, sorted.length > 0 ? sorted[(sorted.length-1)*95/100] / 1e6 : 0);
        if (sampling) {
            sampling = false;
            System.out.printf(Locale.ROOT, "PIXELS changed=%d rate=%.3f%n", changedCount, count>1 ? (changedCount-1)*1e9/(last-first) : 0);
            if(countersBefore!=null) {
                int[] after=counters();
                for(int i=0;i<after.length;i++) after[i]-=countersBefore[i];
                System.out.printf("COUNTERS ticks=%d presentations=%d interpolated=%d matchedSprites=%d%n",
                    after[0],after[1],after[2],after[3]);
            }
            String filename=scenario.isEmpty()?"frames.csv":("frames-"+scenario+".csv");
            try (PrintWriter out = new PrintWriter(filename, "UTF-8")) {
                out.println("monotonic_nanos,frontbuffer_pixel_hash");
                for(String row:samples) out.println(row);
            } catch(IOException e) {throw new UncheckedIOException(e);}
        }
    }
    // Compare just the glyphs. Background animations cannot satisfy or break the check.
    static int screenPixel(int x,int y) {
        int w=MobilePlatform.lcdWidth,h=MobilePlatform.lcdHeight;
        if(w==480 && h==800) return y*w+x;
        boolean landscape=w>h;
        int sw=landscape?800:480,sh=landscape?480:800;
        int dw=Math.min(w,h*sw/sh),dh=Math.min(h,w*sh/sw);
        int sx=landscape?y:x,sy=landscape?479-x:y;
        return ((h-dh)/2+(sy*dh+sh-1)/sh)*w+(w-dw)/2+(sx*dw+sw-1)/sw;
    }
    private static void tapLogical(int x,int y,long ms) throws InterruptedException {
        int loc=screenPixel(x,y),w=MobilePlatform.lcdWidth;
        MobilePlatform.pointerPressed(loc%w,loc/w);Thread.sleep(ms);MobilePlatform.pointerReleased(loc%w,loc/w);
    }
    private static void untilGlyph(MobilePlatform platform, String[] cmd) throws Exception {
        int x=Integer.parseInt(cmd[1]), y=Integer.parseInt(cmd[2]);
        int w=Integer.parseInt(cmd[3]), h=Integer.parseInt(cmd[4]);
        int color=Integer.parseInt(cmd[5],16);
        if(cmd[6].length()!=64) throw new IllegalArgumentException("Expected a full SHA-256 digest");
        byte[] expected=new byte[32];
        for(int i=0;i<expected.length;i++) expected[i]=(byte)Integer.parseInt(cmd[6].substring(2*i,2*i+2),16);
        byte[] mask=new byte[w*h];
        final MessageDigest sha=MessageDigest.getInstance("SHA-256");
        long end=System.nanoTime()+Long.getLong("gf3.bench.glyphSeconds",25L)*1_000_000_000L, nextTap=System.nanoTime()+1_200_000_000L;
        while(System.nanoTime()<end) {
            PlatformImage lcd=platform.getLcdFrontbuffer();
            synchronized(lcd) {
                int[] pixels=lcd.getDataBuffer();
                for(int i=0;i<h;i++) {
                    for(int j=0;j<w;j++) mask[i*w+j]=(byte)(((pixels[screenPixel(x+j,y+i)]&0xffffff)==color)?1:0);
                }
            }
            if(Arrays.equals(expected,sha.digest(mask))) return;
            if(cmd.length==9 && System.nanoTime()>=nextTap) {
                int tx=Integer.parseInt(cmd[7]),ty=Integer.parseInt(cmd[8]);
                tapLogical(tx,ty,100);
                nextTap=System.nanoTime()+1_200_000_000L;
            }
            Thread.sleep(50);
        }
        throw new AssertionError("Expected on-screen glyphs absent: "+Arrays.toString(cmd));
    }
    public static void main(String[] args) {
        try { run(args); }
        catch (Throwable failure) { failure.printStackTrace(); System.exit(1); }
    }
    private static void checkStock(String[] command) throws Exception {
        Class<?> game = Class.forName("a",false,Mobile.getPlatform().loader);
        int product=Integer.parseInt(command[1]), expected=Integer.parseInt(command[2]);
        int actual=nativeNumber(game,"g",0,product);
        if (actual!=expected) throw new AssertionError("Product "+product+" expected "+expected+" got "+actual);
        System.out.println("STOCK product="+product+" quantity="+actual);
    }
    private static void waitPose(MobilePlatform platform,String[] cmd) throws Exception {
        BufferedImage before=ImageIO.read(new File(cmd[1]+".png"));
        int x=Integer.parseInt(cmd[2]), y=Integer.parseInt(cmd[3]);
        int w=Integer.parseInt(cmd[4]), h=Integer.parseInt(cmd[5]), minimum=Integer.parseInt(cmd[6]);
        int[] previous=before.getRGB(x,y,w,h,null,0,w);
        long end=System.nanoTime()+3_000_000_000L;
        while(System.nanoTime()<end) {
            PlatformImage lcd=platform.getLcdFrontbuffer();
            int changed=0;
            synchronized(lcd){
                int[] rgb=lcd.getDataBuffer();
                for(int j=0;j<h;j++)for(int i=0;i<w;i++)
                    if(((previous[j*w+i]^rgb[(j+y)*MobilePlatform.lcdWidth+x+i])&0xffffff)!=0)changed++;
            }
            if(changed>=minimum) {System.out.println("ANIMATION changedPixels="+changed);return;}
            Thread.sleep(40);
        }
        throw new AssertionError("Expected the press to turn inside its original sprite bounds");
    }
    private static int nativeNumber(Class<?> type,String name,int... arguments) throws Exception {
        Class<?>[] parameters=new Class<?>[arguments.length];
        Object[] values=new Object[arguments.length];
        Arrays.fill(parameters,int.class);
        for(int i=0;i<arguments.length;i++) values[i]=arguments[i];
        for(java.lang.reflect.Method method:type.getDeclaredMethods()) {
            if (method.getName().equals(name) && method.getReturnType()==int.class &&
                    Arrays.equals(parameters,method.getParameterTypes())) {
                method.setAccessible(true);
                return (Integer)method.invoke(null,values);
            }
        }
        throw new NoSuchMethodException(name);
    }
    private static void checkFarm(String[] cmd) throws Exception {
        ClassLoader loader=Mobile.getPlatform().loader;
        Class<?> game=Class.forName("a",false,loader),actor=Class.forName("f",false,loader);
        int menu=nativeNumber(game,"a"),level=nativeNumber(game,"f"),coins=nativeNumber(game,"d"),
            bills=nativeNumber(game,"e"),pens=nativeNumber(actor,"a",0,54),plots=nativeNumber(actor,"a",0,49);
        if(menu!=17 || level!=Integer.parseInt(cmd[1]) || coins!=Integer.parseInt(cmd[2]) ||
                bills!=Integer.parseInt(cmd[3]) || pens<1 || plots<1)
            throw new AssertionError("Farm menu/level/coins/bills/animals/plots="+menu+"/"+level+"/"+
                    coins+"/"+bills+"/"+pens+"/"+plots);
        System.out.println("FARM_OK level="+level+" coins="+coins+" bills="+bills+
                           " animals="+pens+" plots="+plots);
    }
    private static void run(String[] args) throws Exception {
        final Path root = Paths.get(".").toRealPath();
        ImageIO.setUseCache(false);
        System.setSecurityManager(new SecurityManager(){
            @Override public void checkPermission(Permission permission) {
                if (permission instanceof SocketPermission) throw new SecurityException("Offline test");
                if (permission instanceof FilePermission) {
                    String a = permission.getActions();
                    if(a.contains("execute")) throw new SecurityException("Child processes disabled");
                    if ((a.contains("write") || a.contains("delete")) &&
                        !Paths.get(permission.getName().replace("*", "probe")).toAbsolutePath().normalize().startsWith(root))
                        throw new SecurityException("Writes restricted to test profile");
                }
            }
            @Override public void checkPermission(Permission p,Object context){ checkPermission(p); }
        });
        final int width = Integer.parseInt(args[1]), height = Integer.parseInt(args[2]);
        final MobilePlatform platform = new MobilePlatform(width, height);
        MobilePlatform.isLibretro = true;
        Mobile.setPlatform(platform, () -> Mobile.updateSettings());
        if (!platform.load(new File(args[0]).toURI().toString())) throw new IOException("Load failed");
        Mobile.config.settings.put("scrwidth", ""+width);
        Mobile.config.settings.put("scrheight", ""+height);
        Mobile.config.settings.put("fps", args.length > 3 ? args[3] : "0");
        Mobile.config.settings.put("fpshack", "Default");
        Mobile.config.sysSettings.put("sound", "off");
        if(Boolean.getBoolean("gf3.bench.audio")) {
            Class.forName("CaptureAudio").getMethod("install").invoke(null);
            Mobile.config.sysSettings.put("sound","on");
        }
        Mobile.updateSettings();
        System.setProperty("microedition.locale", "es-MX");
        platform.setPainter(TouchBench::present);
        new Thread(() -> platform.runJar(), "test-session").start();
        started = System.nanoTime();
        System.out.println("READY");
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, "UTF-8"));
        String line;
        while ((line = input.readLine()) != null) {
            String[] t = line.trim().split(" +");
            switch(t[0]) {
            case "touchlogical":
                tapLogical(Integer.parseInt(t[1]),Integer.parseInt(t[2]),100);break;
            case "touch":
                int x=Integer.parseInt(t[1]), y=Integer.parseInt(t[2]);
                MobilePlatform.pointerPressed(x,y);
                Thread.sleep(t.length > 3 ? Integer.parseInt(t[3]) : 100);
                MobilePlatform.pointerReleased(x,y);
                break;
            case "key":
                int k=Mobile.getMobileKey(Integer.parseInt(t[1]));
                MobilePlatform.keyPressed(k);Thread.sleep(100);MobilePlatform.keyReleased(k);break;
            case "drag":
                int x0=Integer.parseInt(t[1]), y0=Integer.parseInt(t[2]);
                int x1=Integer.parseInt(t[3]), y1=Integer.parseInt(t[4]);
                int n=Integer.parseInt(t[5]), delay=Integer.parseInt(t[6]);
                MobilePlatform.pointerPressed(x0,y0);
                for(int i=1;i<=n;i++) {
                    Thread.sleep(delay);
                    MobilePlatform.pointerDragged(x0+(x1-x0)*i/n,y0+(y1-y0)*i/n);
                }
                MobilePlatform.pointerReleased(x1,y1);break;
            case "shot":
                PlatformImage lcd=platform.getLcdFrontbuffer();
                BufferedImage img = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
                synchronized(lcd) { img.setRGB(0,0,width,height,lcd.getDataBuffer(),0,width); }
                ImageIO.write(img,"png",new File(t[1]+".png"));break;
            case "measure": reset(t.length>1?t[1]:"");break;
            case "pan":
                int ax=Integer.parseInt(t[1]),ay=Integer.parseInt(t[2]);
                int bx=Integer.parseInt(t[3]),by=Integer.parseInt(t[4]);
                int locA=screenPixel(ax,ay),locB=screenPixel(bx,by),lcdW=MobilePlatform.lcdWidth;
                ax=locA%lcdW;ay=locA/lcdW;bx=locB%lcdW;by=locB/lcdW;
                int legs=Integer.parseInt(t[5]),duration=Integer.parseInt(t[6]);
                MobilePlatform.pointerPressed(ax,ay);
                Thread.sleep(90);
                long origin=System.nanoTime(),elapsed;
                while((elapsed=(System.nanoTime()-origin)/1000000L)<(long)legs*duration) {
                    int part=(int)(elapsed%duration);
                    if(((elapsed/duration)&1)!=0) part=duration-part;
                    MobilePlatform.pointerDragged(ax+(bx-ax)*part/duration,ay+(by-ay)*part/duration);
                    Thread.sleep(8);
                }
                MobilePlatform.pointerReleased((legs&1)==0?ax:bx,(legs&1)==0?ay:by);
                break;
            case "assertstock": checkStock(t);break;
            case "assertfarm": checkFarm(t);break;
            case "waitglyph": untilGlyph(platform,t);break;
            case "waitpose": waitPose(platform,t);break;
            case "report": report();break;
            case "wait": Thread.sleep(Integer.parseInt(t[1]));break;
            case "close":
                Mobile.midlet.getClass().getMethod("destroyApp",boolean.class).invoke(Mobile.midlet,true);
                break;
            case "quit": System.exit(0);return;
            default: throw new IllegalArgumentException(line);
            }
            System.out.printf(Locale.ROOT, "ACK %.3f %s%n", (System.nanoTime()-started)/1e9,line);System.out.flush();
        }
        System.exit(0);
    }
}
