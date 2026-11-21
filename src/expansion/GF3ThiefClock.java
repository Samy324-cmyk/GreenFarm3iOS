import java.io.IOException;

/** Local defaults of the Android predator schedule, measured in active game time. */
final class GF3ThiefClock {
    private static final int INTERVAL=300000, LIMIT=2;
    private static int elapsed, count;
    private static long day, previous;
    private static boolean positioned;
    static int row, x, y;

    private GF3ThiefClock() {}

    static void startDay() {
        day=System.currentTimeMillis()/1000;
        count=0; elapsed=0; previous=0;
    }

    static void clearEncounter() {
        row=0; x=0; y=0; elapsed=0; previous=0;positioned=false;
    }

    private static f victim() {
        int count=0;
        f choice=null, hive=null;
        for(int layer=0;layer<2;layer++) {
            for(f actor=f.heads[layer];actor!=null;actor=actor.next) {
                if(!actor.a(512) || actor.a(4096)) continue;
                if(GF3Hive.isHive(actor)) {
                    if(hive==null || actor.y==22) hive=actor;
                } else if(actor.q==54 && !GF3Dogs.dog(actor) && actor.J!=2073 && actor.J!=2074) {
                    if(g.c(0,++count)==0) choice=actor;
                }
            }
        }
        return choice==null?hive:choice;
    }

    static boolean ready() {
        if(row!=0) {
            long now=System.currentTimeMillis()/1000;
            if(now-day>=86400) {day=now;count=1;}
            return true;
        }
        if(a.f()<10 || !a.h(9299) || a.i(302)) {previous=0;return false;}
        long now=System.currentTimeMillis(), seconds=now/1000;
        if(day==0 || seconds-day>=86400) {day=seconds; count=0;}
        if(previous!=0) {
            long delta=now-previous;
            if(delta>0 && delta<=500) elapsed=(int)Math.min(INTERVAL,elapsed+delta);
        }
        previous=now;
        if(elapsed<INTERVAL || count>=LIMIT) return false;
        f target=victim();
        if(target==null) return false;
        f dog=GF3Doghouse.resident(null);
        row=dog!=null && GF3Dogs.level(dog)>=3 && g.c(0,10)>5 ? 74:73;
        x=target.r;
        y=target.s;
        count++; elapsed=0;
        return true;
    }

    static void locate(f enemy) {
        if(!positioned) {
            int[] point=new int[2];
            if(a.a(enemy,point)) {
                x=point[0];y=point[1];
            } else {
                // Android tries the eight positions around the selected
                // livestock or hive when the viewport has no open tile.
                int dx=enemy.r>x?72:-72,dy=enemy.r>y?36:-36;
                boolean found=false;
                for(int i=1;i>=-1 && !found;i--) for(int j=1;j>=-1 && !found;j--) {
                    if(i==0 && j==0) continue;
                    enemy.r=x+i*dx; enemy.s=y+j*dy;
                    found=!a.a(enemy);
                    if(found) {x=enemy.r;y=enemy.s;}
                }
            }
            positioned=true;
        }
        enemy.r=x;enemy.s=y;
    }

    private static void put(byte[] buf,int pos,long value,int bytes) {
        for(int i=0;i<bytes;i++) buf[pos+i]=(byte)(value>>>(i*8));
    }

    private static long get(byte[] buf,int pos,int bytes) {
        long result=0;
        for(int i=0;i<bytes;i++) result|=(long)(buf[pos+i]&255)<<(i*8);
        return result;
    }

    static byte[] save(byte[] main) {
        if(day==0 && row==0) return main;
        int n=main.length;
        byte[] data=new byte[n+22];
        System.arraycopy(main,0,data,0,n);
        put(data,n,day,8); put(data,n+8,elapsed,4);
        data[n+12]=(byte)(count+(positioned?128:0)); data[n+13]=(byte)row;
        put(data,n+14,x,2);put(data,n+16,y,2);
        data[n+18]='R';data[n+19]='A';data[n+20]='D';data[n+21]=1;
        return data;
    }

    static byte[] load(byte[] saved) throws IOException {
        day=previous=0;count=0;clearEncounter();
        if(saved==null || saved.length<22) return saved;
        int n=saved.length-22;
        if(saved[n+18]!='R' || saved[n+19]!='A' || saved[n+20]!='D' || saved[n+21]!=1) return saved;
        day=get(saved,n,8); elapsed=(int)get(saved,n+8,4); count=saved[n+12]&127;
        positioned=(saved[n+12]&128)!=0;
        row=saved[n+13]&255; x=(int)get(saved,n+14,2); y=(int)get(saved,n+16,2);
        if(day<0 || elapsed<0 || elapsed>INTERVAL || count>LIMIT || (row!=0 && row!=73 && row!=74))
            throw new IOException();
        byte[] main=new byte[n];
        System.arraycopy(saved,0,main,0,n);
        return main;
    }
}
