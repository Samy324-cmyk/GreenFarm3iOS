import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
/** Reproduces original c.c.a.b.e DefReader, without executing APK classes. */
public class DecodeMidletProperties {
 public static void main(String[] args)throws Exception{
  byte[] digest=MessageDigest.getInstance("SHA-256").digest("19GmLfT99".getBytes(StandardCharsets.UTF_8));
  StringBuilder hex=new StringBuilder();for(byte b:digest)hex.append(Integer.toString((b&255)+256,16).substring(1));
  SecretKeySpec key=new SecretKeySpec(hex.substring(0,16).getBytes(StandardCharsets.UTF_8),"AES");
  Cipher aes=Cipher.getInstance("AES/ECB/PKCS5Padding");aes.init(Cipher.DECRYPT_MODE,key);
  byte[] encrypted=Base64.getDecoder().decode(Files.readAllBytes(Paths.get(args[0])));
  Files.write(Paths.get(args[1]),aes.doFinal(encrypted));
 }
}
