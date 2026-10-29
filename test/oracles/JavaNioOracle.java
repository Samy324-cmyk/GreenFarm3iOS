import java.nio.*;
/** State and byte-storage differential traces, independent JVM reference. */
public class JavaNioOracle {
 public static void main(String[]args){
  java.util.Random random=new java.util.Random(8123491L);
  System.out.print('[');
  for(int trial=0;trial<80;trial++){
   ByteBuffer bytes=trial%2==0?ByteBuffer.allocate(32):ByteBuffer.allocateDirect(32);
   ByteOrder order=trial%3==0?ByteOrder.BIG_ENDIAN:ByteOrder.LITTLE_ENDIAN;
   bytes.order(order);bytes.position(trial%4);
   int offset=bytes.position();IntBuffer ints=bytes.asIntBuffer();
   if(trial>0)System.out.print(',');System.out.print("{\"offset\":"+offset+",\"little\":"+(order==ByteOrder.LITTLE_ENDIAN)+",\"direct\":"+bytes.isDirect()+",\"values\":[");
   for(int j=0;j<ints.capacity();j++){int v=random.nextInt();if(j>0)System.out.print(',');System.out.print(v);ints.put(j,v);}
   System.out.print("],\"bytes\":[");for(int i=0;i<bytes.limit();i++){if(i>0)System.out.print(',');System.out.print(bytes.get(i)&255);}System.out.print(']');
   ShortBuffer shorts=bytes.asShortBuffer();System.out.print(",\"shorts\":[");for(int j=0;j<shorts.capacity();j++){if(j>0)System.out.print(',');System.out.print(shorts.get(j));}System.out.print(']');
   FloatBuffer floats=bytes.asFloatBuffer();System.out.print(",\"floats\":[");for(int j=0;j<floats.capacity();j++){if(j>0)System.out.print(',');System.out.print(Float.floatToRawIntBits(floats.get(j)));}System.out.print("]}");
  }
  System.out.print(']');
 }
}
