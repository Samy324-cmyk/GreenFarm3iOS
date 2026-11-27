import java.io.IOException;

/** The doghouse and first toy in quest 9299, Android tutorial phases 1026–1038. */
final class GF3DogTutorial {
    private static int phase;
    private static int shopCoins,shopBills;
    private static boolean focused,shelfReady,pressedDog;
    private static final int[] bounds=new int[4];

    private GF3DogTutorial() {}

    private static boolean active() {
        if(a.bD==null || a.cb==null || !a.h(9297))return false;
        for(int i=0;i<a.bD.length;i++)if(a.bD[i]==9297)return false;
        for(int i=0;i<a.bD.length;i++)if(a.bD[i]==9299 && a.cb[i]==2)return true;
        return false;
    }

    private static void go(int step) {
        if(focused)a.c();
        phase=step;focused=false;shelfReady=false;pressedDog=false;
    }

    private static void say(int string,int next) {
        go(next);
        a.a(GF3DogLines.TEXT[string-967],7,0);
    }

    private static void focus(f actor) {
        if(actor!=null && !focused && a.c!=null){
            a.c.a(actor.r,actor.s,0);
            a.a(actor,0,actor.q==54?-100:-70);
            focused=true;
        }
    }

    static boolean farm(int event) {
        // Android's av(1038) explicitly dispatches the pointed dog. The MIDP
        // farm can choose the crop or farmer behind it in a crowded tile.
        if(event==2 && active() && phase==1038 && a.F==0 && a.a()==17 && a.k==null && g.ab!=0) {
            f dog=GF3Doghouse.resident(null);
            if(dog!=null && dog.a!=null && a.art!=null && dog.E>=0 && dog.E<a.art.length && a.art[dog.E]!=null) {
                a.art[dog.E].a(bounds,dog.a.clip(),dog.a.frame(),0,0,dog.a.flags);
                int x=g.ac-dog.u,y=g.ad-dog.v;
                boolean hit=x>=bounds[0]*a.B/100 && x<=bounds[2]*a.B/100 &&
                            y>=bounds[1]*a.B/100 && y<=bounds[3]*a.B/100;
                if(g.ab==1)pressedDog=hit;
                if(pressedDog){
                    if(g.ab==2){pressedDog=false;if(hit)dog.h();}
                    return true;
                }
            }
        }
        boolean handled=a.gf3DogLessonsFarm(event);
        if(event!=2 || a.F!=0 || a.a()!=17 || a.transition!=-1 || a.c==null)return handled;
        if(!active()){if(phase!=0)go(0);return handled;}
        if(phase==0)go(GF3Doghouse.placed(null)==null?1026:1031);
        if(phase==1039){
            // The animation has finished. Dispatch the journal event only on
            // the farm tick, never while the actor list is being updated.
            GF3HomePredator.trained();go(0);a.b(2992,1,44);return handled;
        }
        if(phase==1029 && GF3Doghouse.placed(null)!=null)go(1030);
        if(phase==1030)say(970,1031);
        else if(phase==1031)focus(GF3Doghouse.placed(null));
        else if(phase==1035)say(971,1036);
        else if(phase==1036){
            // APK cGame.fH closes dialogue 1035 by opening the resource
            // market's pet-toy shelf. Wait for the normal MIDP transition.
            a.d(4,3,true);
        }
        else if(phase==1037)go(1038);
        else if(phase==1038)focus(GF3Doghouse.resident(null));
        return handled;
    }

    private static void shelf(int tab,int row) {
        if(shelfReady && a.cu==tab)return;
        a.r(tab,-1);
        int size=0;
        int[] slots=new int[tab==3?3:5];
        int count=Math.min(a.count,a.M.length);
        for(int item=0;item<slots.length;item++){
            int slot=0;
            while(slot<count && a.M[slot]!=row+item)slot++;
            if(slot==count){if(item==0)return;continue;}
            slots[size++]=slot;
        }
        if(size==0)return;
        int[][] columns={a.L,a.M,a.N,a.O,a.P,a.Q,a.R,a.S,a.T,a.U,a.V,a.W};
        for(int col=0;col<columns.length;col++){
            int[] values=new int[size];
            for(int i=0;i<size;i++)values[i]=columns[col][slots[i]];
            System.arraycopy(values,0,columns[col],0,size);
        }
        boolean[] locked=new boolean[size];
        for(int i=0;i<size;i++)locked[i]=a.locked[slots[i]];
        System.arraycopy(locked,0,a.locked,0,size);
        shopCoins=a.Q[0];shopBills=a.R[0];
        a.Q[0]=0;a.R[0]=0;
        a.ct=0;a.count=(char)size;
        for(int i=0;i<6;i++)a.card(i,i<size,false);
        a.visible(2,33,false);
        a.gf();a.H(2);a.J(0);
        shelfReady=true;
    }

    static boolean shop(int event) {
        boolean handled=a.gf3DogLessonsShop(event);
        if(event==3 && shelfReady && (phase==1029 || phase==1036))
            a.a(GF3DogLines.FREE,2,32,0,0);
        if(event==1)shelfReady=false;
        if(event!=2 || a.F!=0 || a.a()!=7 || a.transition!=-1 || !active())return handled;
        if(phase==0)go(1026);
        if(phase>=1026 && phase<=1028){
            int current=phase;
            say(967+current-1026,current+1);
        } else if(phase==1029)shelf(3,24);
        else if(phase==1036)shelf(4,64);
        return handled;
    }

    static void house() {
        if(!active() || a.transition!=-1)return;
        if(phase==1031)go(1032);
        if(phase==1032)say(972,1033);
        else if(phase==1033 && GF3DogToys.nextBonus>System.currentTimeMillis())go(1034);
    }

    static int hint() {return phase==1033?69:phase==1034?68:-1;}

    static boolean closeHouse() {
        if(phase==1033 && GF3DogToys.nextBonus<=System.currentTimeMillis()){
            f dog=GF3Doghouse.resident(null);
            if(dog!=null && !dog.a(32) && GF3Dogs.level(dog)>0)return false;
            // A restored farm may still have a puppy. Let the player feed it,
            // then present the reward when they return with the adult dog.
            return true;
        }
        if(phase==1034)go(1035);
        return true;
    }

    static void claimed() {if(phase==1033)go(1034);}
    static void placed(int row) {if(phase==1029 && row==24)go(1030);}
    static void bought(int toy) {
        if(phase==1036 && toy==0){
            if(a.cu==4 && a.M[0]==64){
                a.Q[0]=shopCoins;a.R[0]=shopBills;
                a.card(0,true,false);
            }
            go(1037);
        }
    }
    static void played() {if(phase==1038 && active())phase=1039;}

    static void reset() {
        phase=0;focused=false;shelfReady=false;pressedDog=false;
        GF3PetNames.reset();
    }

    static byte[] pack(byte[] data) {
        if(phase==0)return GF3PetNames.pack(data);
        int n=data.length;
        byte[] result=new byte[n+5];
        System.arraycopy(data,0,result,0,n);
        result[n]=(byte)(phase-1026);
        result[n+1]='D';result[n+2]='G';result[n+3]='T';result[n+4]=1;
        return GF3PetNames.pack(result);
    }

    static byte[] unpack(byte[] source) throws IOException {
        byte[] data=GF3PetNames.unpack(source);
        int n=data.length-5;
        if(n<0 || data[n+1]!='D' || data[n+2]!='G' || data[n+3]!='T')return data;
        if(data[n+4]!=1 || (data[n]&255)>13)throw new IOException();
        go(1026+data[n]);
        byte[] original=new byte[n];
        System.arraycopy(data,0,original,0,n);
        return original;
    }
}
