/** Android beehive actor, using the touchscreen engine's timed woody-crop save record. */
final class GF3Hive {
    private static final int[] PRICES = {1000,2500,5000,10000,15000,20000,
                                        25000,30000,35000,40000,45000,50000};
    private GF3Hive() {}

    static int price(int[] row) {
        if (row[1] != 3022) return row[6];
        int count = f.b(0,3022) + a.gf3Stored(4,10);
        return PRICES[Math.min(Math.max(0,count),PRICES.length-1)];
    }

    static boolean flushItem(int id) {
        return (id >= 1 && id <= 26) || id == 119;
    }

    static boolean isHive(f actor) {
        return actor.q == 52 && (actor.E == 173 || actor.E == 186);
    }

    static void progressSound(f actor) {
        if(isHive(actor))GF3FarmAudio.original(79);
        else a.c(47);
    }

    static f configure(f actor) {
        if (actor != null && isHive(actor)) {
            actor.w = 3;
            actor.x = 3;
            actor.as = 9;
        }
        return actor;
    }

    static void state(f actor, int next) {
        actor.gf3TreeState(next);
        if (!isHive(actor)) return;
        actor.H();
        actor.a = null;
        if (next == 3) {
            overlay(actor, 187, 1, -1);
        } else if (next == 5) {
            actor.F = 1;
            // State 5 persists in the old tree record through a save and restart.
            f prompt = f.a(33, 0, new int[] {actor.r,actor.s,150,10,12,-63,-117,0,1});
            actor.gf3Link(prompt);
        } else if (next == 6) {
            // RMS can restore while the smoker is running. Replay the brief effect.
            overlay(actor, 13, 0, 2);
        }
    }

    private static void overlay(f actor, int sprite, int animation, int repeats) {
        e sheet = a.b[sprite];
        if (sheet != null) {
            actor.a = new k(sheet, actor.u, actor.v);
            actor.a.b(animation, repeats);
        }
    }

    static int tickState(f actor) {
        if (isHive(actor) && actor.D == 6 && (actor.a == null || actor.a.a())) {
            actor.h(2);
        }
        return actor.D;
    }

    static boolean touch(f actor) {
        if (isHive(actor) && actor.D == 5) {
            if(!GF3HoneyTutorial.requestSmoke())return true;
            a.a(4, actor);
            return true;
        }
        return actor.gf3TouchTree();
    }

    static void clean(f actor) {
        if (!isHive(actor)) {
            actor.gf3AnimalCare();
        } else if (actor.D == 5) {
            if(!GF3HoneyTutorial.canSmoke())return;
            actor.h(6);
            a.c(32);
        }
    }

    static void afterHarvest(f actor, int next) {
        actor.h(isHive(actor) ? 5 : next);
    }

    static int baseYield(f actor) {
        return isHive(actor) && actor.E == 186 ? 4 : 3;
    }

    static int yieldOrSingle(f actor, boolean tree) {
        int count=tree?baseYield(actor):1;
        if(tree && a.F==0 && isHive(actor))
            GF3HoneyTutorial.harvest(actor.J,count+(actor.a(1024)?1:0));
        return count;
    }

    static int requiredSlots(f actor) {
        return baseYield(actor) + (actor.a(1024) ? 1 : 0);
    }

    static int harvestId(f actor) {
        return isHive(actor) ? 4000 + actor.I : actor.J;
    }
}
