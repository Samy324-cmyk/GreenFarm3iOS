import java.io.IOException;

/** Optional local-neighbor predator requests from the Android mailbox. */
final class GF3VisitPredators {
    private static final long[] last = new long[10];
    private static final int[] breeds = {68,70,72,75,69,71};
    private static final int[] rect=new int[4];
    private static int requested=-1, pressed, breed, sheet, frame, which, step;
    private static f enemy,dog;
    private static k fight;

    private GF3VisitPredators() {}

    private static long now() { return System.currentTimeMillis()/1000; }

    private static boolean offered(int row) {
        if (row<0 || row>=10 || row==2) return false;
        boolean guided=a.i(299);
        if (guided && row!=0) return true;
        return a.h(9301) && now()-last[row]>=86400;
    }

    private static void capturePet(int row) {
        f pet=null;
        for (int i=0;i<breeds.length && pet==null;i++) {
            f candidate=GF3Neighbor.animal(breeds[i]);
            if (candidate!=null && candidate.a(512)) pet=candidate;
        }
        which=pet!=null && GF3Dogs.level(pet)>=3 ? row%2 : 0;
        breed=pet==null ? 68 : pet.J-2000;
        sheet=pet==null ? -1 : pet.E;
        frame=pet==null ? -1 : pet.F;
    }

    private static void displayOffer() {
        short[][] rows=a.controls[17];
        rows[52][6]=(short)(76+which);
        for(int i=51;i<=57;i++) {
            short[] item=rows[i];
            if(item[0]==205) {
                item[10]=1;
                a.a(17,item,0,0,i);
                item[10]=0;
            } else {
                item[15]=1;
                a.a(i==53?GF3VisitText.offer:i==56?GF3VisitText.no:GF3VisitText.yes,17,i,0,0);
                item[15]=0;
            }
        }
    }

    private static int button(int x,int y) {
        for(int i=54;i<=55;i++) {
            short[] item=a.controls[17][i];
            e art=a.assets[item[5]];
            if(art==null) continue;
            art.a(item[6],0,rect,0);
            int left=item[2]+rect[0],top=item[3]+rect[1];
            if(x>=left && x<left+rect[2] && y>=top && y<top+rect[3])
                return i==55 ? 1 : 2;
        }
        return 0;
    }

    static boolean detail(int phase) {
        int row=a.eS;
        if (phase==0) { pressed=0; requested=-1; capturePet(row); }
        boolean offer=offered(row);
        if (offer && phase==2) {
            int hit=button(g.ac,g.ad);
            if (g.ab==1) pressed=hit;
            if (g.ab==2 && pressed!=0) {
                int previous=pressed;
                pressed=0;
                if (hit==previous) {
                    a.c(61);
                    if (hit==1) {
                        requested=row;
                        a.cQ();
                    } else {
                        last[row]=now();
                        a.c(true);
                        a.cO();
                    }
                }
                return true;
            }
            if (pressed!=0 || (g.ab!=0 && g.ac>=185 && g.ac<722 && g.ad>=308 && g.ad<448))
                return true;
        }
        boolean handled=a.gf3VisitDetail(phase);
        if (phase==0 || phase==1) {
            for(int i=51;i<=57;i++) {
                short[] item=a.controls[17][i];
                if(item[0]==205) {item[10]=0;item[18]=0;} else item[15]=0;
            }
        }
        if (offer && phase==3) displayOffer();
        return handled;
    }

    private static void hidden(f actor) {
        if (actor==null) return;
        actor.l(8|512);
        actor.r=actor.s=actor.A=actor.B=0;
        GF3Neighbor.hold(actor,0,-1);
    }

    private static void reset() {
        step=0;
        enemy=dog=null;
        fight=null;
    }

    private static void enter() {
        reset();
        int row=a.F-1;
        // Harold's quest has its own original guided reveal and rewards.
        if (row==0 && a.i(299) && requested!=0) return;
        f fox=GF3Neighbor.animal(73),wolf=GF3Neighbor.animal(74);
        if (requested!=row) {
            hidden(fox); hidden(wolf); return;
        }
        requested=-1;
        enemy=which==0 ? fox : wolf;
        hidden(which==0 ? wolf : fox);
        dog=GF3Neighbor.animal(68);
        if (enemy==null || dog==null || a.c==null) {reset();return;}
        if (sheet>=0 && a.b[sheet]!=null) {
            dog.E=sheet;dog.F=frame;
            dog.a=new k(a.b[sheet],dog.u,dog.v);
            dog.i(0);
        }
        enemy.A=enemy.r;enemy.B=enemy.s;
        enemy.k(8|512);
        GF3FarmAudio.original(62);
        GF3Neighbor.hold(enemy,0,-1);
        a.c.a(enemy.r,enemy.s,0);
        step=1;
    }

    static boolean touch(f actor) {
        if (actor!=enemy || step==0 || a.F<1 || a.F>10 || a.a()!=36)
            return actor.gf3VisitPetTouch();
        if (step!=1) return true;
        if (a.e[a.F-1][5]<=0) {
            a.a(GF3VisitText.empty,7,0);
            return true;
        }
        a.c();
        a.aI(-1);
        GF3Neighbor.approach(dog,enemy);
        step=2;
        return true;
    }

    static boolean visit(int phase) {
        boolean handled=a.gf3VisitFarm(phase);
        if (phase==5) {reset();return handled;}
        if (a.F<1 || a.F>10 || a.a()!=36) return handled;
        if (phase==0) enter();
        if (phase!=2) return handled;
        if (step==2) {
            dog.L();
            if (dog.r!=enemy.r || dog.s!=enemy.s) return handled;
            fight=GF3Neighbor.startFight(dog,enemy);
            step=3;
        } else if (step==3 && fight.a()) {
            fight=null;
            dog.i(0);
            int row=a.F-1;
            last[row]=now();
            a.b(99990+row,1,24);
            a.b(2999,1,43);
            int affinity=GF3VisitText.rewards[(breed-68)*4+which];
            int xp=GF3VisitText.rewards[(breed-68)*4+2+which];
            a.n(row,a.d[25]*affinity);
            if (xp>0) f.a(47,2,new int[]{0,0,14}).a(dog.r,dog.s,37,1000,false,xp);
            GF3Neighbor.hold(enemy,12,3);
            step=4;
        } else if (step==4 && enemy.a.a()) {
            hidden(enemy);
            a.c(true);
            step=5;
        }
        return handled;
    }

    static void write(String name,byte[] main) throws IOException {
        byte[] linked=new byte[main.length+84];
        System.arraycopy(main,0,linked,0,main.length);
        for(int row=0;row<10;row++)
            for(int b=0;b<8;b++) linked[main.length+row*8+b]=(byte)(last[row]>>>(8*b));
        int tail=linked.length-4;
        linked[tail]='P';linked[tail+1]='V';linked[tail+2]='T';linked[tail+3]=1;
        GF3DogToys.write(name,linked);
    }

    static byte[] read(String name) throws IOException {
        byte[] data=GF3DogToys.read(name);
        for(int i=0;i<10;i++) last[i]=0;
        requested=-1;reset();
        if (data==null || data.length<84) return data;
        int tail=data.length-4;
        if(data[tail]!='P' || data[tail+1]!='V' || data[tail+2]!='T' || data[tail+3]!=1) return data;
        byte[] main=new byte[data.length-84];
        System.arraycopy(data,0,main,0,main.length);
        for(int row=0;row<10;row++) {
            for(int b=0;b<8;b++) last[row]|=(data[main.length+8*row+b]&255L)<<(8*b);
            if (last[row]<0) throw new IOException();
        }
        return main;
    }
}
