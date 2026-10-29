import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;

/** Independent primitive reflection conversion vectors, including double-rounding boundaries. */
public class JavaReflectionOracle {
  public static boolean asZ(boolean n){return n;}
  public static byte asB(byte n){return n;}
  public static char asC(char n){return n;}
  public static short asS(short n){return n;}
  public static int asI(int n){return n;}
  public static long asJ(long n){return n;}
  public static float asF(float n){return n;}
  public static double asD(double n){return n;}
  static String raw(Object value) {
    if(value instanceof Boolean)return ((Boolean)value)?"1":"0";
    if(value instanceof Character)return Integer.toString((Character)value);
    if(value instanceof Float)return Integer.toString(Float.floatToRawIntBits((Float)value));
    if(value instanceof Double)return Long.toString(Double.doubleToRawLongBits((Double)value));
    return Long.toString(((Number)value).longValue());
  }
  public static void main(String[] args)throws Exception {
    Object[] values={false,true,(byte)-128,(byte)127,(short)-32768,(short)32767,(char)65535,Integer.MIN_VALUE,Integer.MAX_VALUE,Long.MIN_VALUE,Long.MAX_VALUE,(1L<<62)+(1L<<38)+1,-((1L<<62)+(1L<<38)+1),Float.intBitsToFloat(0x80000000),Float.intBitsToFloat(0x3f800001),Float.POSITIVE_INFINITY,Double.longBitsToDouble(0x8000000000000000L),1.25d};
    Map<Class<?>,String> types=Map.of(Boolean.class,"Z",Byte.class,"B",Character.class,"C",Short.class,"S",Integer.class,"I",Long.class,"J",Float.class,"F",Double.class,"D");
    Class<?>[] primitives={boolean.class,byte.class,char.class,short.class,int.class,long.class,float.class,double.class};
    String[] names={"Z","B","C","S","I","J","F","D"};
    ArrayList<String> rows=new ArrayList<>();
    for(Object input:values)for(int n=0;n<names.length;n++){
      Method method=JavaReflectionOracle.class.getDeclaredMethod("as"+names[n],primitives[n]);
      String result,error="";
      try{result=raw(method.invoke(null,input));}catch(IllegalArgumentException e){result="";error=e.getClass().getName();}
      rows.add("{\"source\":\""+types.get(input.getClass())+"\",\"target\":\""+names[n]+"\",\"input\":\""+raw(input)+"\",\"output\":\""+result+"\",\"error\":\""+error+"\"}");
    }
    Files.writeString(Paths.get(args[0]),"[\n"+String.join(",\n",rows)+"\n]\n");
    System.out.println("Wrote "+rows.size()+" reflection vectors");
  }
}
