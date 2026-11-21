import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** Exercise the actual deed panel, debit, unlocked land flags and active quest on FreeJ2ME. */
final class AcreProbe {
    static void check(ClassLoader loader, int purchase) throws Exception {
        Class<?> game = Class.forName("a", true, loader);
        int[] prices = {1000,2000,5000,25000,100000,150000,200000,300000,400000,800000,1200000,2000000};
        Method open = MarketProbe.method(game,"fV",Void.TYPE);
        Method decode = MarketProbe.method(game,"c",Long.TYPE,Long.TYPE);
        Method setCoins = MarketProbe.method(game,"V",Void.TYPE,Integer.TYPE);
        Method readCoins = MarketProbe.method(game,"d",Integer.TYPE);
        Method buy = MarketProbe.method(game,"di",Void.TYPE);
        boolean[] unlocked = (boolean[])MarketProbe.variable(game,"a",boolean[].class).get(null);
        Field parcel = MarketProbe.variable(game,"r",Integer.TYPE), quote = MarketProbe.variable(game,"j",Long.TYPE);
        for (int n = 1; n <= prices.length; n++) {
            parcel.setInt(null,n);
            open.invoke(null);
            long cost = ((Long)decode.invoke(null,quote.getLong(null))).longValue();
            System.out.println("DEED_QUOTE " + n + " " + cost);
            if (cost != prices[n-1]) throw new AssertionError("Incorrect price for deed " + n + ": " + cost);
        }
        // Seed the chosen quest, the preceding acre and its required animals
        // and products in a disposable profile. The MIDlet owns the gating,
        // transaction and actual objective event from this point onward.
        int quest = purchase == 6 ? 153 : 290;
        int cost = prices[purchase-1];
        Method assign = MarketProbe.method(game,"f",Void.TYPE,Integer.TYPE,Integer.TYPE,Boolean.TYPE);
        assign.invoke(null,quest,0,true);
        ((int[])MarketProbe.variable(game,"cb",int[].class).get(null))[0] = 2;
        Method stock = MarketProbe.method(game,"d",Void.TYPE,Integer.TYPE,Integer.TYPE,Integer.TYPE);
        stock.invoke(null,3,purchase == 6 ? 55 : 63,purchase == 6 ? 2 : 5);
        stock.invoke(null,0,purchase == 6 ? 93 : 38,purchase == 6 ? 3 : 5);
        MarketProbe.method(game,"aa",Void.TYPE,Integer.TYPE).invoke(null,100);
        MarketProbe.method(game,"ab",Void.TYPE,Integer.TYPE).invoke(null,100);
        unlocked[purchase-1] = true;
        parcel.setInt(null,purchase);
        setCoins.invoke(null,cost-1);
        open.invoke(null);
        Field eligible = MarketProbe.variable(game,"ar",Boolean.TYPE);
        if (eligible.getBoolean(null) || unlocked[purchase] || (Integer)readCoins.invoke(null) != cost-1)
            throw new AssertionError("Underfunded deed " + purchase);
        setCoins.invoke(null,cost);
        open.invoke(null);
        if (!eligible.getBoolean(null)) throw new AssertionError("Purchase button disabled for deed " + purchase);
        buy.invoke(null);
        boolean[] objective = (boolean[])MarketProbe.variable(game,"j",boolean[].class).get(null);
        if (!unlocked[purchase] || !objective[0] || (Integer)readCoins.invoke(null) != 0)
            throw new AssertionError("Debit, unlocked land or story progress failed for deed " + purchase);
        System.out.println("DEED_ACQUIRED " + purchase + " " + cost + " QUEST " + (9000+quest));
        System.out.println("ACRES_OK");
    }
}
