import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.security.interfaces.RSAPrivateCrtKey;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;

/** Independent JDK vectors; RSA key material is generated exclusively for tests. */
public final class JavaSecurityOracle {
  static final ArrayList<String> rows = new ArrayList<>();
  static String hex(byte[] bytes) { return HexFormat.of().formatHex(bytes); }
  static String q(String value) { return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""; }
  static void row(String... pairs) {
    StringBuilder result = new StringBuilder("{");
    for (int n=0;n<pairs.length;n+=2) {
      if(n>0) result.append(',');
      result.append(q(pairs[n])).append(':').append(q(pairs[n+1]));
    }
    rows.add(result.append('}').toString());
  }
  static byte[] data(int length) { byte[] value=new byte[length];for(int n=0;n<length;n++)value[n]=(byte)(n*31+7);return value; }
  static void block(String algorithm, byte[] key, byte[] iv, byte[] input) throws Exception {
    Cipher cipher=Cipher.getInstance(algorithm);
    SecretKeySpec secret=new SecretKeySpec(key,algorithm.startsWith("AES")?"AES":"DES");
    if(iv==null)cipher.init(Cipher.ENCRYPT_MODE,secret);else cipher.init(Cipher.ENCRYPT_MODE,secret,new IvParameterSpec(iv));
    byte[] encoded=cipher.doFinal(input);
    row("kind","block","algorithm",algorithm,"key",hex(key),"iv",iv==null?"":hex(iv),"input",hex(input),"encrypted",hex(encoded));
  }
  public static void main(String[] args) throws Exception {
    for(String name:new String[]{"MD5","SHA","SHA1","SHA-1","SHA-256"}) {
      for(int size:new int[]{0,1,17,257}) {
        byte[] input=data(size);
        row("kind","digest","algorithm",name,"input",hex(input),"digest",hex(MessageDigest.getInstance(name).digest(input)));
      }
    }
    for(int keySize:new int[]{16,24,32}) {
      for(int size:new int[]{0,1,15,16,17,32}) {
        block("AES",data(keySize),null,data(size));
        block("AES/CBC/PKCS5Padding",data(keySize),data(16),data(size));
      }
      for(int size:new int[]{0,16,32})block("AES/ECB/NoPadding",data(keySize),null,data(size));
    }
    for(int size:new int[]{0,8,16,32})block("DES/ECB/NoPadding",data(8),null,data(size));
    SecretKey des=SecretKeyFactory.getInstance("DES").generateSecret(new DESKeySpec(data(16)));
    row("kind","des_key","input",hex(data(16)),"encoded",hex(des.getEncoded()));
    KeyPairGenerator rsa=KeyPairGenerator.getInstance("RSA");rsa.initialize(2048);KeyPair pair=rsa.generateKeyPair();
    byte[] message="Original CRM public-key decryption fixture".getBytes(StandardCharsets.UTF_8);
    Cipher signature=Cipher.getInstance("RSA/ECB/PKCS1Padding");signature.init(Cipher.ENCRYPT_MODE,pair.getPrivate());
    RSAPrivateCrtKey privateKey=(RSAPrivateCrtKey)pair.getPrivate();
    row("kind","rsa","test_only","true","public_x509",hex(pair.getPublic().getEncoded()),"input",hex(message),"encrypted_private",hex(signature.doFinal(message)),"modulus",privateKey.getModulus().toString(16),"private_exponent",privateKey.getPrivateExponent().toString(16));
    byte[] digest=MessageDigest.getInstance("SHA-256").digest("19GmLfT99".getBytes(StandardCharsets.UTF_8));
    byte[] key=hex(digest).substring(0,16).getBytes(StandardCharsets.UTF_8);
    Cipher aes=Cipher.getInstance("AES");aes.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"));
    byte[] plaintext=aes.doFinal(Base64.getDecoder().decode(Files.readAllBytes(Paths.get(args[0]))));
    row("kind","original_properties","key",hex(key),"plaintext_sha256",hex(MessageDigest.getInstance("SHA-256").digest(plaintext)),"plaintext_length",Integer.toString(plaintext.length));
    Files.writeString(Paths.get(args[1]),"[\n"+String.join(",\n",rows)+"\n]\n",StandardCharsets.UTF_8);
    System.out.println("Wrote "+rows.size()+" independent JDK security vectors");
  }
}
