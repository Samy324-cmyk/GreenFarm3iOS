import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Arrays;

public final class CookingProbe {
    private static Class<?> engine;

    private static Field field(String name, Class<?> type) throws Exception {
        for (Field f : engine.getDeclaredFields()) {
            if (f.getName().equals(name) && f.getType() == type) {
                f.setAccessible(true);
                return f;
            }
        }
        throw new NoSuchFieldException(name);
    }

    private static Object invoke(String name, Class<?> result, int... values) throws Exception {
        Class<?>[] types = new Class<?>[values.length];
        Arrays.fill(types,int.class);
        Object[] arguments = new Object[values.length];
        for (int i=0; i<values.length; i++) arguments[i] = values[i];
        for (Method m : engine.getDeclaredMethods()) {
            if (m.getName().equals(name) && m.getReturnType() == result && Arrays.equals(types,m.getParameterTypes())) {
                m.setAccessible(true);
                return m.invoke(null,arguments);
            }
        }
        throw new NoSuchMethodException(name);
    }

    private static void expect(String name, int value) throws Exception {
        if (field(name,int.class).getInt(null) != value) throw new AssertionError(name + " expected " + value);
    }

    static void run(ClassLoader loader) throws Exception {
        engine = Class.forName("a",true,loader);
        int[] prices=(int[])field("ce",int[].class).get(null);
        if(prices.length!=34) throw new AssertionError("Missing queue expansion tiers");
        for(int slot=1;slot<=21;slot++) {
            int expected=slot<4 || slot>20?0:slot==4?25:slot==5?50:100;
            if(((Integer)invoke("m",int.class,slot))!=expected)
                throw new AssertionError("Queue price at slot "+slot);
        }
        System.out.println("QUEUE tiers=34 maximum=20");
        Class<?> kitchen = Class.forName("GF3HoneyKitchen",true,loader);
        for (boolean honey : new boolean[]{false,true,false}) {
            Method select = kitchen.getDeclaredMethod(honey ? "enter" : "leave");
            select.setAccessible(true);
            select.invoke(null);
            invoke("q",boolean.class,0);
            invoke("q",boolean.class,1);
            int[] counts=(int[])field("ah",int[].class).get(null);
            if (honey && !Arrays.equals(counts,new int[]{4,4,2})) throw new AssertionError(Arrays.toString(counts));
            if (!honey && counts[0] < 12) throw new AssertionError("Missing ordinary recipes");
            int tested=0;
            for (int page=0; page<3; page++) {
                field("d",char.class).setChar(null,(char)page);
                for (int i=0; i<counts[page]; i++) {
                    field("cF",int.class).setInt(null,i);
                    invoke("gt",void.class);
                    int id=field("cN",int.class).getInt(null);
                    if (honey) {
                        expect("cN",6083+tested);
                        expect("cG",121+tested);
                    } else if (id < 6000 || id >= 6083) throw new AssertionError("Ordinary page contained "+ id);
                    tested++;
                }
            }
            System.out.println("KITCHEN " + (honey?"honey":"ordinary") + " recipes=" + tested);
        }
        for (int product : new int[]{36,121,130}) {
            int expected=product+(product>=121?10:1);
            int before=(Integer)invoke("g",int.class,0,expected);
            invoke("gf3AwardStarred",void.class,product);
            int after=(Integer)invoke("g",int.class,0,expected);
            if (after!=before+1) throw new AssertionError("Wrong starred output for "+product);
        }
        System.out.println("KITCHEN starred outputs verified");
    }
}
