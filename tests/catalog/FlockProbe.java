import java.lang.reflect.Method;

/** Verify 4.4.4 livestock eligibility through the native world, journal and trophy book. */
final class FlockProbe {
    static void check(ClassLoader loader) throws Exception {
        Class<?> game = Class.forName("a",true,loader);
        Class<?> actor = Class.forName("f",true,loader);
        Method create = MarketProbe.method(game,"a",actor,int.class,int.class);
        Method set = MarketProbe.method(actor,"k",Void.TYPE,int.class);
        Method clear = MarketProbe.method(actor,"l",Void.TYPE,int.class);
        Method count = MarketProbe.method(actor,"a",int.class,int.class,int.class,int.class,int.class);
        int base = (Integer)count.invoke(null,0,54,0,75);
        if (base >= 24) throw new AssertionError("Requires an early farm fixture");
        // A young beagle has an odd item ID. Adult shepherds have even IDs.
        Object pup = create.invoke(null,0,69), hidden = create.invoke(null,0,68);
        set.invoke(pup,512);
        set.invoke(hidden,512|8192);
        if ((Integer)count.invoke(null,0,54,0,75) != base)
            throw new AssertionError("Juvenile or hidden animal counted");
        for (int i=base; i<24; i++) set.invoke(create.invoke(null,0,68),512);
        if ((Integer)count.invoke(null,0,54,0,75) != 24)
            throw new AssertionError("Adult German shepherds missing from population");
        MarketProbe.method(game,"f",Void.TYPE,int.class,int.class,boolean.class).invoke(null,296,0,true);
        ((int[])MarketProbe.variable(game,"cb",int[].class).get(null))[0]=2;
        Method recount = MarketProbe.method(game,"l",Void.TYPE,int.class);
        recount.invoke(null,2068);
        int enc = ((int[])MarketProbe.variable(game,"bI",int[].class).get(null))[0];
        int actual = (Integer)MarketProbe.method(game,"p",int.class,int.class).invoke(null,enc);
        if (actual != 24) throw new AssertionError("Journal counted "+actual+" animals");
        clear.invoke(hidden,8192);
        recount.invoke(null,2068);
        if (!((boolean[])MarketProbe.variable(game,"j",boolean[].class).get(null))[0])
            throw new AssertionError("The Final Countdown remained at 24/25");
        System.out.println("FINAL_COUNTDOWN 24 25");

        Class<?> table = Class.forName("h",true,loader);
        Object[] tables = (Object[])MarketProbe.variable(table,"a",java.lang.reflect.Array.newInstance(table,0).getClass()).get(null);
        int[][] species = (int[][])MarketProbe.variable(table,"a",int[][].class).get(tables[0]);
        Method distinct = MarketProbe.method(game,"w",int.class);
        for (int i=0; i<species.length && (Integer)distinct.invoke(null)<32; i++) {
            if (species[i][34]!=1 && i!=68) set.invoke(create.invoke(null,0,i),512);
        }
        if ((Integer)distinct.invoke(null)!=32) throw new AssertionError("Distinct adult breeds");
        MarketProbe.method(game,"a",int.class,int.class,int.class,int.class).invoke(null,2068,1,38);
        if (!((boolean[])MarketProbe.variable(game,"d",boolean[].class).get(null))[19])
            throw new AssertionError("The Greatest Flock was not awarded");
        Method claim = MarketProbe.method(game,"T",Void.TYPE,int.class);
        int before = MarketProbe.variable(game,"cf",int.class).getInt(null);
        claim.invoke(null,19);
        if (MarketProbe.variable(game,"cf",int.class).getInt(null)-before!=50000)
            throw new AssertionError("Missing XP in reward queue");
        System.out.println("GREATEST_FLOCK 32 XP 50000");
        System.out.println("FLOCK_OK");
    }
}
