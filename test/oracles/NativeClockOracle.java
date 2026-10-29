import java.util.Random;

/** Independent JVM reference for the native int64->float32->divide sequence. */
public final class NativeClockOracle {
  public static void main(String[] args) {
    long[] edges={0,1,-1,999999,1000000,1000001,16777215,16777216,16777217,
      9007199791611905L,Long.MAX_VALUE,Long.MIN_VALUE};
    Random rng=new Random(0x4e41544956454cL);
    System.out.println("[");
    for(int i=0;i<edges.length+1000;i++) {
      long value=i<edges.length?edges[i]:rng.nextLong();
      int bits=Float.floatToRawIntBits((float)value/1000000.0f);
      System.out.print("{\"ticks\":\""+value+"\",\"float_bits\":"+bits+"}");
      System.out.println(i+1<edges.length+1000?",":"");
    }
    System.out.println("]");
  }
}
