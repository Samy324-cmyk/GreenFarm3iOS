import java.lang.reflect.Array;
import java.lang.reflect.Method;
import org.recompile.mobile.MobilePlatform;

/** Touch Walt's gauge, play the cutscene and inspect the plants immediately after landing. */
final class PlaneProbe {
    private static Class<?> game,actor;
    private static int get(Class<?> type,Object instance,String name) throws Exception {
        return (Integer)MarketProbe.field(type,instance,name,int.class);
    }
    private static Method method(Class<?> type,String name,Class<?> result,Class<?>... args) {
        return MarketProbe.method(type,name,result,args);
    }
    static void check(ClassLoader loader) throws Exception {
        game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);
        Class<?> monitor=Class.forName("GF3Presentation",false,loader);
        Class<?> plane=Class.forName("GF3CropDuster",true,loader);
        Object empty=null,field=null,tree;
        synchronized(monitor) {
            method(game,"X",void.class,int.class).invoke(null,5);
            method(game,"f",void.class,int.class,int.class,boolean.class).invoke(null,23,0,true);
            ((int[])MarketProbe.field(game,null,"cb",int[].class))[0]=2;
            method(game,"a",void.class,boolean.class,boolean.class,boolean.class).invoke(null,true,false,false);
            Object[] heads=(Object[])MarketProbe.field(actor,null,"a",Array.newInstance(actor,0).getClass());
            for(Object obj=heads[0];obj!=null;obj=MarketProbe.field(actor,obj,"a",actor)) {
                if(get(actor,obj,"q")!=49) continue;
                if(empty==null) empty=obj;else {field=obj;break;}
            }
            if(empty==null || field==null) throw new AssertionError("Expected two farm plots");
            method(actor,"g",void.class,int.class).invoke(empty,1);
            method(actor,"g",void.class,int.class).invoke(field,1);
            method(game,"N",void.class,int.class).invoke(null,4);
            method(actor,"f",void.class,int.class).invoke(field,4);
            method(actor,"g",void.class,int.class).invoke(field,3);
            tree=method(game,"a",actor,int.class,int.class).invoke(null,2,12);
            method(actor,"h",void.class,int.class).invoke(tree,2);
            MarketProbe.variable(game,"bT",int.class).setInt(null,359);
        }
        short[] control=((short[][][])MarketProbe.field(game,null,"a",short[][][].class))[1][28];
        if(control[10]==0 || control[18]==0) throw new AssertionError("Missing aircraft gauge");
        int x=479-control[3],y=control[2];
        MobilePlatform.pointerPressed(x,y);Thread.sleep(110);MobilePlatform.pointerReleased(x,y);Thread.sleep(350);
        if(get(game,null,"bT")!=359 || (Integer)method(game,"a",int.class).invoke(null)!=17)
            throw new AssertionError("The aircraft launched before the tank was full");
        method(game,"i",void.class,int.class).invoke(null,1);
        if(get(game,null,"bT")!=360) throw new AssertionError("Refueling failed");
        Thread.sleep(850);
        MobilePlatform.pointerPressed(x,y);Thread.sleep(110);MobilePlatform.pointerReleased(x,y);
        long end=System.currentTimeMillis()+21000;
        boolean inFlight=false;
        do {
            if((Boolean)MarketProbe.field(plane,null,"flying",boolean.class)) {
                if(get(game,null,"bT")!=360) throw new AssertionError("Fuel consumed during the flight");
                inFlight=true;
            } else if(inFlight) break;
            Thread.sleep(25);
        } while(System.currentTimeMillis()<end);
        int[] statuses=(int[])MarketProbe.field(game,null,"cb",int[].class);
        // The native event dispatcher plays its objective notification after
        // the field update and before marking both goals complete.
        long notice=System.currentTimeMillis()+5000;
        while(statuses[0]!=3 && System.currentTimeMillis()<notice) Thread.sleep(40);
        int result=statuses[0];
        if(!inFlight || get(game,null,"bT")!=0 || get(actor,empty,"D")!=1 ||
                get(actor,field,"D")!=5 || get(actor,tree,"D")!=3 || result!=3)
            throw new AssertionError("Flight="+inFlight+" fuel="+get(game,null,"bT")+" empty="+get(actor,empty,"D")+
                " planted="+get(actor,field,"D")+" tree="+get(actor,tree,"D")+" quest="+result+
                " screen="+method(game,"a",int.class).invoke(null));
        System.out.println("PLANE_OK incompleteFuel=359 fullFuel=360 afterLanding=0 empty=1 crop=5 tree=3 quest=9023");
    }
}
