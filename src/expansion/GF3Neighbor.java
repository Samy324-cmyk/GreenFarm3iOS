/** Quest 9301 on Harold's locally stored farm. */
final class GF3Neighbor {
    private static final int READY = 1, WALKING = 2, FIGHTING = 3, RETREAT = 4, MESSAGE = 5, DONE = 6;
    private static final f[] found = new f[1];
    private static f fox, dog;
    private static k fight;
    private static int step;

    private GF3Neighbor() {}

    static f animal(int row) {
        for (int layer = 0; layer < 2; layer++)
            if (f.a(layer, 54, row, found, 1) == 1) return found[0];
        return null;
    }

    private static void clear() {
        fox = null;
        dog = null;
        fight = null;
        found[0] = null;
        step = 0;
    }

    static void hold(f actor, int animation, int repeats) {
        // States beyond the livestock switch are advanced by the encounter,
        // while the native sprite player continues to run on the same clock.
        actor.D = 8;
        actor.a.b(-1, 1);
        actor.a.b(animation, repeats);
    }

    private static boolean pending() {
        for (int i = 0; i < a.bD.length; i++)
            if (a.bD[i] == 9301 && a.cb[i] == 2 && !a.j[i]) return true;
        return false;
    }

    static boolean combatActor(f actor){
        return a.F==1 && (actor==dog && (step==WALKING || step==FIGHTING) ||
                actor==fox && step>=READY && step<=FIGHTING);
    }
    static void approach(f pet,f target){
        // d(II) initializes the native walking animation and world target.
        // Do not jump to a cached path node while the camera is panning.
        pet.d(target.r,target.s);
        pet.D=9;
    }
    static boolean advance(f pet,f target){
        if(pet==null || target==null)return false;
        int ox=pet.r,oy=pet.s;
        pet.A=target.r;pet.B=target.s;
        pet.L();
        // Old saves can contain a zero-speed or exhausted path. Recover
        // by advancing a few world units, never by moving the camera.
        if(pet.r==ox && pet.s==oy){
            int dx=target.r-ox,dy=target.s-oy;
            pet.r+=Math.max(-4,Math.min(4,dx));
            pet.s+=Math.max(-4,Math.min(4,dy));
        }
        if(Math.abs(pet.r-target.r)<=4 && Math.abs(pet.s-target.s)<=4){
            pet.r=pet.A=target.r;pet.s=pet.B=target.s;return true;
        }
        return false;
    }
    static boolean advanceFight(f pet,k effect){
        if(effect==null || pet==null)return true;
        if(effect.a())return true;
        effect.a(pet.u,pet.v-50);
        effect.d(a.B);
        effect.c(Math.max(1,Math.min(100,g.N)));
        return effect.a();
    }
    static void finishFight(f pet){
        if(pet==null)return;
        pet.b=null;pet.A=pet.r;pet.B=pet.s;
        if(pet.a!=null)pet.i(0);
    }

    static k startFight(f dog, f enemy) {
        hold(dog, 21, 1);
        hold(enemy, 15, -1);
        k effect = new k(a.b[13], dog.u, dog.v);
        effect.b(enemy.J==2074?4:3, 5);
        dog.b = effect;
        dog.au = dog.h;
        dog.av = dog.i;
        a.c(124);
        return effect;
    }

    static boolean touch(f actor) {
        if(a.F==1 && actor==dog && (step==WALKING || step==FIGHTING))return true;
        if (actor != fox || a.F != 1 || a.a() != 36 || step == 0)
            return actor.gf3PetTouch();
        if (step == READY) {
            a.c();
            a.aI(-1);
            // Android s1.j0 moves distant attacking pets to the last two
            // path nodes before animating the final approach. Short paths
            // use the engine's 90-percent position adjustment.
            approach(dog, fox);
            step = WALKING;
        }
        return true;
    }

    static boolean visit(int event) {
        boolean handled = a.gf3Visit(event);
        if (event == 5) {
            clear();
            return handled;
        }
        if (event != 2 || a.F != 1 || a.a() != 36) return handled;
        if (step == 0) {
            if (!pending()) return handled;
            fox = animal(73);
            dog = animal(68);
            if (fox == null || dog == null || a.c == null) return handled;
            GF3FarmAudio.original(63);
            fox.A = fox.r;
            fox.B = fox.s;
            hold(fox, 0, -1);
            a.c.a(fox.r, fox.s, 0);
            a.a(fox, 0, -100);
            step = READY;
        } else if (step == WALKING) {
            if(!advance(dog,fox))return handled;
            fight = startFight(dog,fox);
            step = FIGHTING;
        } else if(step==FIGHTING && advanceFight(dog,fight)) {
            fight=null;
            finishFight(dog);
            a.b(99990, 1, 24);
            a.b(2999, 1, 43);
            step = RETREAT;
        }
        if (step == RETREAT) {
            // Android retreat ends at the (0,0) hidden position.
            fox.r = fox.A = 0;
            fox.s = fox.B = 0;
            fox.l(8);
            a.c();
            step = MESSAGE;
            a.a(GF3NeighborText.win(), 7, 0);
        } else if (step == MESSAGE) {
            // The native dialog has returned to the neighbor farm after OK.
            step = DONE;
            a.b(2073, 1, 45);
        }
        return handled;
    }
}
