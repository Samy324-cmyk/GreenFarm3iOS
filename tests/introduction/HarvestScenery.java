import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/** Read a captured LCD after the first real harvest. This program never loads the game. */
public final class HarvestScenery {
    private static int compare(BufferedImage lcd, File directory, String name, int x0, int y0,int tolerance) throws Exception {
        BufferedImage reference=ImageIO.read(new File(directory,name+".png"));
        int exact=0, close=0, different=0;
        for(int y=0;y<reference.getHeight();y++) for(int x=0;x<reference.getWidth();x++){
            int expected=reference.getRGB(x,y);
            // The 480x800 touch LCD stores the 800x480 farm rotated clockwise.
            int actual=lcd.getRGB(479-(y0+y),x0+x);
            int delta=0;
            for(int channel=0;channel<=16;channel+=8){
                delta=Math.max(delta,Math.abs(((actual>>channel)&255)-((expected>>channel)&255)));
            }
            if(delta==0)exact++;
            else if(delta<=tolerance)close++;
            else different++;
        }
        System.out.println("HARVEST_PIXELS "+name+" exact="+exact+" withinTolerance="+close+" different="+different);
        return different;
    }

    public static void main(String[] args) throws Exception {
        BufferedImage lcd=ImageIO.read(new File(args[0]));
        if(lcd.getWidth()!=480 || lcd.getHeight()!=800)throw new AssertionError("Expected a 480x800 touch LCD");
        File reference=new File(args[1]);
        int manor=compare(lcd,reference,"manor",685,0,1);
        int fence=compare(lcd,reference,"fence",291,418,1);
        if(manor>20 || fence>20)throw new AssertionError("First harvest differs from Android by more than one RGB value: "+
            manor+" manor pixels, "+fence+" fence pixels");
        BufferedImage hud=ImageIO.read(new File(args[2]));
        int hudDifferences=compare(hud,reference,"hud-coins",99,18,2)+
            compare(hud,reference,"hud-cash",101,61,2)+compare(hud,reference,"hud-xp",390,28,2)+
            compare(hud,reference,"hud-level",251,16,2);
        if(hudDifferences>5)throw new AssertionError("New-game HUD differs from the original Android font in "+
            hudDifferences+" pixels by more than two RGB values");
    }
}
