import java.io.IOException;

/** The first fox and the player's dog in the offline level-ten quest. */
final class GF3HomePredator {
    private static final int ALERT=1, ADOPT=2, NEED_DOG=3, FEED=4, READY=5,
            WALK=6, FIGHT=7, RETREAT=8, REWARD=9, REMINDER=10,
            OPEN_MILL=11, COOKING=12, FEED_PUPPY=13, GROWN=14,
            NEED_LIVESTOCK=15, PLACE_CHICKEN=16;
    private static final int[] bounds=new int[4];
    private static int step;
    private static f fox, dog;
    private static k effect;
    private static boolean redrawMap;
    private static int redrawFrames;
    private static boolean pressed;
    private static boolean scrollFeed;
    private static boolean showingChicken;
    private static int resume;
    private static long appeared;

    private GF3HomePredator() {}

    private static f ownedDog() {
        return GF3Doghouse.resident(null);
    }

    private static int slot() {
        for(int i=0;i<a.bD.length;i++)
            if(a.bD[i]==9297 && a.cb[i]==2) return i;
        return -1;
    }

    private static boolean active(int id) {
        for(int i=0;i<a.bD.length;i++) if(a.bD[i]==id) return true;
        return false;
    }

    static int journalIcon(int slot){
        int category=a.bH[slot];
        if(category==11 && a.bD[slot]>=9297 && a.bD[slot]<=9301)return 14;
        if(category==12 && a.bD[slot]>=9302 && a.bD[slot]<=9305)return 15;
        return category-1;
    }
    private static boolean guided(int id){return id==9297 || id==9299 || id>=9302 && id<=9304;}
    private static boolean special(int id){
        for(int q:GF3HomeData.quests)if(q==id)return true;
        return false;
    }
    private static int due() {
        if(a.F!=0 || (a.C!=-1 && a.C!=10) || a.bD==null || a.cb==null)return -1;
        // Do not run two guided expansion chapters simultaneously.
        for(int i=0;i<a.bD.length;i++)
            if(guided(a.bD[i]))return -1;
        int[] chain=GF3HomeData.quests;
        for(int i=0;i<chain.length;i++){
            if(a.f()<GF3HomeData.levels[i] || a.h(chain[i]) || active(chain[i]))continue;
            if(chain[i]>=9302 && chain[i]<=9304 && (!a.h(9299) || active(9299) || active(9301)))continue;
            boolean ready=true;
            for(int dependency:GF3HomeData.prerequisites[i])if(!a.h(dependency) || active(dependency))ready=false;
            if(ready)return 297+i;
        }
        return -1;
    }
    static int ordinarySlots(){
        // Leave a fourth slot free shortly before either APK unlock.
        if((a.f()>=9 && a.f()<15 && !a.h(9299)) ||
           (a.f()>=14 && !a.h(9304)))return Math.max(1,a.k-1);
        return a.k;
    }
    static boolean schedule() {
        int next=due();
        if(next>=0)for(int i=0;i<a.k;i++)if(!a.O(i)){
            a.f(next,i,true);
            a.gf3Schedule();
            a.fE=i;
            return true;
        }
        return a.gf3Schedule();
    }
    private static void automatic(){
        if(a.C!=-1 || a.af!=-1 || a.F!=0 || a.bD==null || a.cb==null)return;
        // A queued native journal entry is status 1. Guided APK chapters
        // begin on the farm, without requiring the player to open the diary.
        for(int i=0;i<a.k;i++)if(guided(a.bD[i])){
            if(a.cb[i]==1){
                int id=a.bD[i];
                if(id>=9302 && id<=9304 && (!a.h(9299) || active(9299) || active(9301)))continue;
                a.cb[i]=2;announce(id);
            }
            return;
        }
        int next=due();
        if(next<0)return;
        int target=-1;
        for(int i=0;i<a.k;i++)if(!a.O(i)){target=i;break;}
        // Old saves may already fill all four entries. Only an untouched,
        // not-yet-accepted ordinary offer can safely be returned to the
        // normal scheduler; active objectives and unclaimed rewards stay.
        if(target<0)for(int i=a.k-1;i>=0;i--)
            if(a.cb[i]==1 && a.bD[i]>=9000 && !special(a.bD[i])){target=i;break;}
        if(target<0)return;
        a.f(next,target,true);
        if(guided(a.bD[target])){a.cb[target]=2;a.fE=target;announce(a.bD[target]);}
    }
    private static void announce(int id){
        // Use the original LATAM introduction for the two construction
        // chapters. The later honey tutorial has its own scripted dialogue.
        if(id==9302 || id==9303){
            int title=id==9302?2400:2405,body=id==9302?2402:2407;
            a.a(GF3HomeData.line(title),GF3HomeData.line(body),15,0);
            redrawMap=true;
        }
    }

    private static void message(int text) {
        a.a(GF3HomeData.line(text),7,0);
        redrawMap=true;
    }

    private static void reset() {
        step=0;
        fox=null;
        dog=null;
        effect=null;
        pressed=false;
        scrollFeed=false;
        showingChicken=false;
    }

    private static boolean threatened(f actor) {
        return actor.a(512) && !actor.a(4096) && (GF3Hive.isHive(actor) ||
               actor.q==54 && !GF3Dogs.dog(actor) && actor.J!=2073 && actor.J!=2074);
    }

    private static boolean danger() {
        return a.F==0 && ((step>0 && step<=FIGHT) || (step>=OPEN_MILL && step<=GROWN));
    }

    private static boolean livestockOnFarm() {
        int[] tile=new int[2], world=new int[2];
        // Android layer 1 is the MIDP farm's actor layer 0.
        for(f animal=f.heads[0];animal!=null;animal=animal.next) {
            if(animal.q!=54 || !animal.a(512) || animal.a(4096) || GF3Dogs.dog(animal)
                    || animal.J==2073 || animal.J==2074 || animal==a.placing) continue;
            world[0]=animal.r;world[1]=animal.s;
            a.c(world,tile);
            int left=tile[0]-(animal.w>>1), top=tile[1]-(animal.x>>1);
            int right=left+animal.w-1, bottom=top+animal.x-1;
            if(a.owned(a.region(left+1,top+1)) && a.owned(a.region(right,top+1))
                && a.owned(a.region(left+1,bottom)) && a.owned(a.region(right,bottom))) return true;
        }
        return false;
    }

    static int thief() {
        return a.F==0 && (danger() || step==RETREAT) && fox!=null ? (fox.J==2074?2:1) : 0;
    }

    private static void showAlert() {
        if(a.controls==null || a.controls[1]==null) return;
        int index=96; // Original control 37, appended to the touch HUD.
        short[] alert=a.controls[1][index];
        int kind=(step>=READY && step<=RETREAT || step==FEED_PUPPY || step==GROWN) ? thief() : 0;
        if(kind==0) {
            if(alert[10]!=0) a.showControl(1,index,false);
        } else if(alert[10]==0 || alert[7]!=kind || alert[17]<0) {
            alert[7]=(short)kind;
            a.showControl(1,index,true);
        }
    }

    static void trained() {GF3ThiefClock.startDay();}

    private static long postpone(long start,long paused,long now) {
        if(start<=0) return start;
        return start+Math.max(0L,now-Math.max(start,paused));
    }

    static int update(f actor) {
        // The stock switch follows the native animation tick. Its livestock AI
        // would replace the fox's retreat clip as soon as the clip finishes.
        if(a.F==0 && actor.q==54 && (actor.J==2073 || actor.J==2074)) {
            // The map contains both spawn markers from the start. Android's
            // animal update parks them at (0,0) until their own encounter.
            if(actor!=fox || step==0) {
                actor.r=actor.A=actor.s=actor.B=0;
                if(actor.a(8)) actor.l(8);
            }
            return 55;
        }
        if(actor.gf3ScaredAt!=0 || (danger() && threatened(actor))) {
            if(danger()) {
                if(actor.gf3ScaredAt==0) actor.gf3ScaredAt=appeared;
                return 55;
            }
            long now=System.currentTimeMillis(), since=actor.gf3ScaredAt;
            if(GF3Hive.isHive(actor)) actor.treeStart=postpone(actor.treeStart,since,now);
            else if(actor.a(32)) actor.birth=postpone(actor.birth,since/1000,now/1000);
            else actor.feedStart=postpone(actor.feedStart,since,now);
            actor.gf3ScaredAt=0;
        }
        return GF3DogToys.tick(actor);
    }

    static boolean touchTree(f actor) {
        if(danger() && threatened(actor)) {if(step<WALK) message(12327);return true;}
        return actor.gf3OtherTreeTouch();
    }

    static void write(String name,byte[] main) throws IOException {
        main=GF3ThiefClock.save(main);
        int phase=step==0?resume:step;
        if(phase==0) { GF3VisitPredators.write(name,main); return; }
        byte[] saved=new byte[main.length+13];
        System.arraycopy(main,0,saved,0,main.length);
        for(int i=0;i<8;i++) saved[main.length+i]=(byte)(appeared >>> (8*i));
        saved[main.length+8]=(byte)phase;
        saved[main.length+9]='F';saved[main.length+10]='O';saved[main.length+11]='X';saved[main.length+12]=1;
        GF3VisitPredators.write(name,saved);
    }

    static byte[] read(String name) throws IOException {
        byte[] saved=GF3VisitPredators.read(name);
        reset(); resume=0; appeared=0;
        if(saved==null || saved.length<13) return GF3ThiefClock.load(saved);
        int n=saved.length-13;
        if(saved[n+9]!='F' || saved[n+10]!='O' || saved[n+11]!='X' || saved[n+12]!=1)
            return GF3ThiefClock.load(saved);
        resume=saved[n+8]&255;
        for(int i=0;i<8;i++) appeared|=(saved[n+i]&255L)<<(8*i);
        if(resume<1 || resume>PLACE_CHICKEN || appeared<=0) throw new IOException();
        byte[] main=new byte[n];
        System.arraycopy(saved,0,main,0,n);
        return GF3ThiefClock.load(main);
    }

    private static void focus(f actor) {
        a.c.a(actor.r,actor.s,0);
        a.a(actor,0,-100);
        k.f();redrawFrames=3;
    }

    private static boolean hit(f actor) {
        k sprite=actor.a;
        if(sprite==null) return false;
        a.art[actor.E].a(bounds,sprite.animation(),sprite.frame(),0,0,sprite.flags);
        int px=g.ac-actor.u, py=g.ad-actor.v;
        return px>=bounds[0]*a.B/100 && px<=bounds[2]*a.B/100 &&
               py>=bounds[1]*a.B/100 && py<=bounds[3]*a.B/100;
    }

    private static boolean placeThief(int row) {
        fox=GF3Neighbor.animal(row);
        boolean created=fox==null;
        if(created) fox=a.gf3CreateAnimal(0,row);
        if(fox==null || fox.a==null) return false;
        if(GF3ThiefClock.row!=0) {
            GF3ThiefClock.locate(fox);
        } else if(created || fox.r==0 || fox.s==0) {
            fox.r=GF3HomeData.HOME_X;
            fox.s=GF3HomeData.HOME_Y;
        }
        fox.A=fox.r;
        fox.B=fox.s;
        fox.l(512);
        fox.k(8);
        GF3Neighbor.hold(fox,0,-1);
        return true;
    }

    static boolean touch(f actor) {
        if(danger() && threatened(actor)) {if(step<WALK) message(12327);return true;}
        if(a.F!=0 || a.a()!=17 || actor!=fox || step==0)
            return actor.gf3OtherTouch();
        if(step!=READY) return true;
        dog=ownedDog();
        if(dog==null || dog.a(32)) { message(964); return true; }
        if(GF3Dogs.happiness(dog)/3 < (fox.J==2074?3:2)) { message(979); return true; }
        step=WALK;
        a.c();
        GF3Neighbor.approach(dog,fox);
        return true;
    }

    private static void pay() {
        int[] rates=GF3HomeData.dog(dog.J);
        int level=GF3Dogs.level(dog);
        int lower=GF3Doghouse.floor();
        int enemy=fox.J==2074?1:0;
        int cost=Math.min(rates[enemy],Math.max(0,GF3Dogs.happiness(dog)-lower));
        GF3Dogs.finishToy(dog,level>0?rates[2+enemy]+(level-1)*(1+enemy):0,-cost);
        if(level>0) {
            int xp=rates[4+enemy]+(GF3Dogs.level(dog)-1)*rates[6+enemy];
            f.a(47,2,new int[]{0,0,14}).a(dog.r,dog.s,37,1000,false,xp);
        }
        a.b(2999,1,43);
    }

    static void shopCategory(int category) {
        if(a.F==0 && (step==NEED_LIVESTOCK || step==PLACE_CHICKEN)) {
            step=PLACE_CHICKEN;
            a.r(0,0);
            a.Q[0]=0;a.R[0]=0;
            a.u(1);
            showingChicken=true;
        } else if(a.F==0 && step>=ALERT && step<=NEED_DOG && ownedDog()==null) {
            a.r(0,5);
            // Android's phase 1009 waives the first card's cost. Opening
            // the ordinary pet market later still reads its full price.
            if(a.M[0]==69) {a.Q[0]=0; a.R[0]=0;}
        } else a.ad(category);
    }

    static boolean shop(int event) {
        boolean handled=a.gf3HomeShop(event);
        if(event==5) showingChicken=false;
        if(event==2 && a.F==0 && a.a()==7) {
            if(!showingChicken && (step==NEED_LIVESTOCK || step==PLACE_CHICKEN)) shopCategory(0);
            else if(step==ALERT) {step=ADOPT; message(956);}
            else if(step==ADOPT) {step=NEED_DOG; message(957);}
        }
        return handled;
    }

    static boolean mill(int event) {
        boolean handled=a.gf3HomeMill(event);
        if(event==1 && step==OPEN_MILL && a.F==0) {
            a.t(true);
            scrollFeed=true;
            step=COOKING;
        }
        if(event==2 && scrollFeed && a.dr==0 && a.scroll[1]!=null) {
            if(a.dp==0) a.av(1);
            int[] bar=a.scroll[1];
            bar[8]=Math.min(0,g.K-bar[4]-bar[6]);
            a.J(1);scrollFeed=false;
        }
        return handled;
    }

    private static void feedPrompt() {
        dog=ownedDog();
        if(dog==null) return;
        if(!dog.a(32)) {step=GROWN;message(12331);return;}
        dog.k(4);
        focus(dog);
        a.a(g.a(GF3HomeData.line(965),"%s",GF3PetNames.name(dog)),7,0);
        redrawMap=true;
        step=FEED_PUPPY;
    }

    static boolean farm(int event) {
        if(event==2 || event==3) showAlert();
        if(event==3 && redrawFrames>0 && a.F==0) {
            a.redrawObjects=true;
            redrawFrames--;
        }
        // The home screen's livestock selection skips unowned animals.
        // Use the animator's current frame bounds, including flips and zoom.
        f target=step==READY?fox:step==FEED_PUPPY || step==COOKING?dog:null;
        if(event==2 && a.F==0 && target!=null && g.ab!=0) {
            boolean inside=hit(target);
            if(g.ab==1) pressed=inside;
            if(pressed) {
                if(g.ab==2) {
                    pressed=false;
                    if(inside) {
                        if(step==COOKING && a.c(6)==0) {step=OPEN_MILL; a.a(27);}
                        else touch(target);
                    }
                }
                return true;
            }
        }
        if(target==null) pressed=false;
        if(event==2 && a.F==0 && pressed) return true;
        boolean handled=a.gf3OwnFarm(event);
        // The dialogue renders with its own clip. A camera jump made while
        // opening it can leave the circular tile cache only partially drawn.
        // Event 1 resumes the farm and restores its full viewport.
        if(event==1 && redrawMap && a.F==0 && a.a()==17) {
            k.f();
            redrawFrames=3;
            redrawMap=false;
        }
        if(event!=2 || a.F!=0 || a.a()!=17 || a.c==null) return handled;
        automatic();
        boolean chapter=slot()>=0;
        if(!chapter && !GF3ThiefClock.ready()) {
            if(step!=0 || resume!=0) {reset();resume=0;appeared=0;}
            return handled;
        }
        int row=GF3ThiefClock.row==0?73:GF3ThiefClock.row;
        if(chapter && (step==NEED_LIVESTOCK || step==PLACE_CHICKEN)) {
            if(!livestockOnFarm()) {
                if(a.placing==null) {step=PLACE_CHICKEN;a.d(0,1,true);}
                return handled;
            }
            step=0;
        }
        if(step!=0 && GF3Neighbor.animal(row)!=fox) {resume=step;reset();}
        if(step==0) {
            if(chapter && (resume==0 || resume==NEED_LIVESTOCK || resume==PLACE_CHICKEN) && !livestockOnFarm()) {
                if(appeared==0) appeared=System.currentTimeMillis();
                step=NEED_LIVESTOCK;resume=0;
                a.a(GF3HomeData.line(12320),GF3HomeData.line(12321),15,0);
                redrawMap=true;
                return handled;
            }
            if(resume==NEED_LIVESTOCK || resume==PLACE_CHICKEN) resume=0;
            if(!placeThief(row)) return handled;
            if(resume==0) GF3FarmAudio.original(62);
            if(appeared==0) appeared=System.currentTimeMillis();
            focus(fox);
            int previous=resume; resume=0;
            if(!chapter && previous>=RETREAT) {
                fox.r=fox.A=fox.s=fox.B=0;
                fox.l(8);
                reset();appeared=0;GF3ThiefClock.clearEncounter();
            } else if(!chapter) step=READY;
            else if(previous>=OPEN_MILL) {
                dog=ownedDog();
                step=dog==null?NEED_DOG:previous;
                if(step==GROWN) message(12331);
                if(step==FEED_PUPPY) feedPrompt();
            } else if(previous>=RETREAT) {
                fox.r=fox.A=fox.s=fox.B=0;
                fox.l(8);
                step=previous==REMINDER?REMINDER:REWARD;
                message(step==REMINDER?975:958);
            } else if(previous>=FEED) step=FEED;
            else if(previous>=ADOPT) step=NEED_DOG;
            else {message(955);step=ALERT;}
        } else if(step==ALERT) {
            if(ownedDog()==null) a.d(0,1,true);
            else {message(956);step=ADOPT;}
        } else if(step==ADOPT) {
            message(957);
            step=NEED_DOG;
        } else if(step==NEED_DOG) {
            dog=ownedDog();
            if(dog!=null && (dog==a.placing || GF3PetNames.naming(dog))) return handled;
            if(dog!=null && dog.a(32)) {
                focus(dog);
                message(964);
                step=OPEN_MILL;
            } else if(dog!=null) step=FEED;
        } else if(step==OPEN_MILL) {
            if(a.c(6)>0) feedPrompt();
            else a.a(27);
        } else if(step==COOKING) {
            if(a.c(6)>0) feedPrompt();
        } else if(step==FEED_PUPPY) {
            if(dog!=null && !dog.a(32)) {step=GROWN;message(12331);}
        } else if(step==FEED || step==GROWN) {
            dog=ownedDog();
            if(dog!=null && !dog.a(32)) {
                focus(fox);
                message(959);
                step=READY;
            }
        } else if(step==WALK) {
            dog.L();
            if(dog.r==fox.r && dog.s==fox.s) {
                effect=GF3Neighbor.startFight(dog,fox);
                step=FIGHT;
            }
        } else if(step==FIGHT && effect.a()) {
            effect=null;
            dog.i(0);
            GF3FarmAudio.original(76);
            pay();
            GF3Neighbor.hold(fox,12,3);
            step=RETREAT;
        } else if(step==RETREAT && fox.a.a()) {
            fox.r=fox.A=fox.s=fox.B=0;
            fox.l(8);
            if(chapter) {message(958);step=REWARD;}
            else {reset();appeared=0;GF3ThiefClock.clearEncounter();}
        } else if(step==REWARD) {
            message(975);
            step=REMINDER;
        } else if(step==REMINDER) {
            a.b(2998,1,45);
            reset();
            appeared=0;
        }
        return handled;
    }
}
