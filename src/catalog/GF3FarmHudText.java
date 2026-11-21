import java.io.DataInputStream;
import java.io.IOException;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import javax.microedition.lcdui.game.Sprite;

/** Bitmap glyph passes for the Android farm's coin, cash, experience and level controls. */
final class GF3FarmHudText {
    private static final String CHARACTERS="0123456789 /,.-+";
    private static final int CELL=32;
    private static Image atlas;
    private static byte[] widths;

    private static void load() {
        if(atlas!=null)return;
        try {
            byte[] data=new byte[2*CHARACTERS.length()];
            DataInputStream in=new DataInputStream(new GF3FarmHudText().getClass().getResourceAsStream("/farm-font-widths"));
            try {in.readFully(data);} finally {in.close();}
            Image original=Image.createImage("/farm-font.png");
            widths=data;atlas=original;
        } catch(IOException e) {throw new IllegalStateException("farm-font");}
    }

    private static boolean draw(String text,int panel,int index,int dx,int dy) {
        if(panel!=1 || (index!=13 && index!=16 && index!=22 && index!=23))return false;
        short[] rect=a.controls[panel][index];
        if(rect[15]!=1 || text==null || text.length()==0)return true;
        load();
        boolean outlined=index!=22;
        int count=CHARACTERS.length(),widthOffset=outlined?count:0,advance=0;
        for(int i=0;i<text.length();i++){
            int glyph=CHARACTERS.indexOf(text.charAt(i));
            if(glyph<0)return false;
            advance+=widths[widthOffset+glyph];
        }
        int left=dx+rect[2];
        if(rect[9]==1)left+=(rect[5]>>1)-(advance>>1);
        else if(rect[9]==2)left+=rect[5]-advance;
        // ASprite centers the line box, then applies its font-specific baseline.
        int baseline=dy+rect[3]+(rect[6]>>1)+(outlined?16:9);
        for(int layer=outlined?1:0;layer<=(outlined?2:0);layer++){
            int pen=left;
            for(int i=0;i<text.length();i++){
                int glyph=CHARACTERS.indexOf(text.charAt(i));
                if(text.charAt(i)!=' ')g.screen.drawRegion(atlas,glyph*CELL,layer*CELL,CELL,CELL,
                    Sprite.TRANS_ROT90,480-(baseline-24)-CELL,pen-4,Graphics.TOP|Graphics.LEFT);
                pen+=widths[widthOffset+glyph];
            }
        }
        return true;
    }

    static void simple(String text,int panel,int index,int dx,int dy) {
        if(!draw(text,panel,index,dx,dy))a.originalLabel(text,panel,index,dx,dy);
    }

    static void scrolling(String text,int panel,int index,int dx,int dy) {
        if(!draw(text,panel,index,dx,dy))a.originalScrollingLabel(text,panel,index,dx,dy);
    }
}
