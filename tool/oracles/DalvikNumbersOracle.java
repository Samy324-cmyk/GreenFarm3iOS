import java.io.PrintWriter;
import java.util.Random;

/** Independent JVM oracle: every result is computed by Java operators/casts.
 * Regenerate: javac -d BUILD tool/oracles/DalvikNumbersOracle.java
 * java -cp BUILD DalvikNumbersOracle test/dalvik/fixtures/numbers_oracle.json
 */
public final class DalvikNumbersOracle {
    static long[] unary(int op, long a) {
        int i=(int)a; float f=Float.intBitsToFloat(i); double d=Double.longBitsToDouble(a);
        switch(op) {
            case 0x7b:return out('i',-i); case 0x7c:return out('i',~i);
            case 0x7d:return out('j',-a); case 0x7e:return out('j',~a);
            case 0x7f:return out('f',Float.floatToRawIntBits(-f));
            case 0x80:return out('d',Double.doubleToRawLongBits(-d));
            case 0x81:return out('j',(long)i);
            case 0x82:return out('f',Float.floatToRawIntBits((float)i));
            case 0x83:return out('d',Double.doubleToRawLongBits((double)i));
            case 0x84:return out('i',(int)a);
            case 0x85:return out('f',Float.floatToRawIntBits((float)a));
            case 0x86:return out('d',Double.doubleToRawLongBits((double)a));
            case 0x87:return out('i',(int)f); case 0x88:return out('j',(long)f);
            case 0x89:return out('d',Double.doubleToRawLongBits((double)f));
            case 0x8a:return out('i',(int)d); case 0x8b:return out('j',(long)d);
            case 0x8c:return out('f',Float.floatToRawIntBits((float)d));
            case 0x8d:return out('i',(byte)i); case 0x8e:return out('i',(char)i);
            case 0x8f:return out('i',(short)i);
            default:throw new IllegalArgumentException();
        }
    }
    static long[] binary(int op,long a,long b) {
        int i=(int)a,j=(int)b;
        float f=Float.intBitsToFloat(i),g=Float.intBitsToFloat(j);
        double d=Double.longBitsToDouble(a),e=Double.longBitsToDouble(b);
        switch(op) {
            case 0x90:return out('i',i+j); case 0x91:return out('i',i-j);
            case 0x92:return out('i',i*j); case 0x93:return out('i',i/j);
            case 0x94:return out('i',i%j); case 0x95:return out('i',i&j);
            case 0x96:return out('i',i|j); case 0x97:return out('i',i^j);
            case 0x98:return out('i',i<<j); case 0x99:return out('i',i>>j);
            case 0x9a:return out('i',i>>>j);
            case 0x9b:return out('j',a+b); case 0x9c:return out('j',a-b);
            case 0x9d:return out('j',a*b); case 0x9e:return out('j',a/b);
            case 0x9f:return out('j',a%b); case 0xa0:return out('j',a&b);
            case 0xa1:return out('j',a|b); case 0xa2:return out('j',a^b);
            case 0xa3:return out('j',a<<j); case 0xa4:return out('j',a>>j);
            case 0xa5:return out('j',a>>>j);
            case 0xa6:return out('f',Float.floatToRawIntBits(f+g));
            case 0xa7:return out('f',Float.floatToRawIntBits(f-g));
            case 0xa8:return out('f',Float.floatToRawIntBits(f*g));
            case 0xa9:return out('f',Float.floatToRawIntBits(f/g));
            case 0xaa:return out('f',Float.floatToRawIntBits(f%g));
            case 0xab:return out('d',Double.doubleToRawLongBits(d+e));
            case 0xac:return out('d',Double.doubleToRawLongBits(d-e));
            case 0xad:return out('d',Double.doubleToRawLongBits(d*e));
            case 0xae:return out('d',Double.doubleToRawLongBits(d/e));
            case 0xaf:return out('d',Double.doubleToRawLongBits(d%e));
            default:throw new IllegalArgumentException();
        }
    }
    static long[] compare(int op,long a,long b) {
        if(op==0x31)return out('i',Long.compare(a,b));
        double x=op<=0x2e?Float.intBitsToFloat((int)a):Double.longBitsToDouble(a);
        double y=op<=0x2e?Float.intBitsToFloat((int)b):Double.longBitsToDouble(b);
        return out('i',Double.isNaN(x)||Double.isNaN(y)?(op==0x2d||op==0x2f?-1:1):x==y?0:x<y?-1:1);
    }
    static long[] out(char type,long bits){return new long[]{type,bits};}
    static boolean first=true;
    static void vector(PrintWriter w,char kind,int op,long a,long b) {
        if(!first)w.println(','); first=false;
        w.print("[\""+kind+"\","+op+","+(int)a+","+(int)(a>>>32)+","+(int)b+","+(int)(b>>>32)+",");
        try {
            long[] result=kind=='u'?unary(op,a):kind=='b'?binary(op,a,b):compare(op,a,b);
            char type=(char)result[0]; long bits=result[1];
            boolean nan=type=='f'?Float.isNaN(Float.intBitsToFloat((int)bits)):type=='d'&&Double.isNaN(Double.longBitsToDouble(bits));
            w.print("\""+type+"\","+(int)bits+","+(int)(bits>>>32)+","+nan+"]");
        } catch(ArithmeticException exception) { w.print("\"exception\",0,0,false]"); }
    }
    public static void main(String[] args)throws Exception {
        long[] cases={0,1,-1,2,-2,31,32,63,64,Long.MIN_VALUE,Long.MAX_VALUE,Integer.MIN_VALUE,Integer.MAX_VALUE,
          0x3f800000L,0xbf800000L,0x7fc00000L,0x7f800000L,0xff800000L,0x80000000L,0x007fffffL,0x00800000L,0x7f7fffffL,
          0x3ff0000000000000L,0xbff0000000000000L,0x7ff8000000000000L,0x7ff0000000000000L,0xfff0000000000000L,
          0x000fffffffffffffL,0x0010000000000000L,0x7fefffffffffffffL,0x4000004000000001L,0x4000004000000000L,0x4000003fffffffffL};
        Random random=new Random(0x47524633);
        try(PrintWriter w=new PrintWriter(args[0],"UTF-8")) {
            w.println("{\"generator\":\"DalvikNumbersOracle.java\",\"java\":\""+System.getProperty("java.version")+"\",\"vectors\":[");
            for(int op=0x7b;op<=0x8f;op++) {
                for(long a:cases)vector(w,'u',op,a,0);
                for(int n=0;n<64;n++)vector(w,'u',op,random.nextLong(),0);
            }
            for(int op=0x90;op<=0xaf;op++) {
                for(long a:cases)for(long b:cases)vector(w,'b',op,a,b);
                for(int n=0;n<64;n++)vector(w,'b',op,random.nextLong(),random.nextLong());
            }
            for(int op=0x2d;op<=0x31;op++)for(long a:cases)for(long b:cases)vector(w,'c',op,a,b);
            w.println("]}");
        }
    }
}
