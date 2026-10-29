import java.util.*;
/** Reference fixtures are generated with Java 8, matching the APK's Java APIs. */
public class JavaCoreOracle {
  public static void main(String[] args) {
    Random r=new Random(975421L);
    System.out.print("{\"float\":[");
    int[] special={0,0x80000000,1,2,0x007fffff,0x00800000,0x3dcccccd,0x3f800000,0x7f7fffff,0x7f800000,0xff800000,0x7fc00001};
    for(int i=0;i<10012;i++){int bits=i<special.length?special[i]:r.nextInt();if(i>0)System.out.print(',');System.out.print("[\""+Integer.toHexString(bits)+"\",\""+Float.toString(Float.intBitsToFloat(bits))+"\"]");}
    System.out.print("],\"double\":[");
    long[] specialD={0,Long.MIN_VALUE,1,2,0x000fffffffffffffL,0x0010000000000000L,0x3fb999999999999aL,0x3ff0000000000000L,0x7fefffffffffffffL,0x7ff0000000000000L,0xfff0000000000000L,0x7ff8000000000001L};
    for(int i=0;i<10012;i++){long bits=i<specialD.length?specialD[i]:r.nextLong();if(i>0)System.out.print(',');System.out.print("[\""+Long.toHexString(bits)+"\",\""+Double.toString(Double.longBitsToDouble(bits))+"\"]");}
    System.out.print("]}");
  }
}
