import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

/** Keeps the other kitchen's native queue available while one is on screen. */
final class GF3KitchenQueue {
    private static final int MAX = 20;
    private static final int MAGIC = 0x484B5131; // HKQ1
    private static final String[] STORES = {"gf3_honey_0", "gf3_honey_1"};
    private static GF3KitchenQueue normal, honey;
    private static boolean usingHoney;
    private static int generation;

    private int slots, count, scroll;
    private int[] ids, names, times, prices, icons, remaining;
    private long[] starts;
    private byte[] phases;
    private boolean[] starred;
    private String[] captions;

    private static GF3KitchenQueue newHoney() {
        GF3KitchenQueue q = new GF3KitchenQueue();
        q.slots = 2;
        q.ids = new int[MAX];
        q.names = new int[MAX];
        q.times = new int[MAX];
        q.starts = new long[MAX];
        q.prices = new int[MAX];
        q.icons = new int[MAX];
        q.phases = new byte[MAX];
        q.starred = new boolean[MAX];
        q.remaining = new int[MAX];
        q.captions = new String[MAX];
        return q;
    }

    private void capture() {
        slots = a.slots; count = a.count; scroll = a.scroll;
        ids = a.ids; names = a.names; times = a.times; starts = a.starts;
        prices = a.prices; icons = a.icons; phases = a.phases; starred = a.starred;
        remaining = a.remaining; captions = a.captions;
    }

    private void install() {
        a.slots = slots; a.count = count; a.scroll = scroll;
        a.ids = ids; a.names = names; a.times = times; a.starts = starts;
        a.prices = prices; a.icons = icons; a.phases = phases; a.starred = starred;
        a.remaining = remaining; a.captions = captions;
    }

    static void select(boolean useHoney) {
        if (usingHoney == useHoney) return;
        if (useHoney) {
            if (normal == null) normal = new GF3KitchenQueue();
            if (honey == null) honey = newHoney();
            normal.capture();
            honey.install();
            GF3HoneyKitchen.enter();
        } else {
            honey.capture();
            normal.install();
            GF3HoneyKitchen.leave();
        }
        usingHoney = useHoney;
    }

    static void newSession() {
        usingHoney = false;
        generation = 0;
        normal = null;
        honey = null;
        GF3HoneyKitchen.leave();
        GF3ExtractorUI.reset();
        a.gd();
    }

    static boolean openBuilding(int row) {
        if (row == 9) {
            a.a(8);
            return true;
        }
        if (row != 28) return false;
        select(true);
        a.a(11);
        return true;
    }

    static void resumeFarm() {
        select(false);
        a.C();
    }

    static void openNormal(int menu) {
        select(false);
        a.a(menu);
    }

    static String title(int ordinaryLabel) {
        // Android LATAM[12378], used only on the extractor's queue screen.
        return usingHoney ? "Cocinando miel" : g.c(ordinaryLabel);
    }

    static int slotPrice(int[] prices, int nextSlot) {
        if (nextSlot < 4 || nextSlot > MAX) return 0;
        // Android table 31 groups slots 4–10 first, then 11–20 by building.
        // The mill and kitchen columns have the same prices in release 4.4.4.
        return prices[nextSlot<=10 ? nextSlot-4 : nextSlot+3];
    }

    static boolean screen(int phase) {
        return GF3ExtractorUI.screen(phase,usingHoney,a.drawerOpen);
    }

    static boolean extract(int[] recipe) {
        if (!a.changeStock(0, recipe[6], -recipe[7])) return false;
        if (!a.changeStock(0, recipe[18], 1)) {
            a.changeStock(0, recipe[6], recipe[7]);
            return false;
        }
        a.objective(recipe[1],1,25,false);
        a.order(recipe[1],1,25);
        GF3HoneyTutorial.extracted();
        return true;
    }

    static void openQuest(int recipe) {
        int[][] recipes = h.tables[7].rows;
        boolean honeyRecipe = false;
        for (int i = 0; i < recipes.length; i++) {
            if (recipes[i][1] == recipe) {
                honeyRecipe = recipes[i][4] > 3;
                break;
            }
        }
        if (honeyRecipe) {
            f[] actors = new f[1];
            f.a(0, 50, 28, actors, 1);
            if (actors[0] == null) return;
        }
        select(honeyRecipe);
        a.p(11);
    }

    // The native serializer must always emit the regular kitchen's queue.
    static int normalSlots() { return usingHoney ? normal.slots : a.slots; }
    static byte[] normalPhases() { return usingHoney ? normal.phases : a.phases; }
    static long[] normalStarts() { return usingHoney ? normal.starts : a.starts; }
    static int[] normalTimes() { return usingHoney ? normal.times : a.times; }
    static int[] normalIds() { return usingHoney ? normal.ids : a.ids; }
    static boolean[] normalStarred() { return usingHoney ? normal.starred : a.starred; }

    private byte[] encode(int version) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(bytes);
        out.writeInt(MAGIC);
        out.writeInt(version);
        out.writeByte(slots);
        out.writeByte(count);
        for (int i = 0; i < count; i++) {
            out.writeInt(ids[i]);
            out.writeLong(starts[i]);
            out.writeInt(times[i]);
            out.writeBoolean(starred[i]);
            out.writeByte(phases[i]);
        }
        return bytes.toByteArray();
    }

    private static GF3KitchenQueue decode(byte[] payload, int version) throws IOException {
        if (payload == null) throw new IOException();
        DataInputStream in = new DataInputStream(new ByteArrayInputStream(payload));
        if (in.readInt() != MAGIC || in.readInt() != version) throw new IOException();
        GF3KitchenQueue q = newHoney();
        q.slots = in.readUnsignedByte();
        q.count = in.readUnsignedByte();
        if (q.slots < 2 || q.slots > MAX || q.count > q.slots ||
                payload.length != 10 + 18 * q.count) throw new IOException();
        int[][] recipes = h.tables[7].rows;
        for (int i = 0; i < q.count; i++) {
            q.ids[i] = in.readInt();
            q.starts[i] = in.readLong();
            q.times[i] = in.readInt();
            q.starred[i] = in.readBoolean();
            q.phases[i] = in.readByte();
            int row = 0;
            while (row < recipes.length && recipes[row][1] != q.ids[i]) row++;
            if (row == recipes.length || recipes[row][4] <= 3 || q.times[i] < 0)
                throw new IOException();
            q.names[i] = recipes[row][2];
            q.prices[i] = recipes[row][15];
            q.icons[i] = a.productIcons[recipes[row][18]];
        }
        return q;
    }

    private static int word(byte[] bytes, int pos) {
        return (bytes[pos] << 24) | ((bytes[pos+1] & 255) << 16) |
                ((bytes[pos+2] & 255) << 8) | (bytes[pos+3] & 255);
    }

    private static void word(byte[] bytes, int pos, int value) {
        for (int i = 3; i >= 0; i--) {
            bytes[pos+i] = (byte)value;
            value >>>= 8;
        }
    }

    /** Attach a generation pointer outside the inventory migration footer.
     * The previous side record stays valid until the main RMS write commits. */
    static void write(String name, byte[] main) throws IOException {
        if (usingHoney) honey.capture();
        if (honey == null || (honey.slots == 2 && honey.count == 0)) {
            g.a(name, main);
            return;
        }
        int next = generation + 1;
        g.a(STORES[next & 1], honey.encode(next));
        byte[] linked = new byte[main.length+8];
        System.arraycopy(main, 0, linked, 0, main.length);
        word(linked, main.length, MAGIC);
        word(linked, main.length+4, next);
        g.a(name, linked);
        generation = next;
    }

    static byte[] read(String name) throws IOException {
        byte[] main = g.a(name);
        select(false);
        honey = null;
        generation = 0;
        if (main == null || main.length < 8 || word(main, main.length-8) != MAGIC)
            return main;
        generation = word(main, main.length-4);
        honey = decode(g.a(STORES[generation & 1]), generation);
        byte[] legacy = new byte[main.length-8];
        System.arraycopy(main, 0, legacy, 0, legacy.length);
        return legacy;
    }
}
