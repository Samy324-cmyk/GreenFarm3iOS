import java.util.Locale;
/** Exports Unicode property data, not Java implementation source. */
public class JavaUnicodeOracle {
 public static void main(String[]args){
  System.out.println("// Unicode case/digit facts exported from Java 8 by JavaUnicodeOracle.\n// Rebuild with the documented Java 8 oracle command.\nconst javaUnicode = <int, List<Object>>{");
  for(int cp=0;cp<=0x10ffff;cp++){
   String s=new String(Character.toChars(cp)),lo=s.toLowerCase(Locale.ROOT),up=s.toUpperCase(Locale.ROOT);
   int digit=Character.digit(cp,36),lower=Character.toLowerCase(cp),upper=Character.toUpperCase(cp);
   if(!s.equals(lo)||!s.equals(up)||digit>=0){
    System.out.print(cp+": [");units(lo);System.out.print(',');units(up);System.out.println(","+lower+","+upper+","+digit+"],");
   }
  }
  System.out.println("};");
 }
 static void units(String s){System.out.print("<int>[");for(int i=0;i<s.length();i++){if(i>0)System.out.print(',');System.out.print((int)s.charAt(i));}System.out.print(']');}
}
