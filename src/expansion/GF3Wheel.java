import javax.microedition.lcdui.Graphics;
import java.util.Random;

/** APK 4.4.4 panel 45 and world building 1019 (sheet 185).
 * Offline purchase and payout replace the discontinued advertising service.
 */
final class GF3Wheel {
    private static final int SCREEN=50,GUI=30,BASE=173,PRICE=3;
    private static final int[] PARTS={3,4,5,6}; // Original /dh sheets 20,22,33,41.
    private static final int[] ANGLES={120,80,40,60,60};
    private static final int[] COLORS={0xffb23c,0xd8f158,0x58bdeb,0xf86456,0xb35bc1};
    // First two amounts are the Android qK defaults. The remaining rewards
    // are offline currency substitutions for unavailable online prize draws.
    private static final int[] COINS={100,0,500,0,1000};
    private static final int[] BILLS={0,1,0,3,0};
    private static final String[] EMPTY=new String[13];
    private static final Random random=new Random();
    private static l[] previousImages,images;
    private static byte[] previousFlags,flags;
    private static boolean loaded,cache,spinning;
    private static long started;
    private static int rotation,startRotation,endRotation,result=-1;

    static boolean openBuilding(int row) {
        if(row!=29)return GF3Doghouse.openBuilding(row);
        a.c(60);a.a(SCREEN);return true;
    }
    private static void enterCache(){
        if(cache)return;
        previousImages=a.images;previousFlags=a.flags;
        if(images==null){images=new l[256];flags=new byte[256];}
        a.images=images;a.flags=flags;cache=true;
    }
    private static void leaveCache(){
        if(!cache)return;
        a.images=previousImages;a.flags=previousFlags;
        previousImages=null;previousFlags=null;cache=false;
    }
    private static void load(){
        if(loaded)return;
        if(a.assets==null || a.assets.length<BASE+4)throw new IllegalStateException("Wheel sprite cache");
        g.open("/dh");
        try {
            for(int i=0;i<PARTS.length;i++){
                e art=new e();art.a(g.read(PARTS[i]),0);a.assets[BASE+i]=art;
            }
        }finally{g.l();}
        a.b(GUI,true);
        loaded=true;
    }
    private static void show(int i,boolean visible,boolean hit){
        short[] row=a.controls[GUI][i];
        if(row[0]==204)row[15]=(short)(visible?1:0);
        else{row[10]=(short)(visible?1:0);row[18]=(short)(hit?1:0);}
    }
    private static void fill(){
        String[] text=a.captions[GUI];
        text[2]=GF3WheelText.TITLE;
        text[8]=GF3WheelText.SPIN+" ("+PRICE+" billetes)";
        text[12]=spinning?"Girando...":result<0?"Usa "+PRICE+" billetes para girar.":"Premio: "+reward(result);
        text[11]="Billetes: "+a.e();
        show(4,true,!spinning);show(5,false,false);show(6,true,!spinning);
        show(7,false,false);show(8,true,false);show(9,false,false);show(10,false,false);
        show(11,true,false);show(12,true,false);
        a.gf();a.H(GUI);
    }
    private static String reward(int i){return COINS[i]>0?COINS[i]+" monedas":BILLS[i]+" billetes";}
    static int sector(int angle){
        angle=(angle%360+360)%360;
        for(int i=0;i<ANGLES.length;i++){if(angle<ANGLES[i])return i;angle-=ANGLES[i];}
        return ANGLES.length-1;
    }
    private static void spin(){
        if(spinning)return;
        if(a.e()<PRICE){a.c(56);return;}
        int angle=random.nextInt(360),pick=sector(angle),sum=0;
        for(int i=0;i<pick;i++)sum+=ANGLES[i];
        int target=(90-(sum+ANGLES[pick]/2)+360)%360;
        startRotation=rotation;endRotation=rotation+360*4+(target-rotation+360)%360;
        // Apply debit and prize in the same farm save. Closing the game
        // cannot collect a second prize or lose an already paid spin.
        if(!a.f(PRICE))return;
        if(COINS[pick]>0)a.g(COINS[pick]);else a.h(BILLS[pick]);
        a.c(true);
        result=pick;spinning=true;started=System.currentTimeMillis();a.c(61);fill();
    }
    private static void update(){
        if(!spinning)return;
        int ms=(int)Math.max(0L,Math.min(3200L,System.currentTimeMillis()-started));
        long left=3200-ms;
        long eased=32768L-left*left*left/1000000L;
        rotation=(startRotation+(int)((endRotation-startRotation)*eased/32768L))%360;
        if(ms>=3200){rotation=endRotation%360;spinning=false;a.c(49);fill();}
    }
    private static void draw(){
        Graphics screen=g.graphics;
        if(screen==null || !loaded)return;
        String[] text=a.captions[GUI];
        a.captions[GUI]=EMPTY;
        try{a.F(GUI);}finally{a.captions[GUI]=text;}
        e sheet=a.assets[BASE+3];
        // Panel 45 draws the five wedges procedurally inside APK frame 34,
        // whose hole is 284 px across. Native g rotates landscape to portrait.
        final int x=25,y=40,cx=x+157,cy=y+182;
        int angle=rotation;
        for(int i=0;i<ANGLES.length;i++){
            screen.setColor(COLORS[i]);
            g.arc(screen,cx-142,cy-142,284,284,angle,ANGLES[i],true);
            double r=(angle+ANGLES[i]/2)*3.141592653589793/180.0;
            int px=cx+(int)(90*Math.cos(r)),py=cy-(int)(90*Math.sin(r));
            int icon=COINS[i]>0?0:1;
            sheet.a(screen,icon,px-sheet.d(icon)/2,py-sheet.e(icon)/2,0);
            // Native text routine uses the panel's rotated coordinates.
            screen.setColor(0x28221b);
            screen.drawString(Integer.toString(COINS[i]>0?COINS[i]:BILLS[i]),479-py,px+20,Graphics.HCENTER|Graphics.TOP);
            angle+=ANGLES[i];
        }
        sheet.a(screen,34,x,y,0);
        for(int i=0;i<text.length;i++)if(text[i]!=null && a.controls[GUI][i][0]==204 && a.controls[GUI][i][15]==1)
            a.a(text[i],GUI,i,0,0);
    }
    static boolean dispatch(int phase,int index){
        int[] states=a.states;
        if(states==null || index<0 || index>=states.length || states[index]!=SCREEN)
            return a.gf3WheelPreviousScreen(phase,index);
        if(phase==0){result=-1;rotation=0;load();}
        if(phase==1){enterCache();a.E(GUI);fill();}
        if(phase==2){
            update();
            int key=g.i();
            if(!spinning && (key==19 || key==11))a.t();
        }
        if(phase==3)draw();
        if(phase==4)leaveCache();
        if(phase==5){
            leaveCache();loaded=false;spinning=false;images=null;flags=null;
            for(int i=0;i<4;i++)a.assets[BASE+i]=null;
        }
        return false;
    }
    static void hit(int event){
        if((event>>>16)!=GUI){a.gf3WheelPreviousHit(event);return;}
        int row=event&65535;
        if(row==4 && !spinning){a.c(57);a.t();}
        else if(row==6)spin();
    }
}
