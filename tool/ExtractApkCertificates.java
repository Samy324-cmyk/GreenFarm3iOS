import java.nio.file.*;
import java.security.cert.*;
import java.util.zip.*;
/** Extracts public signing certificates; never executes APK classes. */
public class ExtractApkCertificates {
  public static void main(String[] args) throws Exception {
    try (ZipFile zip=new ZipFile(args[0])) {
      java.util.Collection<? extends Certificate> certs=CertificateFactory.getInstance("X.509").generateCertificates(zip.getInputStream(zip.getEntry("META-INF/CERT.RSA")));
      int index=0;
      for(Certificate cert:certs) {
        Path out=Paths.get(args[1],"apk_signer_"+(index++)+".der");
        Files.write(out,cert.getEncoded());
        System.out.println(out+" : "+((X509Certificate)cert).getSubjectX500Principal());
      }
    }
  }
}
