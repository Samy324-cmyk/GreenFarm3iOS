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

    static void approach(f pet, f target) {
        pet.i(target.r, target.s);
        n path = pet.gf3Path();
        if (path.a() > 3) {
            int[] last = new int[] {path.a(2), path.b(2)};
            int[] world = new int[2];
            a.d(last, world);
            pet.r = world[0];
            pet.s = world[1];
        } else if (Math.abs(target.r-pet.r)>40 || Math.abs(target.s-pet.s)>40) {
            pet.r += (target.r-pet.r)*90/100;
            pet.s += (target.s-pet.s)*90/100;
        }
        pet.d(target.r,target.s);
        pet.D = 9;
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
            dog.L();
            if (dog.r != fox.r || dog.s != fox.s) return handled;
            fight = startFight(dog,fox);
            step = FIGHTING;
        } else if (step == FIGHTING && fight.a()) {
            fight = null;
            dog.i(0);
            a.b(99990, 1, 24);
            a.b(2999, 1, 43);
            hold(fox, 12, 3);
            step = RETREAT;
        } else if (step == RETREAT && fox.a.a()) {
            // Android retreat ends at the (0,0) hidden position.
            fox.r = fox.A = 0;
            fox.s = fox.B = 0;
            fox.l(8);
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
