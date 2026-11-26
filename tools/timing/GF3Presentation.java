import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** The original 50-ms updates run once. MIDP presentations subdivide their idle time. */
final class GF3Presentation {
    private static final int PERIOD=50;
    private static volatile g canvas;
    private static volatile boolean nativePending;
    private static int lastRemaining;
    private static long tickStart, nextDeadline;
    private static Image game;
    private static volatile int moving;
    private static long lastNative;
    private static Graphics gameGraphics;
    private static Image composed;
    private static Graphics composedGraphics;
    private static int screenId=-1;
    private static volatile int nativeCost,betweenCost;
    public static int ticks, presentations, interpolated, matchedSprites;

    static void requestNative(g owner) {
        nativePending=true;
        owner.repaint();
    }

    static synchronized void paint(g owner,Graphics screen) {
        boolean intermediate=!nativePending;
        if(!intermediate)nativePending=false;
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
            gameGraphics=game.getGraphics();
            composed=Image.createImage(w,h);
            composedGraphics=composed.getGraphics();
            moving=0;
        }
        long paintStart=System.currentTimeMillis();
        // serviceRepaints may return before the asynchronous LCD paint.
        // Do not let extra repaint callbacks advance the original simulation.
        if(!intermediate) {
            lastNative=paintStart;
            long previousTick=tickStart;
            tickStart=System.currentTimeMillis();
            Graphics original=gameGraphics;
            original.setClip(0,0,w,h);
            // Do not record or snapshot the market, mansion or other menus.
            // Their native composition is already complete and must not be
            // paired with any preceding farm pose.
            if(screenId==17) {
                GF3Draw.begin(original);
                try {owner.gf3OriginalPaint(original);}
                finally {GF3Draw.stop();}
            }else{
                GF3Draw.invalidate();
                owner.gf3OriginalPaint(original);
            }
            lastRemaining=PERIOD;
            int nextScreen=a.a();
            moving=g.M<0 && screenId==17 && nextScreen==17 && tickStart>=previousTick && tickStart-previousTick<2*PERIOD ? GF3Draw.match() : 0;
            screenId=nextScreen;
            ticks++;
            matchedSprites+=moving;
        }
        long elapsed=System.currentTimeMillis()-tickStart;
        screen.setClip(0,0,w,h);
        int remaining=Math.min(lastRemaining,Math.max(0,PERIOD-(int)elapsed));
        if(moving!=0 && GF3Draw.valid && elapsed>=0 && remaining>0 && GF3Draw.canReplay(remaining,PERIOD)) {
            lastRemaining=remaining;
            // Never replay primitives onto the device LCD. Manic may expose
            // a partially painted canvas during native calls. Compose offscreen
            // and submit exactly one complete image, even when clipping changes.
            composedGraphics.setClip(0,0,w,h);
            GF3Draw.replay(composedGraphics,remaining,PERIOD);
            if(intermediate) interpolated++;
            if(fit) physicalSource=composed;
            else screen.drawImage(composed,0,0,Graphics.TOP|Graphics.LEFT);
        } else {
            moving=0;lastRemaining=0;
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
            // Native repaint requests are marked at the game-loop entry.
            // An asynchronous/coalesced paint cannot advance logic twice.
            owner.repaint();owner.serviceRepaints();
        }
        long left=end-System.currentTimeMillis();
        if(left>0 && left<=millis+6) Thread.sleep(left);
    }
}
