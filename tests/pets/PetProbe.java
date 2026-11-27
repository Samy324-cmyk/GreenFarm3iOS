import java.lang.reflect.Method;

/** Exercise the shop and read the active pet from FreeJ2ME's game class loader. */
final class PetProbe {
    private PetProbe() {}

    static void ready(ClassLoader loader,int screen) throws Exception {
        Class<?> game=Class.forName("a",false,loader);
        Method current=MarketProbe.method(game,"a",int.class);
        java.lang.reflect.Field states=MarketProbe.variable(game,"a",int[].class);
        long deadline=System.currentTimeMillis()+45000L;
        while(System.currentTimeMillis()<deadline) {
            if(states.get(null)!=null && ((Integer)current.invoke(null)).intValue()==screen){
                Thread.sleep(180);return;
            }
            Thread.sleep(120);
        }
        throw new AssertionError("Expected screen "+screen+", found "+current.invoke(null));
    }

    static void collar(ClassLoader loader) throws Exception {
        Class<?> game=Class.forName("a",false,loader),actor=Class.forName("f",false,loader);
        MarketProbe.method(game,"X",void.class,int.class).invoke(null,15);
        MarketProbe.method(game,"W",void.class,int.class).invoke(null,60);
        Object dog=MarketProbe.method(game,"a",actor,int.class,int.class).invoke(null,0,70);
        int[] position=new int[2];
        if(!(Boolean)MarketProbe.method(game,"a",boolean.class,actor,int[].class)
                .invoke(null,dog,position))throw new AssertionError("No available farm tile");
        Method setFlag=MarketProbe.method(actor,"k",void.class,int.class);
        setFlag.invoke(dog,8);
        setFlag.invoke(dog,512);
        MarketProbe.method(game,"r",void.class,int.class,int.class).invoke(null,4,0);
        int[] rows=(int[])MarketProbe.field(game,null,"M",int[].class);
        int slot=0;
        while(slot<rows.length && rows[slot]!=68)slot++;
        if(slot==rows.length)throw new AssertionError("Missing dog collar");
        int offset=(Integer)MarketProbe.field(game,null,"ct",int.class);
        MarketProbe.method(game,"af",void.class,int.class).invoke(null,slot-offset);
        if(!MarketProbe.method(game,"e",int.class).invoke(null).equals(40))
            throw new AssertionError("Wrong price for collar");
    }

    static void check(ClassLoader loader) throws Exception {
        Class<?> game=Class.forName("a",false,loader),actor=Class.forName("f",false,loader);
        Class<?> house=Class.forName("GF3Doghouse",false,loader),names=Class.forName("GF3PetNames",false,loader);
        Object dog=MarketProbe.method(house,"resident",actor,actor).invoke(null,new Object[]{null});
        if(dog==null || !MarketProbe.field(actor,dog,"J",int.class).equals(2070))
            throw new AssertionError("Resident beagle missing");
        String name=(String)MarketProbe.method(names,"name",String.class,actor).invoke(null,dog);
        if(!"Sol".equals(name) || !MarketProbe.method(game,"e",int.class).invoke(null).equals(40))
            throw new AssertionError("Expected Sol and 40 bills, got "+name);
        System.out.println("PET_NAME_OK");
    }
}
