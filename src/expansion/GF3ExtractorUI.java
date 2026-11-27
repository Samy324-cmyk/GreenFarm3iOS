/** Android honey-press controls and animation in the native kitchen queue. */
final class GF3ExtractorUI {
    private static final int GUI=22, FIRST=174, SHEET=166;
    private static final int[] bounds=new int[4], fromHouse={3,4,7};
    private static int pressed;
    private static short[][] shifted;
    private static short[] background;
    private static int displacement;
    private static k animation;
    private static long lastTick;
    private static l[] savedImages;
    private static final l[] buttons=new l[2];
    private static byte[] savedFlags;
    private static int dropStep,dropX,dropY;

    private static void cache() {
        if(savedImages!=null) return;
        savedImages=a.images;
        savedFlags=a.flags;
        a.images=new l[256];
        a.flags=new byte[256];
        a.images[244]=buttons[0];a.images[245]=buttons[1];
    }

    private static void releaseCache() {
        if(savedImages==null) return;
        a.images=savedImages;
        a.flags=savedFlags;
        savedImages=null;
        savedFlags=null;
    }

    private static void load() {
        if(a.assets.length<SHEET+5) {
            e[] resized=new e[SHEET+5];
            System.arraycopy(a.assets,0,resized,0,a.assets.length);
            a.assets=resized;
        }
        if(a.assets[SHEET+4]!=null) return;
        g.gf3Open("/dh");
        for(int i=0;i<3;i++) {
            e art=new e(); art.a(g.gf3Read(fromHouse[i]),0); a.assets[SHEET+i]=art;
        }
        g.l();
        g.gf3Open("/hx");
        for(int i=0;i<2;i++) {
            e art=new e(); art.a(g.gf3Read(i),0); a.assets[SHEET+3+i]=art;
            byte[] pixels=g.gf3Read(i+2);
            int width=(pixels[0]&255)<<8 | pixels[1]&255, height=(pixels[2]&255)<<8 | pixels[3]&255;
            int[] argb=new int[width*height];
            for(int j=0;j<argb.length;j++) {
                int p=4+4*j;
                argb[j]=pixels[p]<<24 | (pixels[p+1]&255)<<16 | (pixels[p+2]&255)<<8 | pixels[p+3]&255;
            }
            buttons[i]=l.a(argb,width,height,true);
        }
        g.l();
    }

    private static void move(short[][] rows, int dx) {
        for(int i=10;i<=85;i++) rows[i][2]=(short)(rows[i][2]+dx);
    }

    static void reset() {
        releaseCache();
        if(shifted!=null) {
            move(shifted,-displacement);
            if(a.templates!=null && a.templates[GUI]==shifted && a.controls[GUI]!=null)
                move(a.controls[GUI],-displacement);
        }
        shifted=null; background=null; animation=null; pressed=0; dropStep=0;
    }

    private static void position() {
        short[][] template=a.templates[GUI];
        if(shifted==template) return;
        shifted=template;
        displacement=template[26][2]-template[11][2];
        move(template,displacement);
        move(a.controls[GUI],displacement);
        short[] press=row(147);
        background=new short[press.length];
        System.arraycopy(press,0,background,0,press.length);
        background[10]=1;
    }

    private static short[] row(int slot) { return a.controls[GUI][FIRST+slot-147]; }

    private static void sprite(int slot) {
        short[] item=row(slot);
        item[10]=1;
        a.a(GUI,item,0,0,FIRST+slot-147);
        item[10]=0;
    }

    private static void caption(int slot,String text) {
        short[] item=row(slot);
        item[15]=1;
        a.a(text,GUI,FIRST+slot-147,0,0);
        item[15]=0;
    }

    private static void paint(int[] recipe,int stock) {
        boolean ready=stock>=recipe[7];
        if(ready) sprite(150);
        else {
            sprite(156);
            caption(157,GF3HoneyTutorial.phase()==1077?"0":GF3ExtractorText.unavailable);
        }
        if(animation==null) {
            row(151)[6]=(short)(ready?3:0);
            sprite(151);
        } else animation.gf3Render();
        row(152)[6]=(short)(ready && animation==null?244:245);
        sprite(152);
        caption(153,GF3ExtractorText.extract);
        caption(154,GF3ExtractorText.combs);
        caption(155,stock+" / "+recipe[7]);
        if(dropStep>0) {
            short[] jar=row(163);
            jar[2]=(short)dropX; jar[3]=(short)dropY;jar[5]=SHEET+4;jar[6]=7;
            sprite(163);
            a.a("+1",dropX+40,dropY+20,0,0,0,0,2,0,false,false);
        }
        GF3HoneyTutorial.drawPress();
    }

    private static boolean overButton(int which) {
        short[] button=row(which);
        a.assets[button[5]].a(button[6],0,bounds,0);
        int x=g.ac-button[2]-bounds[0], y=g.ad-button[3]-bounds[1];
        return x>=0 && x<bounds[2] && y>=0 && y<bounds[3];
    }

    private static boolean input(int[] recipe,int stock) {
        if(dropStep>0) {
            dropX+=dropStep*8/10; dropY+=dropStep*dropStep/10; dropStep++;
            if(dropY>480) dropStep=0;
        }
        if(animation!=null) {
            long now=System.currentTimeMillis();
            animation.c((int)Math.max(0L,Math.min(250L,now-lastTick)));
            lastTick=now;
            if(animation.gf3Finished()) {
                animation=null;
                dropStep=1;dropX=row(151)[2];dropY=row(151)[3];
                a.c(126);
                GF3HoneyTutorial.extractionFinished();
            }
        }
        if(g.ab==1) pressed=overButton(152)?152:GF3HoneyTutorial.phase()==1077 && overButton(156)?156:0;
        if(g.ab!=2 || pressed==0) return pressed!=0;
        int hit=pressed;pressed=0;
        if(!overButton(hit)) return true;
        if(hit==156) {GF3HoneyTutorial.refill();return true;}
        int lesson=GF3HoneyTutorial.phase();
        if((lesson==0 || lesson==1078) && animation==null && stock>=recipe[7] && GF3KitchenQueue.extract(recipe)) {
            short[] machine=row(151);
            animation=new k(a.assets[machine[5]],machine[2],machine[3]);
            animation.b(0,3);
            lastTick=System.currentTimeMillis();
            a.c(125);
        }
        return true;
    }

    static boolean screen(int phase,boolean honey,boolean drawer) {
        if(!honey || phase==5) {
            if(shifted!=null) reset();
            return a.gf3QueueScreen(phase);
        }
        if(phase==0 || phase==1) {
            load();
            if(phase==1) cache();
            boolean handled=a.gf3QueueScreen(phase);
            position();
            return handled;
        }
        if(phase==4) releaseCache();
        if(!drawer && (phase==2 || phase==3)) {
            if(phase==2) GF3HoneyTutorial.kitchen();
            int[] recipe=h.tables[7].rows[93];
            int count=a.g(0,recipe[6]);
            if(phase==2 && input(recipe,count)) return true;
            if(phase==3) {
                // The mobile panel includes the extractor's frame behind the
                // scroll cards, header, and currency values.
                short[] old=a.controls[GUI][0];
                a.a(GUI,old,0,0,0);
                a.controls[GUI][0]=background;
                boolean result;
                try {result=a.gf3QueueScreen(phase);}
                finally {a.controls[GUI][0]=old;}
                paint(recipe,count);
                return result;
            }
            boolean handled=a.gf3QueueScreen(phase);
            return handled;
        }
        return a.gf3QueueScreen(phase);
    }
}
