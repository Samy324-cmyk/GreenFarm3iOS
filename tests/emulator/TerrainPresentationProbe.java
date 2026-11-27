import java.util.Arrays;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Check all output pixels of a wrapped layer that crosses both buffer seams. */
public final class TerrainPresentationProbe {
    static final int W=41,H=37,TW=55,TH=49;
    static final int[] MAP=new int[1];
    static Image texture,screen,mark;
    static int color(int x,int y) {
        return 0xff000000 | ((17*x+3*y)&255)<<16 | ((5*x+13*y)&255)<<8 | ((x+3*y)&255);
    }
    static int mod(int n,int p) {return Math.floorMod(n,p);}
    static void nativeFrame(int worldX,int worldY) {
        int[] tile=new int[TW*TH];
        for(int y=worldY-5;y<worldY-5+TH;y++)
            for(int x=worldX-6;x<worldX-6+TW;x++)
                tile[mod(y,TH)*TW+mod(x,TW)]=color(x,y);
        texture.getGraphics().drawRGB(tile,0,TW,0,0,TW,TH,false);
        Graphics g=screen.getGraphics();
        GF3Draw.begin(g);
        for(int y=-mod(worldY,TH);y<H;y+=TH) {
            for(int x=-mod(worldX,TW);x<W;x+=TW) {
                int left=Math.max(x,0),top=Math.max(y,0);
                g.setClip(left,top,Math.min(W,x+TW)-left,Math.min(H,y+TH)-top);
                GF3Draw.drawImage(g,texture,x,y,Graphics.TOP|Graphics.LEFT);
            }
        }
        GF3Draw.rememberGround(0,-6,-5);
        GF3Draw.rememberCamera(MAP,worldX,worldY);
        if(!GF3Draw.hasGround()) throw new AssertionError("Native quadrants could not be reassembled");
        g.setClip(0,0,W,H);
        GF3Draw.drawImage(g,mark,2,3,Graphics.TOP|Graphics.LEFT);
        GF3Draw.stop();
        GF3Draw.match();
    }
    public static void main(String[] args) {
        Mobile.setPlatform(new MobilePlatform(W,H),()->Mobile.updateSettings());
        texture=Image.createImage(TW,TH);
        screen=Image.createImage(W,H);
        mark=Image.createRGBImage(new int[]{0xffff0033},1,1,true);
        Image target=Image.createImage(W,H);
        int[] actual=new int[W*H],expected=new int[W*H];
        int[][] moves={{54,48},{60,53},{53,47},{47,55},{57,46}};
        nativeFrame(moves[0][0],moves[0][1]);
        for(int i=1;i<moves.length;i++) {
            int x=moves[i][0],y=moves[i][1];
            nativeFrame(x,y);
            for(int remaining=0;remaining<=50;remaining++) {
                GF3Draw.replay(target.getGraphics(),remaining,50);
                int originX=x-(x-moves[i-1][0])*remaining/50;
                int originY=y-(y-moves[i-1][1])*remaining/50;
                for(int row=0;row<H;row++) for(int col=0;col<W;col++)
                    expected[row*W+col]=color(originX+col,originY+row);
                expected[3*W+2]=0xffff0033;
                target.getRGB(actual,0,W,0,0,W,H);
                if(!Arrays.equals(actual,expected))
                    throw new AssertionError("Terrain or fixed HUD differs at move "+i+" phase "+remaining);
            }
        }
        int[] last=moves[moves.length-1];
        // An instant jump by a whole cache circumference plus one pixel
        // must not be mistaken for continuous one-pixel panning.
        nativeFrame(last[0]+TW+1,last[1]+TH+1);
        if(GF3Draw.match()!=0) throw new AssertionError("Interpolated across a camera cut");
        System.out.println("TERRAIN_PIXELS_OK poses="+((moves.length-1)*51));
    }
}
