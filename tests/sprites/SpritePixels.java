import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.Arrays;

/** Run the actual MIDP sprite decoder on each added module and palette. */
public final class SpritePixels {
    public static void main(String[] args) throws Exception {
        Class<?> sprite = Class.forName("e");
        Constructor<?> constructor = sprite.getDeclaredConstructor();
        constructor.setAccessible(true);
        Method load = sprite.getDeclaredMethod("a",byte[].class,int.class);
        load.setAccessible(true);
        Method decode = null;
        Field palette = null;
        for (Method m : sprite.getDeclaredMethods()) {
            if (m.getName().equals("a") && m.getReturnType() == int[].class &&
                    Arrays.equals(m.getParameterTypes(), new Class<?>[]{int.class})) decode = m;
        }
        for (Field f : sprite.getDeclaredFields()) {
            if (f.getName().equals("h") && f.getType() == int.class) palette = f;
        }
        decode.setAccessible(true);
        palette.setAccessible(true);
        int modules = 0;
        long pixels = 0;
        try (DataInputStream input = new DataInputStream(new BufferedInputStream(new FileInputStream(args[0])))) {
            for (int assets = input.readInt(); assets > 0; assets--) {
                String label = input.readUTF();
                byte[] blob = input.readNBytes(input.readInt());
                Object obj = constructor.newInstance();
                load.invoke(obj, blob, 0);
                for (int count = input.readInt(); count > 0; count--) {
                    int index = input.readUnsignedShort(), variant = input.readUnsignedByte();
                    int length = input.readInt();
                    byte[] expected = input.readNBytes(32);
                    palette.setInt(obj, variant);
                    int[] colors = (int[])decode.invoke(obj,index);
                    MessageDigest hash = MessageDigest.getInstance("SHA-256");
                    if (colors == null || colors.length < length)
                        throw new AssertionError(label + " module " + index + " failed to decode");
                    for (int i = 0; i < length; i++) {
                        int c = colors[i];
                        hash.update((byte)(c >>> 24));
                        hash.update((byte)(c >>> 16));
                        hash.update((byte)(c >>> 8));
                        hash.update((byte)c);
                    }
                    if (!Arrays.equals(hash.digest(), expected))
                        throw new AssertionError(label + " module " + index + " palette " + variant);
                    modules++;
                    pixels += length;
                }
            }
            if (input.read() != -1) throw new AssertionError("Unexpected oracle trailer");
        }
        System.out.printf("Verified %d module/palette pairs, %d ARGB pixels.%n", modules, pixels);
    }
}
