import java.io.IOException;

/** Dog toys use the farm's normal shop, action ribbon and original pet animations. */
final class GF3DogToys {
    private static final int[] STOCK = new int[4];
    private static final int[] MOOD = {2,6,4,21};
    // Rows are toys. Columns match beagle, spaniel, shepherd and dalmatian.
    private static final int[][] XP = {{3,5,6,6},{9,14,18,18},{8,12,16,16},{26,39,52,52}};
    private static final int[][] FARM_XP = {{0,0,0,0},{30,45,60,60},{20,30,40,40},{90,135,180,180}};
    private static f selected;
    private static volatile int gesture=-1;
    private static volatile boolean pointerCaptured;
    private static int pressX,pressY;
    private static volatile int dragging=-1,dragX,dragY,armed=-1;
    private static final int[] SLOT_X={257,349,451,543},SLOT_Y={434,416,416,434};
    static int slotX(int i){return SLOT_X[i];}
    static int slotY(int i){return SLOT_Y[i];}
    static int dragToy(){return dragging;}
    static int dragX(){return dragX;}
    static int dragY(){return dragY;}
    static int visibleToy(int i){return (a.aF+i+4)%4;}
    static boolean ribbonActive(){return selected!=null && a.screen()==17 && a.F==0;}
    static void wheelSound(int cue){if(selected==null)a.sound(cue);}
    private static f sounding;
    private static int lastStep=-1,lastClip=-1,lastFrame=-1;
    private static boolean eatingHeard;
    static long nextBonus;

    static int quantity(int toy) { return toy>=0 && toy<STOCK.length?STOCK[toy]:0; }
    private static boolean playable(f pet,int toy){
        if(pet==null || pet.a==null || pet.a(32) || !pet.a(512) || pet.a(4096) || toy<0 || toy>=4)return false;
        e sheet=pet.a.sprite();
        int clip=17+toy;
        return sheet!=null && clip<sheet.animations() && sheet.a(clip)>0;
    }

    // Touch coordinates have already been rotated into the logical canvas.
    // Consume the entire gesture while the pet ribbon is open: the crop
    // handler must never receive a stray release from a pet selection.
    private static int slotAt(int x,int y){
        int best=-1,dist=52;
        for(int i=0;i<4;i++){
            int d=Math.abs(x-SLOT_X[i])+Math.abs(y-SLOT_Y[i]);
            if(d<dist){dist=d;best=i;}
        }
        return best;
    }
    private static boolean onDog(int x,int y){
        f pet=selected;
        return pet!=null && Math.abs(x-pet.u)<65 && y>=pet.v-100 && y<=pet.v+35;
    }
    static boolean pointer(int px,int py,int phase){
        int x=py,y=479-px;
        if(phase==0){
            pointerCaptured=ribbonActive();
            if(pointerCaptured){
                pressX=x;pressY=y;dragX=x;dragY=y;
                int slot=slotAt(x,y);
                dragging=slot<0?-1:visibleToy(slot);
            }
        }
        if(!pointerCaptured)return false;
        dragX=x;dragY=y;
        if(phase==1){
            int item=dragging;
            dragging=-1;
            if(item>=0 && onDog(x,y))gesture=item;
            else if(item>=0 && Math.abs(x-pressX)<20 && Math.abs(y-pressY)<20)armed=item;
            else if(armed>=0 && onDog(x,y))gesture=armed;
            else if(pressY>=365 && y>=365 && Math.abs(x-pressX)>38)gesture=x>pressX?101:102;
            else if(y<365 || x<190 || x>610)gesture=100;
            pointerCaptured=false;
        }
        return true;
    }
    private static void dismiss(){
        f old=selected;selected=null;gesture=-1;armed=dragging=-1;
        if(old!=null && old.a!=null && old.D==15)old.i(0);
    }
    private static void processGesture(){
        int action=gesture;gesture=-1;
        if(action<0 || !ribbonActive())return;
        if(action==100){dismiss();return;}
        if(action==101 || action==102){
            a.aF=(a.aF+(action==101?3:1))%4;
            armed=-1;
            return;
        }
        if(action<4)play(action);
    }
    private GF3DogToys() {}

    static void buy(int button) {
        int pos = button + a.ct;
        if(a.M!=null && pos>=0 && pos<a.M.length && !a.f[pos] &&
                (a.cu==0 && GF3PetNames.unavailable(a.M[pos]) ||
                 a.cu==3 && GF3PetNames.houseUnavailable(a.M[pos]))) return;
        if(a.cu==4 && a.M!=null && pos>=0 && pos<a.M.length && a.M[pos]==68 && !a.f[pos]){
            GF3PetNames.collar(pos,button);
            return;
        }
        if (a.cu != 4 || a.M == null || pos < 0 || pos >= a.M.length ||
                a.M[pos] < 64 || a.M[pos] > 67 || a.f[pos]) {
            a.gf3PreviousBuy(button);
            return;
        }
        int toy = a.M[pos] - 64;
        if (a.Q[pos] != 0 ? a.c(a.Q[pos]) : a.f(a.R[pos])) {
            STOCK[toy]++;
            GF3DogTutorial.bought(toy);
            a.sound(61);
        } else {
            // Original handler presents the localized missing-currency dialog.
            a.gf3PreviousBuy(button);
        }
    }

    private static void menu(f pet) {
        if(selected==pet && ribbonActive()){dismiss();return;}
        if(selected!=null)dismiss();
        // Close the native crop/tool menu; the pet ribbon owns no crop state.
        a.clearTool(-1);
        a.a(false,(f)null);
        selected=pet;
        a.aF=0;
        armed=dragging=-1;
        pet.i(0);
    }
    static boolean touch(f pet) {
        if(GF3Dogs.dog(pet) && a.F==0){
            GF3Dogs.normalize(pet);
            if(playable(pet,0) && (pet.D==0 || pet.D==1 || pet.D==2 || pet.D==15) &&
                    !pet.a(4) && !pet.a(256)){
                menu(pet);return true;
            }
        }
        return pet.gf3PreviousPetTouch();
    }
    private static void play(int toy){
        f pet=selected;
        if(!playable(pet,toy) || STOCK[toy]<=0 || h.a[4].rows[64+toy][8]>a.f()){
            a.sound(56);armed=-1;return;
        }
        dismiss();
        pet.a.b(17+toy,2);
        GF3Dogs.beginToy(pet,toy);
        STOCK[toy]--;
        pet.D=13;
    }
    static void control(int event) {
        if(ribbonActive() && event>=65601 && event<=65606){
            play(visibleToy((event-65601)%4));return;
        }
        if(ribbonActive())dismiss();
        a.gf3PreviousControl(event);
    }

    static int tick(f pet) {
        if (!GF3Dogs.dog(pet)) return pet.q;
        GF3Dogs.normalize(pet);
        if(selected==pet){
            if(!ribbonActive())dismiss();
            else {processGesture();if(selected==pet)return 55;}
        }
        GF3PetNames.farmTick(pet);
        int pending = GF3Dogs.pending(pet);
        if(a.F==0 && pet.a(512) && pet.a!=null)sound(pet,pending);
        if (pending == 0) {
            if (pet.D == 15) {
                if (selected == pet) return 55;
                pet.i(0);
            }
            return pet.q;
        }
        int toy = pending-1;
        if(!playable(pet,toy)){
            if(toy>=0 && toy<4)STOCK[toy]++;
            GF3Dogs.cancelToy(pet);
            if(pet.a!=null)pet.i(0);
            return 55;
        }
        if (pet.D != 13 || pet.a.aId() != 17+toy) {
            pet.D = 13;
            pet.a.b(17+toy,2);
        } else if (pet.a.a()) {
            int breed = pet.J == 2070 ? 0 : pet.J == 2072 ? 1 : pet.J == 2068 ? 2 : 3;
            GF3Dogs.finishToy(pet,XP[toy][breed],MOOD[toy]);
            int playerXP = FARM_XP[toy][breed];
            if (playerXP > 0) f.a(47,2,new int[] {0,0,14}).a(pet.r,pet.s,37,1000,false,playerXP);
            pet.i(0);
            GF3DogTutorial.played();
        }
        // Skip the stock livestock timetable during the toy interaction.
        return 55;
    }

    private static void sound(f pet,int pending) {
        int clip=pet.a.aId(),frame=pet.a.frameNumber();
        boolean entering=sounding!=pet || lastStep!=pet.D;
        if(entering)eatingHeard=false;
        if(!entering && clip==lastClip && frame==lastFrame)return;
        sounding=pet;lastStep=pet.D;lastClip=clip;lastFrame=frame;
        if(pet.D==3 && frame==2 && !eatingHeard) {
            eatingHeard=true;
            GF3FarmAudio.original(78);
        } else if(pet.D==13 && pending>0 && frame==9)
            GF3FarmAudio.original(pending<=2?67:72);
        else if(pet.D==0 && frame==6 && clip==23)
            GF3FarmAudio.original(64);
        else if(pet.D==0 && frame==1 && (clip==2 || clip==22))
            GF3FarmAudio.original(75);
    }

    static void write(String name, byte[] main) throws IOException {
        main=GF3PetNames.pack(main);
        byte[] linked = new byte[main.length+28];
        System.arraycopy(main,0,linked,0,main.length);
        for (int i=0;i<4;i++) {
            int index = main.length + i*4;
            int n = STOCK[i];
            for (int b=0;b<4;b++) linked[index+b] = (byte)(n >>> (b*8));
        }
        int tail = linked.length-4;
        for(int b=0;b<8;b++) linked[tail-8+b]=(byte)(nextBonus >>> (8*b));
        linked[tail]='D';linked[tail+1]='T';linked[tail+2]='Y';linked[tail+3]=2;
        GF3KitchenQueue.write(name,linked);
    }

    static byte[] read(String name) throws IOException {
        byte[] linked = GF3KitchenQueue.read(name);
        for(int i=0;i<4;i++) STOCK[i]=0;
        selected = null;gesture=-1;pointerCaptured=false;armed=dragging=-1;
        sounding=null;lastStep=lastClip=lastFrame=-1;eatingHeard=false;
        nextBonus = 0;
        GF3PetNames.reset();
        if (linked == null || linked.length < 20) return linked;
        int tail = linked.length-4;
        if (linked[tail]!='D' || linked[tail+1]!='T' || linked[tail+2]!='Y') return linked;
        int version = linked[tail+3];
        if(version!=1 && version!=2) throw new IOException();
        if(version==2){
            if(linked.length<28) throw new IOException();
            for(int b=0;b<8;b++) nextBonus |= (long)(linked[tail-8+b]&255) << (8*b);
            if(nextBonus<0) throw new IOException();
        }
        byte[] main = new byte[linked.length-(version==2?28:20)];
        System.arraycopy(linked,0,main,0,main.length);
        for (int i=0;i<4;i++) {
            int index=main.length+i*4, n=0;
            for(int b=0;b<4;b++) n |= (linked[index+b]&255) << (b*8);
            if (n<0) throw new IOException();
            STOCK[i]=n;
        }
        return GF3PetNames.unpack(main);
    }
}
