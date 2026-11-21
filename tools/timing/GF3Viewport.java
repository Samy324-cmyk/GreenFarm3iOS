import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import javax.microedition.lcdui.game.Sprite;

/** Present the 480 by 800 touch edition on the physical LCD, including landscape LCDs. */
final class GF3Viewport {
    static final int WIDTH=480, HEIGHT=800;
    private static int deviceWidth,deviceHeight,left,top,width,height;
    private static boolean landscape;
    private static int captured;
    private static Image portrait, presented;
    private static int[] source,output,columns;

    private static int fit(int limit,int other,int sourceLimit,int sourceOther) {
        return Math.max(1,Math.min(limit,(int)((long)other*sourceLimit/sourceOther)));
    }

    private static void configure(int w,int h) {
        if(w==deviceWidth && h==deviceHeight) return;
        deviceWidth=w;deviceHeight=h;landscape=w>h;
        int sw=landscape?HEIGHT:WIDTH,sh=landscape?WIDTH:HEIGHT;
        width=fit(w,h,sw,sh);height=fit(h,w,sh,sw);
        left=(w-width)/2;top=(h-height)/2;
        if(width==sw && height==sh) {columns=null;output=null;return;}
        columns=new int[width];
        for(int x=0;x<width;x++) {
            int column=x*sw/width;
            columns[x]=landscape?column*WIDTH:column;
        }
        output=new int[width*height];
    }

    static Graphics begin(int w,int h) {
        configure(w,h);
        if(portrait==null) portrait=Image.createImage(WIDTH,HEIGHT);
        return portrait.getGraphics();
    }

    static void present(Graphics screen) {
        present(screen,null);
    }

    static void present(Graphics screen,Image nativePose) {
        Image frame=nativePose==null?portrait:nativePose;
        presented=frame;
        screen.setClip(0,0,deviceWidth,deviceHeight);
        screen.setColor(0);
        if(left>0) screen.fillRect(0,0,left,deviceHeight);
        if(top>0) screen.fillRect(0,0,deviceWidth,top);
        if(left+width<deviceWidth) screen.fillRect(left+width,0,deviceWidth-left-width,deviceHeight);
        if(top+height<deviceHeight) screen.fillRect(0,top+height,deviceWidth,deviceHeight-top-height);
        if(columns==null) {
            screen.drawRegion(frame,0,0,WIDTH,HEIGHT,landscape?Sprite.TRANS_ROT270:Sprite.TRANS_NONE,
                    left,top,Graphics.TOP|Graphics.LEFT);
            return;
        }
        if(source==null) source=new int[WIDTH*HEIGHT];
        frame.getRGB(source,0,WIDTH,0,0,WIDTH,HEIGHT);
        int sh=landscape?WIDTH:HEIGHT;
        boolean twoFifths=width*5==(landscape?HEIGHT:WIDTH)*2 && height*5==sh*2;
        int step=landscape?WIDTH:1;
        int last=-1;
        for(int y=0;y<height;y++) {
            int row=y*sh/height,dest=y*width;
            int offset=landscape?WIDTH-1-row:row*WIDTH;
            if(offset==last) System.arraycopy(output,dest-width,output,dest,width);
            else if(twoFifths) {
                // An inherited 240×320 LCD uses two samples per five source pixels.
                // Consume pairs directly so the VM needs no column lookup per pixel.
                int end=dest+width,index=offset;
                while(dest<end) {
                    output[dest++]=source[index];
                    output[dest++]=source[index+2*step];
                    index+=5*step;
                }
            } else for(int x=0;x<width;x++) output[dest+x]=source[offset+columns[x]];
            last=offset;
        }
        screen.drawRGB(output,0,width,left,top,width,height,false);
    }

    static void pointer(a canvas,int x,int y,int phase) {
        int w=canvas.getWidth(),h=canvas.getHeight();
        if(w<=0 || h<=0) return;
        if(w!=WIDTH || h!=HEIGHT) {
            // The display may rotate between a paint event and its next pointer event.
            // Read this event's geometry without changing the active paint buffers.
            boolean horizontal=w>h;
            int sw=horizontal?HEIGHT:WIDTH,sh=horizontal?WIDTH:HEIGHT;
            int dw=fit(w,h,sw,sh),dh=fit(h,w,sh,sw);
            int localX=x-(w-dw)/2,localY=y-(h-dh)/2;
            String contact;
            try {contact=System.getProperty("com.nokia.pointer.number");}
            catch(SecurityException unavailable){contact=null;}
            int mask="1".equals(contact)?2:1;
            if(phase==0) {
                captured&=~mask;
                if(localX>=0 && localX<dw && localY>=0 && localY<dh)captured|=mask;
            }
            if((captured&mask)==0) return;
            int u=localX*sw/dw,v=localY*sh/dh;
            x=horizontal?WIDTH-1-v:u;
            y=horizontal?u:v;
            if(phase==1) captured&=~mask;
        }
        if(phase==0) canvas.gf3PointerPressed(x,y);
        else if(phase==1) canvas.gf3PointerReleased(x,y);
        else canvas.gf3PointerDragged(x,y);
    }
}
