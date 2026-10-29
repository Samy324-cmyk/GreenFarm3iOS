import java.lang.reflect.*;
import java.util.*;

public class LeafVectors {
  static String json(Object value) {
    if (value == null) return "null";
    if (value instanceof Float) return "" + Float.floatToRawIntBits((Float)value);
    if (value instanceof Boolean) return (Boolean)value ? "1" : "0";
    if (value.getClass().isArray()) {
      StringJoiner parts = new StringJoiner(",", "[", "]");
      for (int i=0;i<Array.getLength(value);i++) parts.add(json(Array.get(value,i)));
      return parts.toString();
    }
    return value.toString();
  }
  static String type(Class<?> type) {
    if (type.isArray()) return type.getName().replace('.', '/');
    if (type == int.class) return "I";
    if (type == long.class) return "J";
    if (type == float.class) return "F";
    if (type == short.class) return "S";
    if (type == boolean.class) return "Z";
    if (type == void.class) return "V";
    throw new IllegalArgumentException(type.toString());
  }
  public static void main(String[] ignored) throws Exception {
    Random random = new Random(91618273L);
    StringJoiner result = new StringJoiner(",\n", "[\n", "\n]");
    Method[] methods = DexLeafOracle.class.getDeclaredMethods();
    Arrays.sort(methods, Comparator.comparing(Method::getName));
    for (int sample=0;sample<160;sample++) {
      int n = (1+random.nextInt(8))*4;
      byte[] bytes = new byte[n+8];random.nextBytes(bytes);
      int[] ints = new int[n];for (int i=0;i<n;i++) ints[i]=random.nextInt();
      boolean flag = (sample&1)!=0;
      for (Method method : methods) {
        Object[] args = switch (method.getName()) {
          case "C2" -> new Object[]{random.nextInt(), bytes.clone(), 2};
          case "H4" -> new Object[]{random.nextInt()};
          case "H7" -> new Object[]{ints.clone(), flag, sample%3==0?new byte[n*4]:null};
          case "I3" -> new Object[]{(float)(sample%5), (float)(sample%9), (float)-sample, (float)sample, -3.1415927f, 17.75f};
          case "I7" -> new Object[]{bytes.clone(), flag, sample%3==0?new int[(bytes.length+3)/4+(flag?1:0)]:null};
          case "U2" -> new Object[]{ints.clone(), n*4};
          case "f3" -> new Object[]{random.nextInt(0x40000001)};
          case "o0" -> new Object[]{ints.clone(), 0, n, -1000000000, 1000000000};
          case "o3", "p3", "q3" -> new Object[]{bytes.clone(), sample%4};
          case "r0" -> new Object[]{ints.clone(), sample%n};
          case "t0" -> new Object[]{random.nextInt(), new int[]{0,1,2,3,18,99}[sample%6]};
          case "u3" -> new Object[]{bytes.clone(), sample%4, random.nextInt()};
          case "v3" -> new Object[]{bytes.clone(), sample%4, random.nextLong()};
          case "w3" -> new Object[]{bytes.clone(), sample%4, (short)random.nextInt()};
          default -> throw new IllegalStateException(method.toString());
        };
        if (method.getName().equals("H7") && flag) ((int[])args[0])[n-1] = sample%4==0?n*4+1:sample%(n*4);
        String before=json(args);
        Object output=method.invoke(null,args);
        StringJoiner parameters=new StringJoiner(",", "[", "]");
        String signature="(";
        for (Class<?> p : method.getParameterTypes()) { parameters.add("\""+type(p)+"\"");signature+=type(p); }
        signature+=")"+type(method.getReturnType());
        result.add("{\"method\":\""+method.getName()+signature+"\",\"parameters\":"+parameters+",\"args\":"+before+",\"result\":"+json(output)+",\"after\":"+json(args)+"}");
      }
    }
    System.out.print(result);
  }
}
