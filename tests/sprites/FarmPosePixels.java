import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.Arrays;
import javax.microedition.lcdui.*;
import org.recompile.mobile.*;

/** Render complete poses into a real FreeJ2ME LCD image and compare Android reference pixels. */
public final class FarmPosePixels {
    static Method method(Class<?> c,String name,Class<?> ret,Class<?>... parameters) throws Exception {
        for (Method m:c.getDeclaredMethods()) {
            if (m.getName().equals(name) && ret==m.getReturnType() && Arrays.equals(parameters,m.getParameterTypes())) {
                m.setAccessible(true);
                return m;
            }
        }
        throw new NoSuchMethodException(name);
    }

    public static void main(String[] args) throws Exception {
        Mobile.setPlatform(new MobilePlatform(480,800),() -> Mobile.updateSettings());
        Class<?> type=Class.forName("e");
        Constructor<?> make=type.getDeclaredConstructor();
        make.setAccessible(true);
        Method load=method(type,"a",void.class,byte[].class,int.class);
        Method pre=method(type,"a",void.class,int.class,int.class,int.class,int.class);
        Method set=method(type,"d",void.class,int.class);
        Method draw=method(type,"a",void.class,Graphics.class,int.class,int.class,int.class,int.class);
        Image image=Image.createImage(480,800);
        Graphics gr=image.getGraphics();
        int poses=0;
        try (DataInputStream in=new DataInputStream(new BufferedInputStream(new FileInputStream(args[0])))) {
            for(int slots=in.readInt(); slots>0; slots--) {
                int slot=in.readInt();
                Object sprite=make.newInstance();
                load.invoke(sprite,in.readNBytes(in.readInt()),0);
                boolean[] ready=new boolean[16];
                for(int n=in.readInt();n>0;n--) {
                    int frame=in.readUnsignedShort(), variant=in.readUnsignedByte();
                    int x=in.readUnsignedShort(),y=in.readUnsignedShort();
                    int w=in.readUnsignedShort(),h=in.readUnsignedShort();
                    byte[] expected=in.readNBytes(32);
                    if (!ready[variant]) {
                        pre.invoke(sprite,variant,0,-1,-1);
                        ready[variant]=true;
                    }
                    set.invoke(sprite,variant);
                    gr.setColor(0xf81fe9);
                    gr.fillRect(0,0,480,800);
                    draw.invoke(sprite,gr,frame,400,240,0);
                    int[] rgba=new int[w*h];
                    image.getRGB(rgba,0,w,x,y,w,h);
                    MessageDigest hash=MessageDigest.getInstance("SHA-256");
                    for (int c:rgba) {
                        hash.update((byte)(c>>16));
                        hash.update((byte)(c>>8));
                        hash.update((byte)c);
                    }
                    if (!Arrays.equals(hash.digest(),expected))
                        throw new AssertionError("Frame pixels/anchor differ: sheet "+slot+", frame "+frame+", variant "+variant);
                    poses++;
                }
            }
        }
        System.out.println("Verified "+poses+" complete on-screen farm and menu poses.");
    }
}
