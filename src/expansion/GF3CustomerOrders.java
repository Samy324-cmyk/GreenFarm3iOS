import java.io.IOException;

/** The Android farm stand keeps each discarded customer's stall closed for 30 minutes. */
final class GF3CustomerOrders {
    private static final long INTERVAL=1800000L;
    private static final int FIRST=208, SPEED=211, SHEET=172;
    private static final long[] since=new long[20];
    private static int previous=-2,offset=-1,marked;

    private GF3CustomerOrders(){}

    private static int remaining(int slot,long now){
        return since[slot]==0?0:(int)((INTERVAL+since[slot]-now)/1000L);
    }
    private static void art(){
        if(a.assets.length<=SHEET){
            e[] pool=new e[SHEET+1];
            System.arraycopy(a.assets,0,pool,0,a.assets.length);
            a.assets=pool;
        }
        if(a.assets[SHEET]==null){
            g.open("/dh");e sheet=new e();sheet.a(g.chunk(3),0);g.l();a.assets[SHEET]=sheet;
        }
    }
    private static void visible(int control,boolean show,boolean button){
        short[] row=a.ui[3][control];
        if(row[0]==204)row[15]=(short)(show?1:0);
        else{
            row[10]=(short)(show?1:0);
            row[18]=(short)(show&&button?1:0);
        }
    }
    private static void refresh(){
        long now=System.currentTimeMillis();
        boolean expired=false;
        if(a.aw)for(int i=0;i<since.length;i++){
            if(since[i]==0 || remaining(i,now)>0)continue;
            replace(i);expired=true;
        }
        int mask=0;
        if(a.aw)for(int i=0;i<15 && i+a.cB<a.cA;i++)
            if(since[a.ab[i+a.cB]]!=0)mask|=1<<i;
        int selected=a.aw && a.cC>=0 && a.cC<a.cA && since[a.ab[a.cC]]!=0?a.ab[a.cC]:-1;
        if(!expired && selected==previous && marked==mask && offset==a.cB)return;
        for(int i=0;i<15;i++){
            int start=10+11*i, control=start+7;
            short[] row=a.ui[3][control];
            if((mask&(1<<i))!=0){
                art();row[5]=SHEET;row[6]=234;row[10]=1;
                short[] card=a.ui[3][start];
                row[2]=(short)(card[2]+49);row[3]=(short)(card[3]+30);
                for(int cell=start+1;cell<=start+4;cell++)visible(cell,false,false);
            }else if((marked&(1<<i))!=0){
                row[5]=a.templates[3][control][5];row[6]=a.templates[3][control][6];
                for(int axis=2;axis<=3;axis++)row[axis]=(short)(a.ui[3][start][axis]+
                        a.templates[3][control][axis]-a.templates[3][start][axis]);
                a.card(i,a.cB+i<a.cA);
            }
        }
        marked=mask;offset=a.cB;previous=selected;
        boolean blocked=selected>=0;
        for(int i=FIRST;i<FIRST+6;i++)visible(i,blocked,i==SPEED);
        if(blocked){
            art();a.ui[3][SPEED][5]=SHEET;a.ui[3][FIRST+5][5]=SHEET;
            for(int i=176;i<=188;i++)visible(i,false,false);
            for(int i=198;i<=200;i++)visible(i,false,false);
        }else if(a.aw && a.cA>0){
            visible(198,true,true);visible(199,true,true);visible(200,true,false);
            a.select(a.cC-a.cB);
        }
        a.gf();a.H(3);
    }
    private static void replace(int slot){
        since[slot]=0;
        a.generate(slot,null);
        if(a.aw && slot<a.cA){
            a.rebind(slot,slot);
            int local=slot-a.cB;
            if(local>=0 && local<15)a.card(local,true);
        }
    }
    static boolean available(int slot){
        return (slot<0 || slot>=since.length || since[slot]==0) && a.gf3CanDeliver(slot);
    }
    static void discard(){
        int slot=a.ab[a.cC];
        if(since[slot]!=0)return;
        a.c(23);since[slot]=System.currentTimeMillis();
        previous=-2;refresh();
    }
    static void hit(int event){
        if(event==(3<<16|SPEED) && a.a()==8 && a.aw && a.cC>=0 && a.cC<a.cA){
            int slot=a.ab[a.cC];
            if(since[slot]==0)return;
            if(remaining(slot,System.currentTimeMillis())<=0 || a.payBills(4)){
                a.c(49);replace(slot);previous=-2;refresh();
            }else{
                a.c(56);
                a.notice(GF3CustomerText.MISSING,7,0);
            }
            return;
        }
        a.gf3StandHit(event);
        if((event>>>16)==3)previous=-2;
    }
    static boolean screen(int phase){
        boolean nativeResult=a.gf3StandScreen(phase);
        if(phase==1){previous=-2;offset=-1;marked=0;refresh();}
        else if(phase==2)refresh();
        else if(phase==3 && previous>=0){
            a.line(GF3CustomerText.WAIT,3,FIRST,0,0);
            a.line(a.time(remaining(previous,System.currentTimeMillis())),3,FIRST+1,0,0);
            a.wrap(GF3CustomerText.DETAIL,3,FIRST+2,0,0);
            a.line("4",3,FIRST+4,0,0);
        }else if(phase==5){
            previous=-2;offset=-1;marked=0;
            if(a.assets.length>SHEET)a.assets[SHEET]=null;
        }
        return nativeResult;
    }

    static void reset(){
        for(int i=0;i<since.length;i++)since[i]=0;
        previous=-2;marked=0;offset=-1;
        GF3DogTutorial.reset();
    }
    static byte[] pack(byte[] source){
        byte[] before=GF3DogTutorial.pack(source);
        int count=0;
        for(int i=0;i<since.length;i++)if(since[i]!=0)count++;
        if(count==0)return before;
        int n=before.length;
        byte[] saved=new byte[n+count*9+5];System.arraycopy(before,0,saved,0,n);
        for(int i=0;i<since.length;i++)if(since[i]!=0){
            saved[n++]=(byte)i;
            for(int b=0;b<8;b++)saved[n++]=(byte)(since[i]>>>(b*8));
        }
        saved[n++]=(byte)count;saved[n++]='O';saved[n++]='R';saved[n++]='D';saved[n]=1;
        return saved;
    }
    static byte[] unpack(byte[] data)throws IOException{
        int n=data.length-5;
        if(n<0 || data[n+1]!='O' || data[n+2]!='R' || data[n+3]!='D')return GF3DogTutorial.unpack(data);
        int count=data[n]&255,start=n-count*9;
        if(data[n+4]!=1 || count>20 || start<0)throw new IOException();
        int pos=start;
        long[] restored=new long[since.length];
        for(int i=0;i<count;i++){
            int slot=data[pos++]&255;
            if(slot>=restored.length || restored[slot]!=0)throw new IOException();
            long time=0;for(int b=0;b<8;b++)time|=(long)(data[pos++]&255)<<(8*b);
            if(time<=0)throw new IOException();
            restored[slot]=time;
        }
        byte[] base=new byte[start];System.arraycopy(data,0,base,0,start);
        base=GF3DogTutorial.unpack(base);
        System.arraycopy(restored,0,since,0,since.length);
        return base;
    }
}
