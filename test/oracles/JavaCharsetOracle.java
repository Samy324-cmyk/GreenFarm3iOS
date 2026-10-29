import java.util.*;
public class JavaCharsetOracle {
 public static void main(String[]args)throws Exception{
  String[]texts={"","Aé😀","a\uD800z\uDC00","\uFEFF","\uD800\uD800\uDC00","\uDC00\uD800"};
  String[]charsets={"UTF-8","UTF-16","UTF-16BE","UTF-16LE","US-ASCII","ISO-8859-1"};
  System.out.print("{\"encode\":[");boolean first=true;
  for(String s:texts)for(String c:charsets){if(!first)System.out.print(',');first=false;System.out.print("[");units(s);System.out.print(",\""+c+"\",");bytes(s.getBytes(c));System.out.print(']');}
  int[][]values={{0xed,0xa0,0x80},{0xe1,0x80,0x41},{0xf0,0x90,0x80},{0xf0,0x90,0x80,0x41},{0xc0,0x80},{0xe0,0x80,0x80},{0xf4,0x90,0x80,0x80},{0x80,0xbf},{0xd8,0,0,65},{0xd8,0,0xd8,0,0xdc,0},{0xfe,0xff,0,65},{0xff,0xfe,65,0},{0,65,0},{255}};
  System.out.print("],\"decode\":[");first=true;
  for(int[] v:values)for(String c:charsets){byte[] b=new byte[v.length];for(int i=0;i<v.length;i++)b[i]=(byte)v[i];if(!first)System.out.print(',');first=false;System.out.print("[");bytes(b);System.out.print(",\""+c+"\",");units(new String(b,c));System.out.print(']');}
  System.out.print("]}");
 }
 static void bytes(byte[] b){System.out.print('[');for(int i=0;i<b.length;i++){if(i>0)System.out.print(',');System.out.print(b[i]&255);}System.out.print(']');}
 static void units(String s){System.out.print('[');for(int i=0;i<s.length();i++){if(i>0)System.out.print(',');System.out.print((int)s.charAt(i));}System.out.print(']');}
}
