import java.io.IOException;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import javax.microedition.lcdui.game.Sprite;

/** Draw the localized loading captions with the original Android bitmap font. */
final class GF3Loading {
    private static Image progress,copyright;
    private static Image read(String name) {
        try {return Image.createImage(name);}
        catch(IOException failure){throw new IllegalStateException(name);}
    }
    private static void text(Image picture,short[] rect,int advance) {
        if(rect[15]!=1)return;
        // The original font centers its advance, then draws from its glyph
        // origin. The cap ascent is 22 and its baseline is 16 below center.
        int left=rect[2]+(rect[5]>>1)-(advance>>1);
        int top=rect[3]+(rect[6]>>1)+16-22;
        int w=picture.getWidth(),h=picture.getHeight();
        g.screen.drawRegion(picture,0,0,w,h,Sprite.TRANS_ROT90,480-top-h,left,Graphics.TOP|Graphics.LEFT);
    }
    static void draw(int panel) {
        if(progress==null)progress=read("/cargando.png");
        if(copyright==null)copyright=read("/copyright.png");
        String[] captions=a.captions[panel];
        String loading=captions[4];
        boolean translated="Cargando".equals(loading);
        if(translated)captions[4]=null;
        try {a.F(panel);}
        finally {if(translated)captions[4]=loading;}
        if(translated)text(progress,a.controls[panel][4],129);
        text(copyright,a.controls[panel][6],216);
    }
}
