import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** The original 50-ms updates run once. MIDP presentations subdivide their idle time. */
final class GF3Presentation {
    private static final int PERIOD=50;
    private static volatile g canvas;
    private static volatile boolean intermediate;
    private static long tickStart, nextDeadline;
    private static Image game;
    private static Image background;
    private static Graphics backgroundGraphics;
    private static int moving;
    private static volatile int nativeCost,betweenCost;
    public static int ticks, presentations, interpolated, matchedSprites;

    static synchronized void paint(g owner,Graphics screen) {
        canvas=owner;
        int width=owner.getWidth(),height=owner.getHeight();
        if(width<=0 || height<=0) return;
        int w=GF3Viewport.WIDTH,h=GF3Viewport.HEIGHT;
        Graphics lcd=screen;
        boolean fit=width!=w || height!=h;
        Image physicalSource=null;
        if(fit) screen=GF3Viewport.begin(width,height);
        if(g.o) {
            if(!intermediate) {owner.gf3OriginalPaint(screen);if(fit) GF3Viewport.present(lcd);}
            return;
        }
        if(game==null || w!=game.getWidth() || h!=game.getHeight()) {
            game=Image.createImage(w,h);
            background=Image.createImage(w,h);
            backgroundGraphics=background.getGraphics();
            moving=0;
        }
        long paintStart=System.currentTimeMillis();
        if(!intermediate) {
            long previousTick=tickStart;
            tickStart=System.currentTimeMillis();
            backgroundGraphics.drawImage(game,0,0,Graphics.TOP|Graphics.LEFT);
            Graphics original=game.getGraphics();
            GF3Draw.begin(original);
            try {owner.gf3OriginalPaint(original);}
            finally {GF3Draw.stop();}
            moving=g.M<0 && tickStart>=previousTick && tickStart-previousTick<2*PERIOD ? GF3Draw.match() : 0;
            ticks++;
            matchedSprites+=moving;
        }
        long elapsed=System.currentTimeMillis()-tickStart;
        screen.setClip(0,0,w,h);
        if(moving!=0 && GF3Draw.valid && elapsed>=0 && elapsed<PERIOD) {
            if(!GF3Draw.hasGround()) screen.drawImage(background,0,0,Graphics.TOP|Graphics.LEFT);
            GF3Draw.replay(screen,PERIOD-(int)elapsed,PERIOD);
            if(intermediate) interpolated++;
            screen.setClip(0,0,w,h);
        } else {
            moving=0;
            if(fit)physicalSource=game;
            else screen.drawImage(game,0,0,Graphics.TOP|Graphics.LEFT);
        }
        if(fit) GF3Viewport.present(lcd,physicalSource);
        int cost=(int)Math.max(0,Math.min(PERIOD,System.currentTimeMillis()-paintStart));
        if(intermediate) betweenCost=(betweenCost*3+cost+2)/4;
        else nativeCost=(nativeCost*3+cost+2)/4;
        presentations++;
    }
    static void waitForTick(long millis) throws InterruptedException {
        long now=System.currentTimeMillis(), end=now+millis;
        if(nextDeadline!=0) {
            long ideal=nextDeadline+PERIOD;
            // Recover timer rounding on a healthy device. Long stalls rebase immediately.
            if(ideal>now && Math.abs(ideal-end)<6) end=ideal;
        }
        nextDeadline=end;
        g owner=canvas;
        // Only fill actual idle time. A slow renderer never causes extra simulation updates.
        for(int step=1;owner!=null && step<=2;step++) {
            // A simulation frame takes longer to draw than an intermediate
            // frame. Align completed presentations, not just repaint calls.
            int compensation=Math.max(0,Math.min(7,nativeCost-betweenCost));
            long due=end-PERIOD+(step*1000+30)/60+compensation;
            long delay=due-System.currentTimeMillis();
            if(due>=end || delay< -4 || owner!=canvas || g.o) continue;
            if(delay>0) Thread.sleep(delay);
            if(System.currentTimeMillis()>=end) break;
            intermediate=true;
            try {owner.repaint();owner.serviceRepaints();}
            finally {intermediate=false;}
        }
        long left=end-System.currentTimeMillis();
        if(left>0 && left<=millis+6) Thread.sleep(left);
    }
}
