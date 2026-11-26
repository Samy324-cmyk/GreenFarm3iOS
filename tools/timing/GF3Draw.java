import java.lang.ref.WeakReference;
import java.util.Hashtable;
import javax.microedition.lcdui.Font;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Record only operations directed to the actual game framebuffer. */
final class GF3Draw {
    static final int IMAGE=1, REGION=2, RGB=3, TEXT=4, FILL=5, RECT=6, ARC=7, FILLEDARC=8, LINE=9, TRIANGLE=10;
    private static final int MAX_COMMANDS=4096, MAX_SNAPSHOT_PIXELS=800*480*2;
    private static Frame previous=new Frame(), current=new Frame();
    private static Graphics target;
    private static int copied;
    static boolean valid;
    private static final Hashtable sources=new Hashtable();
    private static final GraphicsBinding[] bindings=new GraphicsBinding[127];
    private static final class GraphicsBinding {
        WeakReference graphics, image;
        GraphicsBinding next;
    }
    static Graphics getGraphics(Image image) {
        Graphics g=image.getGraphics();
        int bucket=(g.hashCode() & 0x7fffffff)%bindings.length;
        GraphicsBinding previous=null,node=bindings[bucket];
        while(node!=null) {
            Object owner=node.graphics.get();
            if(owner==g) return g;
            if(owner==null || node.image.get()==null) {
                if(previous==null) bindings[bucket]=node.next;
                else previous.next=node.next;
            } else previous=node;
            node=node.next;
        }
        node=new GraphicsBinding();
        node.graphics=new WeakReference(g); node.image=new WeakReference(image);
        node.next=bindings[bucket]; bindings[bucket]=node;
        return g;
    }
    private static void beforeWrite(Graphics g) {
        if(sources.isEmpty() || !valid) return;
        for(GraphicsBinding b=bindings[(g.hashCode() & 0x7fffffff)%bindings.length];b!=null;b=b.next) {
            if(b.graphics.get()!=g) continue;
            Image image=(Image)b.image.get();
            if(image==null || sources.remove(image)==null) return;
            if(target==null || !reserve(image.getWidth()*image.getHeight())) {valid=false;return;}
            Image snapshot=Image.createImage(image);
            for(int i=0;i<current.size;i++) {
                Command cmd=current.ops[i];
                if(cmd.source==image) cmd.source=snapshot;
            }
            return;
        }
    }

    static final class Frame {
        Command[] ops=new Command[128];
        int size, width,height,groundEnd,worldEnd,tileWidth,tileHeight,tileX,tileY,cacheLeft,cacheTop;
        Image tileImage, tileSnapshot;
        Graphics tileGraphics;
        boolean terrainRead;
        int[] mapState;
        int worldX,worldY;
        int[] terrain;
        boolean complete;
        void clear() {
            for(int i=0;i<size;i++) {
                ops[i].key=null;
                ops[i].source=null;
                ops[i].font=null;
                ops[i].priorWithSameImage=null;
            }
            size=0;
            groundEnd=worldEnd=0;tileImage=null;mapState=null;terrainRead=false;
        }
        Command add() {
            if(size==ops.length) {
                Command[] replacement=new Command[size*2];
                System.arraycopy(ops,0,replacement,0,size);
                ops=replacement;
            }
            if(ops[size]==null) ops[size]=new Command();
            return ops[size++];
        }
    }
    static final class Command {
        int type, x, y, w, h, a, b, sx, sy, color, cx, cy, cw, ch, dx, dy, clipDx, clipDy;
        boolean used;
        Command priorWithSameImage;
        Object key,source;
        Font font;
    }
    static void begin(Graphics screen) {
        Frame swap=previous; previous=current; current=swap;
        current.clear(); sources.clear(); copied=0; valid=true; target=screen;
        current.width=screen.getClipWidth();current.height=screen.getClipHeight();
    }
    static void stop() { target=null; current.complete=valid; }
    static void world() {
        f.b();
        if(target!=null) current.worldEnd=current.size;
    }
    static void terrain(Graphics g,int x,int y,int layer) {
        int first=current.size;
        k.a(g,x,y,layer);
        if(g==target && g!=null && layer==0 && k.a!=null && k.a[0]!=null) {
            int[] state=k.a[0];
            boolean pixelOrigin=(state[15]&256)!=0;
            int originX=pixelOrigin?state[5]:state[9]*k.p[2];
            int originY=pixelOrigin?state[6]:state[10]*k.p[5];
            int left=current.width+state[14]+state[17]-originY-state[8];
            int top=originX-state[13]-state[16];
            rememberGround(first,left,top);
            rememberCamera(state,state[13]+state[16],state[14]+state[17]);
        }
    }
    static void rememberCamera(int[] mapState,int worldX,int worldY) {
        if(hasGround()) {
            current.mapState=mapState;current.worldX=worldX;current.worldY=worldY;
        }
    }
    static void rememberGround(int first,int cacheLeft,int cacheTop) {
        if(!valid || current.size<=first || current.size>first+4) return;
        Command base=current.ops[first];
        int w=current.width,h=current.height,tw=base.w,th=base.h;
        if(base.type!=IMAGE || base.a!=(Graphics.TOP|Graphics.LEFT) || tw<w || th<h || tw*th>1024*1024 ||
           cacheLeft>0 || cacheTop>0 || cacheLeft+tw<w || cacheTop+th<h) return;
        int area=0;
        for(int i=first;i<current.size;i++) {
            Command c=current.ops[i];
            if(c.type!=IMAGE || c.a!=base.a || c.key!=base.key || (c.x-base.x)%tw!=0 || (c.y-base.y)%th!=0) return;
            if(c.cx<0 || c.cy<0 || c.cx+c.cw>w || c.cy+c.ch>h || c.cx<c.x || c.cy<c.y ||
               c.cx+c.cw>c.x+tw || c.cy+c.ch>c.y+th) return;
            for(int j=first;j<i;j++) {
                Command p=current.ops[j];
                if(c.cx<p.cx+p.cw && p.cx<c.cx+c.cw && c.cy<p.cy+p.ch && p.cy<c.cy+c.ch) return;
            }
            area+=c.cw*c.ch;
        }
        if(area!=w*h) return;
        current.tileImage=(Image)base.source;
        if(current.tileSnapshot==null || current.tileWidth!=tw || current.tileHeight!=th) {
            current.tileSnapshot=Image.createImage(tw,th);
            current.tileGraphics=current.tileSnapshot.getGraphics();
        }
        current.tileGraphics.drawImage(current.tileImage,0,0,Graphics.TOP|Graphics.LEFT);
        current.tileWidth=tw;current.tileHeight=th;
        current.tileX=wrap(-base.x,tw);current.tileY=wrap(-base.y,th);
        current.cacheLeft=cacheLeft;current.cacheTop=cacheTop;
        current.groundEnd=current.size;
    }
    private static int wrap(int n,int period) {
        int r=n%period;
        return r<0?r+period:r;
    }
    private static int difference(int curr,int prev,int period) {
        return wrap(curr-prev+period/2,period)-period/2;
    }
    // Keep both native poses resident so a wrapped seam can use the old edge.
    private static void groundRect(Graphics g,Frame f,int phaseX,int phaseY,int left,int top,int right,int bottom) {
        for(int y=top;y<bottom;) {
            int sy=wrap(phaseY+y,f.tileHeight);
            int rows=Math.min(bottom-y,f.tileHeight-sy);
            for(int x=left;x<right;) {
                int sx=wrap(phaseX+x,f.tileWidth);
                int cols=Math.min(right-x,f.tileWidth-sx);
                g.drawRegion(f.tileSnapshot,sx,sy,cols,rows,0,x,y,Graphics.TOP|Graphics.LEFT);
                x+=cols;
            }
            y+=rows;
        }
    }
    private static int cameraDx,cameraDy,stableSkyStart;
    private static void readTerrain(Frame f) {
        if(f.terrainRead)return;
        int n=f.tileWidth*f.tileHeight;
        if(f.terrain==null || f.terrain.length!=n)f.terrain=new int[n];
        f.tileSnapshot.getRGB(f.terrain,0,f.tileWidth,0,0,f.tileWidth,f.tileHeight);
        f.terrainRead=true;
    }
    private static boolean sameSky(int start) {
        // The sky actor never scrolls sideways. Protect any foreground
        // scenery in this band by requiring identical native LCD strips.
        Frame c=current,p=previous;
        readTerrain(c);readTerrain(p);
        for(int y=0;y<c.height;y++) {
            int row=wrap(c.tileY+y,c.tileHeight)*c.tileWidth;
            int old=wrap(p.tileY+y,p.tileHeight)*p.tileWidth;
            int x=wrap(c.tileX+start,c.tileWidth),px=wrap(p.tileX+start,p.tileWidth);
            for(int i=start;i<c.width;i++) {
                if(c.terrain[row+x]!=p.terrain[old+px]) return false;
                if(++x==c.tileWidth)x=0;
                if(++px==p.tileWidth)px=0;
            }
        }
        return true;
    }
    private static void findStableSky() {
        if(current.mapState==null || current.mapState.length<18 || k.p==null ||
                cameraDx!=0 || cameraDy==0 || previous.worldY!=current.worldY) return;
        int fullHeight=current.mapState[3]*36,y=current.worldY;
        if(fullHeight<=0)return;
        int zoom=(current.mapState[6]*100+fullHeight/2)/fullHeight;
        if(zoom<=0 || y>=648*zoom/100)return;
        int worldY=y*100/zoom;
        // The highest mountain module is 245 pixels high. Everything
        // above it is the sky/solid backdrop in the Android projection.
        int mountains=(int)(648-(648-worldY)*40.0f/648+0.5f);
        int limit=(mountains-245)*zoom/100-y-1;
        int start=Math.max(0,current.width-limit);
        if(start<current.width && sameSky(start)) stableSkyStart=start;
    }
    static boolean hasGround() {return current.groundEnd!=0;}
    private static boolean groundCovered(int remain,int period) {
        int dx=cameraDx*remain/period,dy=cameraDy*remain/period;
        int cl=dx+current.cacheLeft,ct=dy+current.cacheTop;
        int cr=cl+current.tileWidth,cb=ct+current.tileHeight,w=current.width,h=current.height;
        if(cl<=0 && ct<=0 && cr>=w && cb>=h) return true;
        int pl=dx-cameraDx+previous.cacheLeft,pt=dy-cameraDy+previous.cacheTop;
        int pr=pl+previous.tileWidth,pb=pt+previous.tileHeight;
        // A quick diagonal move can require a corner in neither cached
        // rectangle. Keep the native pose for that presentation.
        if(cl>0 && (pl>0 || pr<cl || pt>0 || pb<h)) return false;
        if(cr<w && (pl>cr || pr<w || pt>0 || pb<h)) return false;
        if(ct>0 && (pl>0 || pr<w || pt>0 || pb<ct)) return false;
        return cb>=h || (pl<=0 && pr>=w && pt<=cb && pb>=h);
    }
    private static void drawGround(Graphics g,int remain,int period) {
        int w=current.width,h=current.height;
        int dx=cameraDx*remain/period,dy=cameraDy*remain/period;
        int phaseX=current.tileX-dx,phaseY=current.tileY-dy;
        g.setClip(0,0,w,h);
        groundRect(g,current,phaseX,phaseY,0,0,w,h);
        if(dx==0 && dy==0) return;
        // When the native cache loads a new row/column, preserve terrain on
        // the trailing edge from the previous tick's actual visible area.
        int px=dx-cameraDx,py=dy-cameraDy;
        int x0=Math.max(0,px+previous.cacheLeft),x1=Math.min(w,px+previous.cacheLeft+previous.tileWidth);
        int y0=Math.max(0,py+previous.cacheTop),y1=Math.min(h,py+previous.cacheTop+previous.tileHeight);
        int cl=dx+current.cacheLeft,cr=cl+current.tileWidth,ct=dy+current.cacheTop,cb=ct+current.tileHeight;
        int prevX=previous.tileX-px,prevY=previous.tileY-py;
        if(cl>0) groundRect(g,previous,prevX,prevY,x0,y0,Math.min(x1,cl),y1);
        if(cr<w) groundRect(g,previous,prevX,prevY,Math.max(x0,cr),y0,x1,y1);
        if(ct>0) groundRect(g,previous,prevX,prevY,x0,y0,x1,Math.min(y1,ct));
        if(cb<h) groundRect(g,previous,prevX,prevY,x0,Math.max(y0,cb),x1,y1);
        if(stableSkyStart<w) groundRect(g,current,current.tileX,current.tileY,stableSkyStart,0,w,h);
    }
    private static Command record(Graphics g,int type,Object key,int x,int y,int w,int h,int a,int b,int sx,int sy) {
        if(g!=target) {beforeWrite(g);return null;}
        if(!valid) return null;
        if(current.size==MAX_COMMANDS) {valid=false; return null;}
        Command c=current.add();
        c.type=type;c.key=key;c.source=key;c.x=x;c.y=y;c.w=w;c.h=h;c.a=a;c.b=b;c.sx=sx;c.sy=sy;
        c.dx=0;c.dy=0;c.clipDx=0;c.clipDy=0;c.used=false;
        c.cx=g.getClipX(); c.cy=g.getClipY(); c.cw=g.getClipWidth(); c.ch=g.getClipHeight();
        c.color=type>=TEXT?g.getColor():0; c.font=type==TEXT ? g.getFont() : null;
        return c;
    }
    private static boolean reserve(int n) {
        if(n<0 || n>MAX_SNAPSHOT_PIXELS-copied) {valid=false;return false;}
        copied+=n;return true;
    }
    private static void image(Command c,Image src) {
        if(c!=null && src.isMutable()) sources.put(src,src);
    }
    static void drawImage(Graphics g,Image src,int x,int y,int anchor) {
        if(g==target && valid)image(record(g,IMAGE,src,x,y,src.getWidth(),src.getHeight(),anchor,0,0,0),src);
        else beforeWrite(g);
        g.drawImage(src,x,y,anchor);
    }
    static void drawRegion(Graphics g,Image src,int sx,int sy,int w,int h,int transform,int x,int y,int anchor) {
        image(record(g,REGION,src,x,y,w,h,anchor,transform,sx,sy),src);
        g.drawRegion(src,sx,sy,w,h,transform,x,y,anchor);
    }
    static void drawString(Graphics g,String text,int x,int y,int anchor) {
        record(g,TEXT,text,x,y,0,0,anchor,0,0,0);g.drawString(text,x,y,anchor);
    }
    static void drawRGB(Graphics g,int[] rgb,int off,int stride,int x,int y,int w,int h,boolean alpha) {
        Command c=record(g,RGB,null,x,y,w,h,alpha?1:0,0,0,0);
        if(c!=null && w>0 && h>0 && reserve(w*h)) {
            int[] pixels=new int[w*h];
            for(int row=0;row<h;row++) System.arraycopy(rgb,off+row*stride,pixels,row*w,w);
            c.source=pixels;
        }
        g.drawRGB(rgb,off,stride,x,y,w,h,alpha);
    }
    static void fillRect(Graphics g,int x,int y,int w,int h) {record(g,FILL,null,x,y,w,h,0,0,0,0);g.fillRect(x,y,w,h);}
    static void drawRect(Graphics g,int x,int y,int w,int h) {record(g,RECT,null,x,y,w,h,0,0,0,0);g.drawRect(x,y,w,h);}
    static void drawArc(Graphics g,int x,int y,int w,int h,int a,int b) {record(g,ARC,null,x,y,w,h,a,b,0,0);g.drawArc(x,y,w,h,a,b);}
    static void fillArc(Graphics g,int x,int y,int w,int h,int a,int b) {record(g,FILLEDARC,null,x,y,w,h,a,b,0,0);g.fillArc(x,y,w,h,a,b);}
    static void drawLine(Graphics g,int x,int y,int x2,int y2) {record(g,LINE,null,x,y,x2,y2,0,0,0,0);g.drawLine(x,y,x2,y2);}
    static void fillTriangle(Graphics g,int x,int y,int x2,int y2,int x3,int y3) {record(g,TRIANGLE,null,x,y,x2,y2,x3,y3,0,0);g.fillTriangle(x,y,x2,y2,x3,y3);}
    private static boolean samePart(Command a, Command b) {
        return a.key==b.key && a.type==b.type && a.a==b.a && a.b==b.b && a.sx==b.sx &&
            a.sy==b.sy && a.w==b.w && a.h==b.h && a.cw==b.cw && a.ch==b.ch;
    }
    private static final Hashtable previousParts=new Hashtable();
    static int match() {
        cameraDx=cameraDy=0;stableSkyStart=current.width;
        if(!valid || !previous.complete) return 0;
        if(current.mapState!=previous.mapState || current.mapState!=null &&
           (current.tileImage!=previous.tileImage ||
            Math.abs(current.worldX-previous.worldX)>32 || Math.abs(current.worldY-previous.worldY)>32))
            return 0;
        if(current.tileImage!=null && current.tileImage==previous.tileImage) {
            cameraDx=difference(current.tileX,previous.tileX,current.tileWidth);
            cameraDy=difference(current.tileY,previous.tileY,current.tileHeight);
            if(Math.abs(cameraDx)>32 || Math.abs(cameraDy)>32) cameraDx=cameraDy=0;
        }
        if(a.a()!=17 || current.tileImage==null || (cameraDx==0 && cameraDy==0))return 0;
        findStableSky();
        previousParts.clear();
        for(int i=previous.groundEnd;i<previous.size;i++) {
            Command p=previous.ops[i];
            if(p.type!=IMAGE && p.type!=REGION) continue;
            p.priorWithSameImage=(Command)previousParts.put(p.key,p);
            p.used=false;
        }
        int matched=cameraDx!=0 || cameraDy!=0 ? 1 : 0;
        for(int i=current.groundEnd;i<current.size;i++) {
            Command c=current.ops[i];
            if(c.type!=IMAGE && c.type!=REGION) continue;
            boolean world=i<current.worldEnd;
            int expectedX=world?cameraDx:0,expectedY=world?cameraDy:0;
            Command best=null;
            int first=2049, second=2049;
            for(Command p=(Command)previousParts.get(c.key);p!=null;p=p.priorWithSameImage) {
                if(p.used || !samePart(c,p)) continue;
                int dx=p.x-c.x,dy=p.y-c.y;
                if(Math.abs(dx)>32 || Math.abs(dy)>32) continue;
                if(p.cx!=c.cx && p.cx-c.cx!=dx || p.cy!=c.cy && p.cy-c.cy!=dy) continue;
                int ex=dx-expectedX,ey=dy-expectedY;
                int distance=ex*ex+ey*ey;
                if(distance<first) { second=first; first=distance; best=p; }
                else if(distance<second) second=distance;
            }
            // Repeated cels occur in crops and text. Only animate an unambiguous instance.
            if(best==null || (first>0 && second-first<Math.max(4,first/2))) {
                // Ambiguous repeated cels stay in the native pose.
                continue;
            }
            best.used=true;
            if(best.x==c.x && best.y==c.y) continue;
            if(!world || best.x-c.x!=cameraDx || best.y-c.y!=cameraDy) continue;
            c.dx=best.x-c.x; c.dy=best.y-c.y;
            c.clipDx=best.cx-c.cx; c.clipDy=best.cy-c.cy;
            matched++;
        }
        previousParts.clear();
        return matched;
    }
    static void replay(Graphics g,int remaining,int period) {
        if(hasGround()) {
            if(!groundCovered(remaining,period)) remaining=0;
            drawGround(g,remaining,period);
        }
        int lastClipX=-1,lastClipY=-1,lastClipW=-1,lastClipH=-1;
        for(int i=current.groundEnd;i<current.size;i++) {
            Command c=current.ops[i];
            int clipX=c.cx+c.clipDx*remaining/period,clipY=c.cy+c.clipDy*remaining/period;
            if(clipX!=lastClipX || clipY!=lastClipY || c.cw!=lastClipW || c.ch!=lastClipH) {
                g.setClip(clipX,clipY,c.cw,c.ch);
                lastClipX=clipX;lastClipY=clipY;lastClipW=c.cw;lastClipH=c.ch;
            }
            int x=c.x + c.dx*remaining/period, y=c.y + c.dy*remaining/period;
            switch(c.type) {
            case IMAGE:g.drawImage((Image)c.source,x,y,c.a);break;
            case REGION:g.drawRegion((Image)c.source,c.sx,c.sy,c.w,c.h,c.b,x,y,c.a);break;
            case RGB:if(c.source!=null) g.drawRGB((int[])c.source,0,c.w,x,y,c.w,c.h,c.a!=0);break;
            default:
                g.setColor(c.color);
                switch(c.type) {
                case TEXT:g.setFont(c.font);g.drawString((String)c.source,x,y,c.a);break;
                case FILL:g.fillRect(x,y,c.w,c.h);break;
                case RECT:g.drawRect(x,y,c.w,c.h);break;
                case ARC:g.drawArc(x,y,c.w,c.h,c.a,c.b);break;
                case FILLEDARC:g.fillArc(x,y,c.w,c.h,c.a,c.b);break;
                case LINE:g.drawLine(x,y,c.w,c.h);break;
                case TRIANGLE:g.fillTriangle(x,y,c.w,c.h,c.a,c.b);break;
                }
            }
        }
    }
}
