/** Farm camera input for standard MIDP and Nokia multipoint touch devices. */
final class GF3Zoom {
    private static boolean primary,secondary,pinch,multipoint;
    private static int x0,y0,x1,y1,spanX,spanY,startingZoom;
    private static volatile int requested;
    private static int centerX,centerY;
    private static boolean anchored;

    static void hide(int panel,int index,boolean ignored) {
        a.a(panel,index,false);
        a.b(panel,index,false);
    }
    static boolean onePointer() {return !multipoint;}
    static String choice() {
        return (requested==0?a.B:requested)==100?"Alejar":"Acercar";
    }
    static synchronized void toggle() {anchored=false;requested=(requested==0?a.B:requested)==100?50:100;}
    static void update() {
        applyZoom();
        f.a();
    }
    private static synchronized void applyZoom() {
        int zoom=requested;
        if(zoom!=0 && (a.screen()==17 || a.screen()==18)) {
            requested=0;
            f.e(zoom);
            if(anchored)GF3Fractional.center(zoom,centerX,centerY);
        }
    }
    static synchronized void pointer(a canvas,int x,int y,int phase) {
        String id;
        try {id=System.getProperty("com.nokia.pointer.number");}
        catch(SecurityException unavailable){id=null;}
        if(id!=null) {
            multipoint=true;
            if(!"0".equals(id) && !"1".equals(id))return;
            boolean second="1".equals(id);
            if(second) {secondary=phase!=1;x1=x;y1=y;}
            else {primary=phase!=1;x0=x;y0=y;}
            if(!pinch && primary && secondary && a.C==-1 && (a.screen()==17 || a.screen()==18)) {
                pinch=true;
                startingZoom=a.B;
                centerX=GF3Fractional.centerX();centerY=GF3Fractional.centerY();
                anchored=true;
                spanX=Math.abs(x1-x0);spanY=Math.abs(y1-y0);
                g.cancelZoomPress();
            }
            if(pinch) {
                if(primary && secondary) {
                    // s1.a1 scales both contact-axis deltas about one stable viewport center.
                    int percent=startingZoom+(Math.abs(x1-x0)-spanX)/10+(Math.abs(y1-y0)-spanY)/10;
                    requested=Math.max(50,Math.min(100,percent));
                }
                if(!primary && !secondary)pinch=false;
                return;
            }
            if(second)return;
        }
        if(phase==0)canvas.gf3ZoomPressed(x,y);
        else if(phase==1)canvas.gf3ZoomReleased(x,y);
        else canvas.gf3ZoomDragged(x,y);
    }
}
