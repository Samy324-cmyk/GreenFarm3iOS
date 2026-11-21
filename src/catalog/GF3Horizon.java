/** Northern scenery from cGame.Kv and s1.H1/q1, in tile-cache coordinates. */
final class GF3Horizon {
    private static int lastX=-1,lastY=-1,lastZoom=-1;

    static f[] worldActors() {
        int x=k.cameraX(0),y=k.cameraY(0),zoom=a.B;
        boolean moved=x!=lastX || y!=lastY || zoom!=lastZoom;
        if(k.dirtyCount>0 || zoom!=lastZoom || moved && y<648*zoom/100)
            a.l=true;
        lastX=x;lastY=y;lastZoom=zoom;
        return f.actors;
    }

    static boolean draw() {
        int zoom=a.B;
        // MIDP stores the top left in zoomed pixels. Android's positions
        // and its 648-pixel horizon use unscaled world coordinates.
        int x=k.cameraX(0),y=k.cameraY(0);
        if (zoom<=0 || y>=648*zoom/100) return true;
        int worldX=x*100/zoom,worldY=y*100/zoom;
        boolean all=a.l;
        k.buffers[0][0].setColor(0x10b5f2);
        int sky=(int)(648-(648-worldY)*215.0f/648+0.5f);
        k.fill(0,0,k.e(),sky*zoom/100,all);
        // The distant sky actor has no horizontal scroll and always draws
        // its texture at native scale. All its repetitions coincide.
        drawSprite(79,x,y+(433-worldY)*zoom/100,all);
        if(zoom!=100) {g.o();g.n(zoom);}
        int mountains=(int)(648-(648-worldY)*40.0f/648+0.5f);
        int xShift=x-(worldX>>4)*zoom/100;
        // Include the extra tile margin around the viewport. Those pixels
        // will be exposed the next time the map advances by a partial tile.
        int worldWidth=k.e()*100/zoom;
        for(int wx=0;wx<worldWidth;wx+=240)
            drawSprite(78,xShift+wx*zoom/100,mountains*zoom/100,all);
        for(int wx=0;wx<worldWidth;wx+=400)
            drawSprite(77,wx*zoom/100,648*zoom/100,all);
        if(zoom!=100) g.p();
        return true;
    }

    private static void drawSprite(int slot,int x,int y,boolean all) {
        k.sprite(0,a.b[slot],0,x,y,all,null);
    }
}
