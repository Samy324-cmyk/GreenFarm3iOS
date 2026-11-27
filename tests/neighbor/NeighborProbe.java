import java.lang.reflect.*;
import java.util.Arrays;
import org.recompile.mobile.Mobile;

final class NeighborProbe {
    static int coinsBeforeClaim, xpBeforeClaim;
    static Class<?> type(String name) throws Exception {
        return Class.forName(name,true,Mobile.getPlatform().loader);
    }
    static Object read(Class<?> c,Object target,String name,Class<?> t) throws Exception {
        return MarketProbe.field(c,target,name,t);
    }
    static Object invoke(Class<?> c,String name,Class<?> result,Class<?>[] types,Object... args) throws Exception {
        return MarketProbe.method(c,name,result,types).invoke(null,args);
    }
    static void run(String op) throws Exception {
        Class<?> game=type("a"),actor=type("f"),enc=type("GF3Neighbor");
        if (op.equals("seed")) {
            invoke(game,"X",void.class,new Class[]{int.class},10);
            invoke(game,"f",void.class,new Class[]{int.class,int.class,boolean.class},299,0,true);
            ((int[])read(game,null,"cb",int[].class))[0]=2;
            // The mailbox belongs to the earlier quest 9002.
            int[] done=(int[])read(game,null,"cc",int[].class);
            for(int i=0;i<done.length;i++) if(done[i]==-1) {done[i]=9002;break;}
            String title=((String[])read(game,null,"i",String[].class))[0];
            if (!"Problemas con los depredadores".equals(title)) throw new AssertionError(title);
        } else if (op.equals("wait-message")) {
            long end = System.currentTimeMillis() + 18000;
            while (((Integer)read(enc,null,"step",int.class)!=5 ||
                (Integer)invoke(game,"a",int.class,new Class[]{})!=19) && System.currentTimeMillis()<end)
                Thread.sleep(40);
            if (((Integer)read(enc,null,"step",int.class))!=5 ||
                (Integer)invoke(game,"a",int.class,new Class[]{})!=19 ||
                ((boolean[])read(game,null,"j",boolean[].class))[0])
                throw new AssertionError("Before acknowledgment: step="+read(enc,null,"step",int.class)+
                    " menu="+invoke(game,"a",int.class,new Class[]{})+
                    " objective="+((boolean[])read(game,null,"j",boolean[].class))[0]);
        } else if (op.equals("expect-done")) {
            if (!((boolean[])read(game,null,"j",boolean[].class))[0] ||
                ((int[])read(game,null,"cb",int[].class))[0]!=3)
                throw new AssertionError("Victory did not complete the objective");
            System.out.println("NEIGHBOR_OK");
        } else if (op.equals("expect-reward")) {
            if ((Integer)read(game,null,"F",int.class)!=0 ||
                (Integer)invoke(game,"a",int.class,new Class[]{})!=26 ||
                ((int[])read(game,null,"bD",int[].class))[0]!=9301)
                throw new AssertionError("Expected quest reward on the home farm");
            coinsBeforeClaim=(Integer)invoke(game,"d",int.class,new Class[]{});
            xpBeforeClaim=(Integer)invoke(game,"x",int.class,new Class[]{});
        } else if (op.equals("expect-claimed")) {
            int coins=(Integer)invoke(game,"d",int.class,new Class[]{});
            int xp=(Integer)invoke(game,"x",int.class,new Class[]{});
            if (coins-coinsBeforeClaim!=300 || xp-xpBeforeClaim!=10 ||
                    ((int[])read(game,null,"cc",int[].class))[299]!=9301 ||
                    ((int[])read(game,null,"bD",int[].class))[0]==9301)
                throw new AssertionError("Rewards/ledger "+coinsBeforeClaim+"->"+coins+
                    " XP "+xpBeforeClaim+"->"+xp);
            System.out.println("NEIGHBOR_REWARD_OK coins=300 xp=10");
        }
        StringBuilder line=new StringBuilder("NEIGHBOR ").append(op).append(" menu=")
            .append(invoke(game,"a",int.class,new Class[]{})).append(" farm=")
            .append(read(game,null,"F",int.class)).append(" step=").append(read(enc,null,"step",int.class))
            .append(" quest=").append(Arrays.toString((int[])read(game,null,"cb",int[].class)));
        for (String n:new String[]{"fox","dog"}) {
            Object pet=read(enc,null,n,actor);
            if (pet!=null) {
                line.append(" ").append(n).append("=");
                for(String part:new String[]{"D","r","s","u","v"})
                    line.append(read(actor,pet,part,int.class)).append("/");
            }
        }
        System.out.println(line);
    }
}
