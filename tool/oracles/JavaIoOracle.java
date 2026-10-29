import java.io.*;
import java.util.Arrays;
import java.util.zip.*;

/** Standard JVM stream behavior, independent of the Dart implementation. */
public final class JavaIoOracle {
    public static void main(String[] args)throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        DataOutputStream out=new DataOutputStream(bytes);
        out.writeBoolean(true); out.writeBoolean(false);
        out.writeByte(255); out.writeShort(-12345); out.writeChar(0xd834);
        out.writeInt(0x89abcdef); out.writeLong(0x8123456789abcdefL);
        out.writeFloat(-0.0f); out.writeDouble(-0.0d);
        out.writeFloat(Float.intBitsToFloat(0xffa12345));
        out.writeDouble(Double.longBitsToDouble(0xfff123456789abcdL));
        out.writeUTF("A\u0000\u00e9\u6771\ud83d\ude00\ud800");
        out.flush();
        CRC32 crc=new CRC32();crc.update(bytes.toByteArray());
        ByteArrayInputStream in=new ByteArrayInputStream(new byte[]{10,20,30,40},1,2);
        int[] positions={in.read(),in.available(),0,0,0,0};
        in.reset();positions[2]=in.read();in.close();positions[3]=in.read();positions[4]=in.read(new byte[0]);positions[5]=in.available();
        ByteArrayOutputStream compressed=new ByteArrayOutputStream();
        try(GZIPOutputStream gzip=new GZIPOutputStream(compressed)){gzip.write("Granja original: ma\u00edz \ud83c\udf3d".getBytes("UTF-8"));}
        try(PrintWriter w=new PrintWriter(args[0],"UTF-8")){
            w.println("{\"generator\":\"JavaIoOracle.java\",\"data\":"+Arrays.toString(bytes.toByteArray())+",");
            w.println("\"crc32\":"+crc.getValue()+",\"byteInput\":"+Arrays.toString(positions)+",");
            w.println("\"gzip\":"+Arrays.toString(compressed.toByteArray())+"}");
        }
    }
}
