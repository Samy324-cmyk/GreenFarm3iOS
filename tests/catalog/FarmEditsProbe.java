import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;
import org.recompile.mobile.PlatformImage;

/** Exercise the HUD's sell/store controls, the Android warnings and the RMS farm. */
final class FarmEditsProbe {
    private static Class<?> game,actor;
    private static Method method(Class<?> from,String name,Class<?> result,Class<?>...types) {
        return MarketProbe.method(from,name,result,types);
    }
    private static int field(Object obj,String name)throws Exception {
        return MarketProbe.variable(obj==null?game:actor,name,int.class).getInt(obj);
    }
    private static Object selected()throws Exception {return MarketProbe.field(game,null,"a",actor);}
    private static int screen()throws Exception {return (Integer)method(game,"a",int.class).invoke(null);}
    private static void waitScreen(int expected)throws Exception {
        long until=System.currentTimeMillis()+7000;
        while(screen()!=expected && System.currentTimeMillis()<until)Thread.sleep(80);
        if(screen()!=expected)throw new AssertionError("Farm editor screen "+screen()+" expected "+expected);
        Thread.sleep(500);
    }
    private static int count(int id)throws Exception {
        return (Integer)method(actor,"b",int.class,int.class,int.class).invoke(null,0,id);
    }
    private static int stock(int index)throws Exception {
        return (Integer)method(game,"g",int.class,int.class,int.class).invoke(null,4,index);
    }
    private static Object find(int id)throws Exception {
        Object list=MarketProbe.field(actor,null,"a",Array.newInstance(actor,0).getClass());
        Object obj=Array.get(list,0);
        while(obj!=null && field(obj,"J")!=id)obj=MarketProbe.field(actor,obj,"a",actor);
        return obj;
    }
    private static Object place(int type,int row)throws Exception {
        Object item=method(game,"a",actor,int.class,int.class).invoke(null,type,row);
        // Separate the controlled actors before the native placement search.
        // Otherwise two freshly constructed actors can share a pick rectangle.
        int[] cell=new int[2];
        int x=type==0?2250:row==23?2250:2106;
        int y=row==23?999:819;
        if(!(Boolean)method(game,"a",boolean.class,actor,int[].class,int.class,int.class)
                .invoke(null,item,cell,x,y))
            throw new AssertionError("Cannot place editor fixture "+row);
        method(actor,"k",void.class,int.class).invoke(item,8);
        method(actor,"k",void.class,int.class).invoke(item,512);
        System.out.println("FARM_EDIT fixture "+field(item,"J")+" at "+field(item,"r")+","+field(item,"s"));
        return item;
    }
    private static void tap(int x,int y)throws Exception {
        MobilePlatform.pointerPressed(x,y);Thread.sleep(110);MobilePlatform.pointerReleased(x,y);Thread.sleep(450);
    }
    private static void button(int event)throws Exception {
        int[][] hits=(int[][])MarketProbe.field(game,null,"i",int[][].class);
        for(int[] r:hits)if(r[5]==event){
            System.out.println("FARM_EDIT tap="+event+" x="+(r[0]+r[2]/2)+" y="+(r[1]+r[3]/2));
            tap(479-r[1]-r[3]/2,r[0]+r[2]/2);return;
        }
        throw new AssertionError("Missing farm edit control "+event);
    }
    private static void select(Object item)throws Exception {
        waitScreen(17);
        Object camera=MarketProbe.field(game,null,"c",actor);
        method(actor,"a",void.class,int.class,int.class,int.class).invoke(camera,field(item,"r"),field(item,"s"),0);
        Thread.sleep(600);
        for(int attempt=0;attempt<3;attempt++) {
            int[] point=pick(item);
            MobilePlatform.pointerPressed(479-point[1],point[0]);
            long until=System.currentTimeMillis()+1700;
            while(selected()!=item && System.currentTimeMillis()<until)Thread.sleep(50);
            MobilePlatform.pointerReleased(479-point[1],point[0]);Thread.sleep(350);
            if(selected()==item && field(null,"d")==3)return;
            System.out.println("FARM_EDIT missed actor "+field(item,"J")+" at "+point[0]+","+point[1]+" mode="+field(null,"d")+
                    " screen="+screen()+" selected="+(selected()==null?"none":field(selected(),"J")));
            if(screen()!=17)break;
        }
        throw new AssertionError("Could not select the actor from the farm "+field(item,"J"));
    }
    private static int[] pick(Object item)throws Exception {
        // The native hit test is a pure query of g.ac/g.ad. Probe a patch
        // (there may be moving animals in front) and restore both coordinates
        // before returning control to the renderer or sending the actual press.
        ClassLoader loader=game.getClassLoader();
        Class<?> canvas=Class.forName("g",false,loader);
        Field x=MarketProbe.variable(canvas,"ac",int.class),y=MarketProbe.variable(canvas,"ad",int.class);
        Method hit=method(actor,"b",actor);
        synchronized(Class.forName("GF3Presentation",false,loader)){
            int oldX=x.getInt(null),oldY=y.getInt(null);
            try{
                for(int dy:new int[]{-32,-15,-50,-65,0,12,-80})for(int dx:new int[]{0,18,-18,35,-35,50,-50}){
                    int u=field(item,"u")+dx,v=field(item,"v")+dy;
                    x.setInt(null,u);y.setInt(null,v);
                    if(hit.invoke(null)==item)return new int[]{u,v};
                }
            }finally{x.setInt(null,oldX);y.setInt(null,oldY);}
        }
        throw new AssertionError("No visible part of actor "+field(item,"J"));
    }
    private static void warning(Object item,int action,String title,String phrase)throws Exception {
        select(item);button(action);waitScreen(19);
        String heading=(String)MarketProbe.field(game,null,"o",String.class);
        String body=(String)MarketProbe.field(game,null,"p",String.class);
        if(!heading.equals(title)||!body.contains(phrase))throw new AssertionError("Unexpected removal dialog "+heading+" "+body);
        if(count(field(item,"J"))!=1)throw new AssertionError("Protected actor was removed");
        PlatformImage lcd=Mobile.getPlatform().getLcdFrontbuffer();
        BufferedImage shot=new BufferedImage(480,800,BufferedImage.TYPE_INT_RGB);
        synchronized(lcd){shot.setRGB(0,0,480,800,lcd.getDataBuffer(),0,480);}
        ImageIO.write(shot,"png",new File("aviso-"+field(item,"J")+"-"+action+".png"));
        System.out.println("FARM_EDIT_PROTECTED id="+field(item,"J")+" action="+action+" title="+heading);
        button(4<<16|11);waitScreen(17);
    }
    static void check(ClassLoader loader,boolean reload)throws Exception {
        game=Class.forName("a",true,loader);actor=Class.forName("f",true,loader);
        waitScreen(17);
        if(reload){
            if(count(3022)!=1 || count(3023)!=0 || count(2070)!=1 || stock(11)!=1)
                throw new AssertionError("Farm objects changed after reload");
            warning(find(3022),65611,"¡ALERTA DE COLMENA!","al menos una colmena");
            System.out.println("EDITS-RELOAD_OK hives=1 storedHives=1 dogs=1");return;
        }
        if(count(3022)+count(3023)+count(2070)!=0 || stock(11)!=0)
            throw new AssertionError("Expected empty level-15 test prerequisites");
        Object hive=place(2,22), dog=place(0,70);
        // A newly created beagle has hidden edit buttons. Exercise the second
        // Android guard with the restored actor flags used by s1.I0 and O0.
        method(actor,"k",void.class,int.class).invoke(dog,64|128);
        for(int action:new int[]{65610,65611}){
            warning(hive,action,"¡ALERTA DE COLMENA!","al menos una colmena");
            warning(dog,action,"¡ALERTA CANINA!","al menos un perro");
        }
        Object extra=place(2,23);
        select(extra);button(65611);waitScreen(17);
        if(count(3022)!=1 || count(3023)!=0 || stock(11)!=1 || count(2070)!=1)
            throw new AssertionError("Storing the second hive did not preserve the first");
        System.out.println("EDITS_OK protectedActions=4 secondHiveStored=true");
    }
}
