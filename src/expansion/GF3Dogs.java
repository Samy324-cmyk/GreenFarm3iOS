/** Offline canine feeding and growth from Android's actor/animal state machine. */
final class GF3Dogs {
    private GF3Dogs() {}
    private static final int[] LEVEL_XP = {10,27,100,1000,5000,10000,15000,20000,30000,50000};
    private static final int[] LEVEL_BILLS = {1,3,7,10,20,35,65,90,150,300};
    private static final long TAG = 0x4746334400000000L;
    static int nextXp(int current) {return LEVEL_XP[current];}
    static int nextBills(int current) {return LEVEL_BILLS[current];}

    static boolean dog(f x) {
        return x.q == 54 && (x.J >= 2068 && x.J <= 2072 || x.J == 2075);
    }

    private static boolean puppy(f x) {
        return dog(x) && x.a(32);
    }

    static boolean touch(f x) {
        if (puppy(x) && x.a(4) && x.f == 0) x.f = 1;
        return x.gf3AnimalTouch();
    }

    static void care(f x) {
        if (puppy(x) && x.a(4)) {
            // The stock livestock handler increments its milestone counter when
            // feeding. Puppies use this interaction to mature after eating.
            int goal = x.c, count = x.d;
            x.c = Integer.MAX_VALUE;
            x.gf3NativeCare();
            x.c = goal;
            x.d = count;
        } else {
            x.gf3NativeCare();
        }
    }

    static void age(f x) {
        if (!puppy(x)) x.gf3Mature();
    }

    static int growthEvent(int id, int quantity, int action) {
        if (id == 2069 || id == 2071) return 0;
        return a.b(id,quantity,action);
    }

    // The original serializes e:J as the birth timestamp while the puppy
    // flag is set. Adult dogs never use the juvenile timer. Keeping the
    // packed stats here follows the same individual through moves and saves.
    private static boolean stored(f x) {
        return !puppy(x) && (x.e & 0xfffffff800000000L) == (TAG & 0xfffffff800000000L);
    }

    static int xp(f x) {
        if (stored(x)) return (int)(x.e & 65535L);
        return (x.J == 2068 || x.J == 2075) ? 10 : (x.J == 2069 || x.J == 2071 ? 1 : 0);
    }

    static int happiness(f x) {
        if (stored(x)) return (int)((x.e >>> 16) & 255);
        return x.J == 2068 || x.J == 2075 ? 9 : 6;
    }

    static int level(f x) {
        if (stored(x)) return Math.min(10,(int)((x.e >>> 24) & 255));
        return x.J==2068 || x.J==2075?1:0;
    }

    static void floor(f pet,int floor) {
        if(!puppy(pet) && happiness(pet)<floor)
            setStats(pet,xp(pet),floor,level(pet));
    }

    private static void setStats(f x, int exp, int happy, int level) {
        x.e = TAG | ((long)level << 24) | ((long)happy << 16) | (long)exp;
    }

    private static void rewardLevel(f pet,int before,int after) {
        if(after<=before || before<0 || before>=LEVEL_BILLS.length || a.F!=0)return;
        GF3FarmAudio.original(11);
        f.a(47,2,new int[]{0,0,14}).a(pet.r-50,pet.s-20,6,1000,false,LEVEL_BILLS[before]);
    }

    static int pending(f x) {
        return stored(x) ? (int)((x.e >>> 32) & 7L) ^ 4 : 0;
    }

    static void beginToy(f x, int toy) {
        setStats(x,xp(x),happiness(x),level(x));
        x.e ^= (long)(toy+1) << 32;
    }

    static void cancelToy(f x){setStats(x,xp(x),happiness(x),level(x));}
    static void finishToy(f x, int expAdded, int moodAdded) {
        int oldLevel=level(x);
        int total = Math.min(50000, xp(x) + expAdded);
        int moodMax = x.J == 2068 ? 18 : x.J == 2070 ? 9 : x.J == 2072 ? 12 : 21;
        int newLevel = 0;
        while (newLevel < LEVEL_XP.length && total >= LEVEL_XP[newLevel]) newLevel++;
        setStats(x,total,Math.min(moodMax,happiness(x)+moodAdded),newLevel);
        rewardLevel(x,oldLevel,newLevel);
    }

    static void finishedEating(f x, int next) {
        if (dog(x)) {
            int oldLevel=level(x);
            int exp = Math.min(50000, xp(x) + 10);
            int happy = happiness(x);
            if (puppy(x)) x.gf3Mature();
            int currentLevel = 0;
            while (currentLevel < LEVEL_XP.length && exp >= LEVEL_XP[currentLevel]) currentLevel++;
            setStats(x,exp,happy,currentLevel);
            rewardLevel(x,oldLevel,currentLevel);
        }
        x.i(next);
    }

    static void finishedCleaning(f x, int next) {
        if (dog(x) && !puppy(x)) {
            int limit = x.J == 2068 ? 18 : x.J == 2070 ? 9 : x.J == 2072 ? 12 : 21;
            setStats(x,xp(x),Math.min(limit,happiness(x)+1),level(x));
        }
        x.i(next);
    }

    static void productionDue(f x, int flag) {
        if (dog(x)) {
            x.r();
            x.i(2);
        } else {
            x.j(flag);
        }
    }
}
