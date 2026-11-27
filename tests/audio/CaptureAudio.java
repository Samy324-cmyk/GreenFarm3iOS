import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import javax.sound.sampled.*;
import javax.sound.sampled.spi.MixerProvider;

/** Test-only Java Sound sink for the unchanged FreeJ2ME MMAPI decoder. */
public class CaptureAudio extends MixerProvider {
    static final Mixer.Info INFO = new Mixer.Info("GF3 capture", "local", "in-memory PCM", "1") {};
    static final AudioFormat FORMAT = new AudioFormat(32000, 16, 1, true, false);
    static final ScheduledExecutorService clock = Executors.newSingleThreadScheduledExecutor();
    static volatile long sampledHeap;
    static final ConcurrentMap<Capture,String> voices=new ConcurrentHashMap<Capture,String>();
    static final Mixer MIXER = proxy(Mixer.class, (self, method, args) -> {
        switch (method.getName()) {
        case "getMixerInfo": return INFO;
        case "getSourceLineInfo": return new Line.Info[] {new Line.Info(SourceDataLine.class),new Line.Info(Clip.class)};
        case "isLineSupported": return supports((Line.Info)args[0]);
        case "getLine":
            Line.Info info = (Line.Info)args[0];
            if (!supports(info)) throw new LineUnavailableException();
            return Clip.class.equals(info.getLineClass()) ? proxy(Clip.class, new Capture()) : proxy(SourceDataLine.class,new Capture());
        case "getMaxLines": return AudioSystem.NOT_SPECIFIED;
        }
        return defaults(self,method,args);
    });
    static boolean supports(Line.Info i) {
        return i.getLineClass() == Clip.class || i.getLineClass() == SourceDataLine.class;
    }
    public Mixer.Info[] getMixerInfo() {return new Mixer.Info[]{INFO};}
    public Mixer getMixer(Mixer.Info i) {
        if (i != null && !i.equals(INFO)) throw new IllegalArgumentException();
        return MIXER;
    }
    static <T> T proxy(Class<T> cls,InvocationHandler h) {
        return cls.cast(Proxy.newProxyInstance(CaptureAudio.class.getClassLoader(), new Class<?>[]{cls}, h));
    }
    static Object defaults(Object self,Method m,Object[] args) {
        if(m.getName().equals("hashCode")) return System.identityHashCode(self);
        if(m.getName().equals("equals")) return args[0] == self;
        if(m.getName().equals("toString")) return "GF3 capture";
        Class<?> t = m.getReturnType();
        if(t.isArray()) return java.lang.reflect.Array.newInstance(t.getComponentType(),0);
        if(t==boolean.class)return false;
        if(t==int.class)return 0;
        if(t==float.class)return 0f;
        if(t==long.class)return 0L;
        return null;
    }
    public static void install() throws Exception {
        for(Class<?> type:new Class<?>[]{Clip.class,SourceDataLine.class}) {
            System.setProperty(type.getName(),"CaptureAudio#GF3 capture");
            Line line=AudioSystem.getLine(new DataLine.Info(type, FORMAT));
            if (!Proxy.isProxyClass(line.getClass()) || !(Proxy.getInvocationHandler(line) instanceof Capture))
                throw new IllegalStateException("Expected capture mixer before enabling sound");
        }
        System.out.println("AUDIO_CAPTURE selected");
        clock.scheduleAtFixedRate(() -> {
            Runtime vm=Runtime.getRuntime();
            sampledHeap=Math.max(sampledHeap,vm.totalMemory()-vm.freeMemory());
        }, 0, 100, TimeUnit.MILLISECONDS);
    }
    static class Capture implements InvocationHandler {
        final List<LineListener> listeners = new CopyOnWriteArrayList<>();
        final FloatControl gain = new FloatControl(FloatControl.Type.MASTER_GAIN,-100,10,1,0,0,"dB") {};
        AudioFormat format = FORMAT;
        int frames=0; long position=0, started=0; boolean open=false,running=false;
        String hash=""; ScheduledFuture<?> ending;
        long length() { return Math.round(1e6*frames / format.getFrameRate()); }
        long now() {return running ? Math.min(length(),position + (System.nanoTime()-started)/1000) : position;}
        void event(Line l, LineEvent.Type type) {
            LineEvent ev=new LineEvent(l,type,(long)(now()*format.getFrameRate()/1e6));
            for(LineListener listener:listeners) listener.update(ev);
        }
        public synchronized Object invoke(Object self,Method method,Object[] args) throws Exception {
            String name=method.getName();
            if(name.equals("open")){
                open=true;
                if(args!=null && args.length!=0 && args[0] instanceof AudioInputStream) {
                    AudioInputStream in=(AudioInputStream)args[0]; format=in.getFormat();
                    MessageDigest sha=MessageDigest.getInstance("SHA-256"); long size=0,nonzero=0;
                    byte[] buf=new byte[8192]; int n;
                    while((n=in.read(buf))!=-1){sha.update(buf,0,n);size+=n;for(int i=0;i<n;i++) if(buf[i]!=0) nonzero++;}
                    frames=(int)(size/format.getFrameSize());StringBuilder hex=new StringBuilder();
                    for(byte b:sha.digest())hex.append(String.format("%02x",b));hash=hex.toString();
                    System.out.printf("PCM_OPEN %s %d %d %d %d %d%n",hash,(int)format.getSampleRate(),format.getSampleSizeInBits(),format.getChannels(),frames,nonzero);
                } else if(args!=null && args.length>0 && args[0] instanceof AudioFormat) format=(AudioFormat)args[0];
                return null;
            }
            switch(name) {
            case "getControl":return gain;
            case "getControls":return new Control[]{gain};
            case "isControlSupported":return gain.getType().equals(args[0]);
            case "getFormat":return format;
            case "getLineInfo":return new DataLine.Info(self instanceof Clip?Clip.class:SourceDataLine.class,format);
            case "getBufferSize":case "available":return 4096;
            case "getFrameLength":return frames;
            case "getFramePosition":return (int)(now()*format.getFrameRate()/1e6);
            case "getLongFramePosition":return (long)(now()*format.getFrameRate()/1e6);
            case "getMicrosecondLength":return length();
            case "getMicrosecondPosition":return now();
            case "setMicrosecondPosition":position=(Long)args[0];started=System.nanoTime();return null;
            case "setFramePosition":position=(long)((Integer)args[0]*1e6/format.getFrameRate());started=System.nanoTime();return null;
            case "isRunning":case "isActive":return running;
            case "isOpen":return open;
            case "start":
                if(running)return null;
                running=true;started=System.nanoTime();
                if(self instanceof Clip) {
                    System.out.printf("PCM_START %s %d%n",hash,position);
                    voices.put(this,hash);
                    System.out.println("PCM_MIX "+String.join(" ",voices.values()));
                    event((Line)self,LineEvent.Type.START);
                    ending=clock.schedule(()->{synchronized(this){ running=false;voices.remove(this);position=length();event((Line)self,LineEvent.Type.STOP);}},Math.max(1,length()-position),TimeUnit.MICROSECONDS);
                }
                return null;
            case "close":case "stop":
                if(ending!=null)ending.cancel(false);
                voices.remove(this);
                position=now();running=false;if(name.equals("close"))open=false;return null;
            case "addLineListener":listeners.add((LineListener)args[0]);return null;
            case "removeLineListener":listeners.remove(args[0]);return null;
            case "write":
                int bytes=(Integer)args[2];Thread.sleep(Math.max(1,Math.round(1000.0*bytes / format.getFrameSize()/format.getFrameRate())));return bytes;
            }
            return defaults(self,method,args);
        }
    }
}
