import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** Inspect objects and shop rows from the live FreeJ2ME game class loader. */
final class MarketProbe {
    static Method method(Class<?> c,String name,Class<?> result,Class<?>... args) {
        for (Method m:c.getDeclaredMethods()) {
            if (m.getName().equals(name) && m.getReturnType()==result &&
                java.util.Arrays.equals(m.getParameterTypes(),args)) {
                m.setAccessible(true);
                return m;
            }
        }
        throw new AssertionError(name);
    }

    static Field variable(Class<?> c, String name, Class<?> type) throws Exception {
        for (Field f : c.getDeclaredFields()) {
            if (f.getName().equals(name) && f.getType() == type) {
                f.setAccessible(true);
                return f;
            }
        }
        throw new NoSuchFieldException(name);
    }

    static Object field(Class<?> c,Object target,String name,Class<?> type) throws Exception {
        return variable(c,name,type).get(target);
    }

    static void check(ClassLoader loader) throws Exception {
        // These UI operations normally execute together inside Canvas.paint.
        // A test issuing them from stdin must not interleave shop cleanup or
        // a music-pack read between requesting, loading and drawing the icons.
        synchronized(Class.forName("GF3Presentation",false,loader)) {
            checkWithinFrame(loader);
        }
    }
    private static void checkWeekly(ClassLoader loader,Class<?> game) throws Exception {
        Class<?> offers=Class.forName("GF3MarketFront",true,loader);
        Method week=method(offers,"week",int.class,int.class,int.class,int.class);
        int friday=(Integer)week.invoke(null,2026,11,27);
        if((Integer)week.invoke(null,2026,11,28)!=friday+1 ||
           (Integer)week.invoke(null,2026,12,4)!=friday+1)
            throw new AssertionError("Saturday rollover");
        Method open=method(offers,"open",void.class,int.class);
        Field count=variable(offers,"offerCount",int.class),stamp=variable(offers,"offerWeek",int.class);
        Field loaded=variable(offers,"offersLoaded",boolean.class);
        Field redeemed=variable(offers,"offerRedeemed",int.class);
        open.invoke(null,5);
        if(count.getInt(null)<2 || count.getInt(null)>3)throw new AssertionError("Weekly offer generation");
        int[] ids=(int[])field(offers,null,"offerIds",int[].class);
        int[] discounts=(int[])field(offers,null,"offerDiscount",int[].class);
        int[] coins=(int[])field(offers,null,"offerCoins",int[].class);
        int[] bills=(int[])field(offers,null,"offerBills",int[].class);
        for(int n=2;n<=3;n++){
            count.setInt(null,n);loaded.setBoolean(null,true);redeemed.setInt(null,0);
            ids[0]=64;discounts[0]=25;coins[0]=bills[0]=0;
            ids[1]=-1;discounts[1]=0;coins[1]=450;bills[1]=3;
            ids[2]=65;discounts[2]=40;coins[2]=bills[2]=0;
            open.invoke(null,5);
            int[] marketIds=(int[])field(game,null,"M",int[].class);
            int[] prices=(int[])field(game,null,"Q",int[].class);
            int[] cash=(int[])field(game,null,"R",int[].class);
            if(marketIds.length!=n || marketIds[0]!=64 || cash[0]!=113 || prices[1]!=450 ||
                n==3 && marketIds[2]!=65)throw new AssertionError("Mixed weekly cards");
            short[][][] controls=(short[][][])field(game,null,"a",short[][][].class);
            short[] icon=controls[2][44],wallet=controls[2][6];
            if(icon[5]!=wallet[5] || icon[6]!=wallet[6] || icon[9]!=0)
                throw new AssertionError("Currency card is not using the static wallet icon");
            method(offers,"saveOffers",void.class).invoke(null);
            loaded.setBoolean(null,false);count.setInt(null,0);
            method(offers,"loadOffers",void.class).invoke(null);
            if(count.getInt(null)!=n || ids[0]!=64 || ids[1]!=-1)
                throw new AssertionError("Weekly record does not survive reload");
        }
        System.out.println("WEEKLY_OK Saturday, 2/3 cards, currency art and RMS");
    }

    private static void checkWithinFrame(ClassLoader loader) throws Exception {
        Class<?> game=Class.forName("a",true,loader), actor=Class.forName("f",true,loader);
        Class<?> sprite=Class.forName("e",true,loader);
        Class<?> spriteArray=java.lang.reflect.Array.newInstance(sprite,0).getClass();
        Object[] pool=(Object[])field(game,null,"b",spriteArray);
        int[] sheets={160,159,188,188,177,175,175,176,176,171,172,178};
        int[] feeds={5,5,2,2,6,6,6,6,6,0,0,6};
        Method create=method(game,"a",actor,int.class,int.class);
        // In this isolated profile seed only the prerequisites, then use the
        // game's purchase, placement, quote and sale handlers unchanged.
        method(game,"X",Void.TYPE,int.class).invoke(null,10);
        method(game,"V",Void.TYPE,int.class).invoke(null,15000);
        method(game,"o",Boolean.TYPE,int.class).invoke(null,0);
        Method showShelf=method(game,"r",Void.TYPE,int.class,int.class);
        showShelf.invoke(null,0,5);
        method(game,"af",Void.TYPE,int.class).invoke(null,0);
        Object puppy=field(game,null,"e",actor);
        if (puppy==null || ((Integer)field(actor,puppy,"J",Integer.TYPE)).intValue()!=2069)
            throw new AssertionError("Beagle purchase did not enter placement");
        method(game,"a",Void.TYPE,actor,Boolean.TYPE).invoke(null,puppy,false);
        method(game,"fI",Void.TYPE).invoke(null);
        int coins=((Integer)method(game,"d",Integer.TYPE).invoke(null)).intValue();
        int quote=((Integer)method(actor,"a",Integer.TYPE).invoke(puppy)).intValue();
        if (coins!=5000 || quote!=400) throw new AssertionError("Beagle price or resale "+coins+"/"+quote);
        method(actor,"G",Void.TYPE).invoke(puppy);
        System.out.println("TRADE 2069 10000 "+quote);
        for (int i=0;i<sheets.length;i++) {
            int row=64+i;
            if (pool[sheets[i]]==null) throw new AssertionError("Missing physical sprite "+sheets[i]);
            Object obj=create.invoke(null,0,row);
            int id=((Integer)field(actor,obj,"J",Integer.TYPE)).intValue();
            int sheet=((Integer)field(actor,obj,"E",Integer.TYPE)).intValue();
            int feed=((Short)field(actor,obj,"a",Short.TYPE)).intValue();
            if (id!=2000+row || sheet!=sheets[i] || feed!=feeds[i]) throw new AssertionError("species "+row);
            System.out.println("ACTOR "+id+" "+sheet+" "+feed);
        }
        for (int[] entry:new int[][]{{3,20,1010,167},{3,21,1011,167},{4,63,7063,169}}) {
            Object obj=create.invoke(null,entry[0],entry[1]);
            int id=((Integer)field(actor,obj,"J",Integer.TYPE)).intValue();
            int sheet=((Integer)field(actor,obj,"E",Integer.TYPE)).intValue();
            if (id!=entry[2] || sheet!=entry[3]) throw new AssertionError("object "+id+"/"+sheet);
            System.out.println("OBJECT "+id+" "+sheet);
        }
        Class<?> table=Class.forName("h",true,loader);
        Object[] tables=(Object[])field(table,null,"a",java.lang.reflect.Array.newInstance(table,0).getClass());
        int buildings=((Integer)field(table,tables[3],"b",Integer.TYPE)).intValue();
        int decor=((Integer)field(table,tables[4],"b",Integer.TYPE)).intValue();
        if (buildings==30 && decor==69) {
            for (int[] entry:new int[][]{{3,24,1014,174},{3,25,1015,174},{3,26,1016,174},{3,28,1018,183},
                                         {4,64,7064,179},{4,65,7065,180},{4,66,7066,181},{4,67,7067,181},{4,68,7068,182}}) {
                Object obj=create.invoke(null,entry[0],entry[1]);
                int id=((Integer)field(actor,obj,"J",Integer.TYPE)).intValue();
                int sheet=((Integer)field(actor,obj,"E",Integer.TYPE)).intValue();
                if(id!=entry[2] || sheet!=entry[3]) throw new AssertionError("house/toy "+id);
                System.out.println("OBJECT "+id+" "+sheet);
            }
        }
        int[][] scenery=(int[][])field(table,tables[15],"a",int[][].class);
        for(int row=28;row<=29;row++) {
            int[] data=scenery[row];
            Object piece=method(actor,"a",actor,int.class,int.class,int[].class).invoke(null,32,1,
                new int[]{1700,800,data[7],data[1],data[2],data[4],data[5],data[3],data[6]});
            if(piece==null || (Integer)field(actor,piece,"E",int.class)!=184+row-28)
                throw new AssertionError("Expansion scenery "+row);
        }
        System.out.println("SCENERY slots=184,185");
        // Enter the actual MIDP shop UI and ask it to populate each shelf.
        method(game,"o",Boolean.TYPE,int.class).invoke(null,0);
        for (int[] shelf:new int[][]{{0,-1,1,3,64,65},{0,2,66,28,30,32,34,36,38},
                                    {0,5,69,71,68,75},{3,-1,10,13,11,12,20,21}}) {
            showShelf.invoke(null,shelf[0],shelf[1]);
            int[] rowIds=(int[])field(game,null,"M",int[].class);
            for(int i=2;i<shelf.length;i++) {
                if(rowIds[i-2]!=shelf[i]) throw new AssertionError("shop "+shelf[0]+"/"+shelf[1]+" slot "+(i-2)+" got "+rowIds[i-2]);
            }
            System.out.println("SHELF "+shelf[0]+" "+shelf[1]+" "+(shelf.length-2));
        }
        showShelf.invoke(null,4,-1);
        if (((int[])field(game,null,"M",int[].class))[0]!=63) throw new AssertionError("statue");
        // Request each new recipe icon using the same UI reader used by
        // the kitchen, flush its queued requests and draw its item frame.
        Object[] menuArt=(Object[])field(game,null,"a",spriteArray);
        int[] capacity=(int[])field(game,null,"i",int[].class);
        if(capacity[1]!=138 || menuArt.length!=173)
            throw new AssertionError("Physical UI sprite limits "+capacity[1]+"/"+menuArt.length);
        // Native packed count remains 138; independently loaded UI sheets
        // through 172 share this same expanded cache.
        for (int slot=126;slot<=135;slot++) method(game,"d",Void.TYPE,int.class,int.class).invoke(null,1,slot);
        // A deferred hive or pet cue can arrive inside a menu update.
        Class<?> pack=Class.forName("g",true,loader);
        method(pack,"c",void.class,String.class).invoke(null,"/7");
        method(Class.forName("GF3FarmAudio",true,loader),"original",void.class,int.class).invoke(null,79);
        boolean loaded=(Boolean)method(Class.forName("k",true,loader),"a",boolean.class,int.class).invoke(null,149);
        if(!loaded || !"/7".equals(field(pack,null,"c",String.class)))
            throw new AssertionError("Deferred sound left the menu resource reader on another pack");
        // Invoke the native UI loader, which selects pack /7 itself.
        // Advance only its read timer in this paused test frame.
        for(int attempts=0;attempts<64 && (Integer)method(game,"f",int.class,int.class).invoke(null,1)>0;attempts++) {
            variable(game,"ao",int.class).setInt(null,0);
            method(game,"t",Void.TYPE,int.class).invoke(null,1);
        }
        for (int slot=126;slot<=135;slot++) {
            if(menuArt[slot]==null) throw new AssertionError("recipe icon "+slot);
            javax.microedition.lcdui.Image img=javax.microedition.lcdui.Image.createImage(480,800);
            javax.microedition.lcdui.Graphics gr=img.getGraphics();
            gr.setColor(0xf81fe9);gr.fillRect(0,0,480,800);
            method(sprite,"a",Void.TYPE,javax.microedition.lcdui.Graphics.class,int.class,int.class,int.class,int.class)
                    .invoke(menuArt[slot],gr,0,400,240,0);
            int[] rgb=new int[480*800];
            img.getRGB(rgb,0,480,0,0,480,800);
            int ink=0;
            for(int color:rgb) if((color & 0xffffff)!=0xf81fe9) ink++;
            if(ink<20) throw new AssertionError("empty recipe icon "+slot+"/"+ink);
            System.out.println("RECIPE_ICON "+slot+" "+ink);
        }
        checkWeekly(loader,game);
        System.out.println("MARKET_OK");
    }
}
