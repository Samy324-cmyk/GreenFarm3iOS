import java.io.IOException;

/** Dog toys use the farm's normal shop, action ribbon and original pet animations. */
final class GF3DogToys {
    private static final int[] STOCK = new int[4];
    private static final int[] MOOD = {2,6,4,21};
    // Rows are toys. Columns match beagle, spaniel, shepherd and dalmatian.
    private static final int[][] XP = {{3,5,6,6},{9,14,18,18},{8,12,16,16},{26,39,52,52}};
    private static final int[][] FARM_XP = {{0,0,0,0},{30,45,60,60},{20,30,40,40},{90,135,180,180}};
    private static f selected;
    private static f sounding;
    private static int lastStep=-1,lastClip=-1,lastFrame=-1;
    private static boolean eatingHeard;
    static long nextBonus;

    static int quantity(int toy) { return STOCK[toy]; }

    /** The world toy frames have no embedded touchscreen rectangles. */
    private static void hitAreas() {
        short[][] rows=a.controls[1];
        for(int item=0;item<4;item++){
            short[] row=rows[65+item];
            int id=65601+item, free=-1;
            for(int i=0;i<a.hits.length-2;i++){
                if(a.hits[i][5]==id){free=i;break;}
                if(free==-1 && a.hits[i][4]==-1 && a.hits[i][5]==-1)free=i;
            }
            if(free<0)continue;
            e sheet=row[5]>=1000?a.world[row[5]-1000]:a.assets[row[5]];
            if(sheet==null)continue;
            int scale=Math.max(50,100-Math.abs(g.K/2-row[2]));
            int frame=row[6];
            int[] box=a.hits[free];
            box[0]=row[2]+sheet.f(frame)*scale/100;
            box[1]=row[3]+sheet.g(frame)*scale/100;
            box[2]=Math.max(1,sheet.d(frame)*scale/100);
            box[3]=Math.max(1,sheet.e(frame)*scale/100);
            box[4]=0;box[5]=id;box[6]=0;box[7]=0;
        }
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
        a.a(true,1,2);
        selected = pet;
        a.aF = 0;
        a.aG = 4;
        a.aH = 2;
        for (int i=0;i<4;i++) {
            int[] row = h.a[4].rows[64+i];
            a.k[i] = row[8] <= a.f() ? row[3] : 20;
            a.l[i] = row[8] > a.f() ? 136 : row[4] + (STOCK[i] == 0 ? 1 : 0);
            a.m[i] = row[6];
            a.n[i] = 64+i;
        }
        a.B();
        hitAreas();
        pet.D = 15;
    }

    static boolean touch(f pet) {
        if (GF3Dogs.dog(pet) && !pet.a(32) && a.F == 0 &&
                (pet.D == 0 || pet.D == 1 || pet.D == 15) &&
                !pet.a(4) && !pet.a(16) && !pet.a(256)) {
            menu(pet);
            return true;
        }
        return pet.gf3PreviousPetTouch();
    }

    static void control(int event) {
        // The native wheel places its center confirmation rectangle above
        // the item under the arrow. It wins hit testing against that item.
        if(selected!=null && a.aH==2 && a.k!=null && event==65607){
            int nearest=0, distance=Integer.MAX_VALUE;
            for(int i=0;i<4;i++){
                int dx=Math.abs(a.controls[1][65+i][2]-g.K/2);
                if(dx<distance){nearest=i;distance=dx;}
            }
            event=65601+nearest;
        }
        if (selected != null && a.aH == 2 && a.k != null && event >= 65601 && event <= 65604) {
            int toy = event-65601;
            f pet = selected;
            selected = null;
            a.a(false,2,0);
            if (STOCK[toy] <= 0 || h.a[4].rows[64+toy][8] > a.f()) {
                a.sound(56);
                pet.i(0);
                return;
            }
            STOCK[toy]--;
            GF3Dogs.beginToy(pet,toy);
            pet.D = 13;
            pet.a.b(17+toy,2);
            a.b(4118,1,44);
            return;
        }
        a.gf3PreviousControl(event);
        if (selected != null && (a.k == null || a.aH != 2)) {
            selected.i(0);
            selected = null;
        }
    }

    static int tick(f pet) {
        if (!GF3Dogs.dog(pet)) return pet.q;
        GF3PetNames.farmTick(pet);
        int pending = GF3Dogs.pending(pet);
        if(a.F==0 && pet.a(512) && pet.a!=null)sound(pet,pending);
        if (pending == 0) {
            if (pet.D == 15) {
                if (selected == pet && a.k != null) {hitAreas();return 55;}
                pet.i(0);
            }
            return pet.q;
        }
        int toy = pending-1;
        if (pet.D != 13 || pet.a.aId() != 17+toy) {
            pet.D = 13;
            pet.a.b(17+toy,2);
        } else if (pet.a.a()) {
            int breed = pet.J == 2070 ? 0 : pet.J == 2072 ? 1 : pet.J == 2068 ? 2 : 3;
            GF3Dogs.finishToy(pet,XP[toy][breed],MOOD[toy]);
            int playerXP = FARM_XP[toy][breed];
            if (playerXP > 0) f.a(47,2,new int[] {0,0,14}).a(pet.r,pet.s,37,1000,false,playerXP);
            GF3DogTutorial.played();
            pet.i(0);
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
        selected = null;
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
