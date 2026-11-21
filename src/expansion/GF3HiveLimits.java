/** Android counts bee houses and fruit trees as separate actor types. */
final class GF3HiveLimits {
    private static boolean rejectedHive;

    static int capacity(){
        int level=Math.max(0,Math.min(50,a.f()));
        return GF3HiveLevels.maximum[level];
    }
    private static boolean hive(int sku){return sku==3022 || sku==3023;}
    private static int placed(){return f.b(0,3022)+f.b(0,3023);}
    static int owned(){return placed()+a.gf3Stored(4,10)+a.gf3Stored(4,11);}
    static int trees(){return f.a(0,52)-placed();}
    static int buyCount(int slot){return hive(a.V[slot])?owned():trees();}
    static int buyLimit(int slot){return hive(a.V[slot])?capacity():a.B();}
    static int placingCount(f actor){return hive(actor.J)?owned():trees();}
    static int placingLimit(f actor){return hive(actor.J)?capacity():a.B();}
    static int cancelPlacement(f actor){
        rejectedHive=hive(actor.J);
        a.D();
        return 20;
    }
    static void placingNotice(){
        boolean hive=rejectedHive;
        rejectedHive=false;
        notice(hive);
    }
    static void buyNotice(int slot){notice(hive(a.V[slot]));}
    private static void notice(boolean hive){
        if(!hive){a.e(491,492,7,0);return;}
        int i=capacity()<20?0:2;
        a.gf3HiveNotice(GF3HiveLevels.text[i],GF3HiveLevels.text[i+1],7,0,false);
    }
    static int areaTrees(int layer,int kind,int left,int right,int top,int bottom,f[] found,int max){
        int count=f.a(layer,kind,left,right,top,bottom,found,max),trees=0;
        for(int i=0;i<count;i++)if(!hive(found[i].J))trees++;
        return trees;
    }
}
