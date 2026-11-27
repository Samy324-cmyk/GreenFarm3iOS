import java.io.DataInputStream;
import java.io.IOException;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Bitmap glyph passes for the Android farm's coin, cash, experience and level controls. */
final class GF3FarmHudText {
    private static final String CHARACTERS="0123456789 /,.-+";
    private static final int CELL=32;
    private static byte[] alpha;
    private static byte[] widths;
    private static final String[] values = new String[4];
    private static final int[] advances = new int[4];
    private static final Image[][] lines = new Image[4][2];

    private static void load() {
        if(alpha!=null)return;
        try {
            byte[] data=new byte[2*CHARACTERS.length()];
            DataInputStream in=new DataInputStream(new GF3FarmHudText().getClass().getResourceAsStream("/farm-font-widths"));
            try {in.readFully(data);} finally {in.close();}
            Image original=Image.createImage("/farm-font.png");
            int w=original.getWidth(), h=original.getHeight();
            int[] pixels=new int[w*h];
            original.getRGB(pixels,0,w,0,0,w,h);
            byte[] coverage=new byte[w*h];
            for(int i=0;i<pixels.length;i++)coverage[i]=(byte)(pixels[i]>>>24);
            widths=data;alpha=coverage;
        } catch(IOException e) {throw new IllegalStateException("farm-font");}
    }

    // Keep each native font pass separate. The outline under a neighboring
    // digit must still be painted before any white ink, including during scroll.
    private static boolean prepare(String text,int slot,boolean outlined) {
        if(text.equals(values[slot]))return true;
        int count=CHARACTERS.length(), offset=outlined?count:0, advance=0, last=0;
        for(int i=0;i<text.length();i++){
            int glyph=CHARACTERS.indexOf(text.charAt(i));
            if(glyph<0)return false;
            last=advance;
            advance+=widths[offset+glyph];
        }
        int height=last+CELL, stride=count*CELL;
        for(int pass=0;pass<(outlined?2:1);pass++){
            int row=outlined?1+pass:0, rgb=row==1?0x1979eb:0xffffff;
            int[] buffer=new int[CELL*height];
            int pen=0;
            for(int i=0;i<text.length();i++){
                int glyph=CHARACTERS.indexOf(text.charAt(i));
                if(text.charAt(i)!=' '){
                    int origin=row*CELL*stride+glyph*CELL;
                    for(int y=0;y<CELL;y++)for(int x=0;x<CELL;x++){
                        int a=alpha[origin+y*stride+x]&255;
                        if(a==0)continue;
                        int dst=(pen+x)*CELL+CELL-1-y;
                        int previous=buffer[dst]>>>24;
                        int combined=a+((255-a)*previous+127)/255;
                        buffer[dst]=(combined<<24)|rgb;
                    }
                }
                pen+=widths[offset+glyph];
            }
            lines[slot][pass]=Image.createRGBImage(buffer,CELL,height,true);
        }
        advances[slot]=advance;
        values[slot]=text;
        return true;
    }

    private static boolean draw(String text,int panel,int index,int dx,int dy) {
        if(panel!=1 || (index!=13 && index!=16 && index!=22 && index!=23))return false;
        short[] rect=a.controls[panel][index];
        if(rect[15]!=1 || text==null || text.length()==0)return true;
        load();
        boolean outlined=index!=22;
        int slot=index==13?0:index==16?1:index==22?2:3;
        if(!prepare(text,slot,outlined))return false;
        int advance=advances[slot];
        int left=dx+rect[2];
        if(rect[9]==1)left+=(rect[5]>>1)-(advance>>1);
        else if(rect[9]==2)left+=rect[5]-advance;
        // ASprite centers the line box, then applies its font-specific baseline.
        int baseline=dy+rect[3]+(rect[6]>>1)+(outlined?16:9);
        for(int pass=0;pass<(outlined?2:1);pass++)
            g.screen.drawImage(lines[slot][pass],480-(baseline-24)-CELL,left-4,Graphics.TOP|Graphics.LEFT);
        return true;
    }

    static void simple(String text,int panel,int index,int dx,int dy) {
        if(!draw(text,panel,index,dx,dy))a.originalLabel(text,panel,index,dx,dy);
    }

    static void scrolling(String text,int panel,int index,int dx,int dy) {
        if(!draw(text,panel,index,dx,dy))a.originalScrollingLabel(text,panel,index,dx,dy);
    }
}
