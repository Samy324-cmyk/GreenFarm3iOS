import java.io.IOException;

/** Android's dog-name keyboard, active resident and four saved breed names. */
final class GF3PetNames {
    private static final int GUI=29, SCREEN=49, MAX_NAME=12;
    private static final String LETTERS="qwertyuiopasdfghjklzxcvbnm";
    private static final String SYMBOLS="1234567890@#$%&*-+/!,':;.?";
    private static final String[] names=new String[4];
    private static boolean caps,digits,collar,accepted,swapped;
    private static int editing=-1;
    private static f pending;
    private static String input;

    private GF3PetNames() {}

    private static int breed(int row) {
        if(row==68)return 0;
        if(row==69 || row==70)return 1;
        if(row==71 || row==72)return 2;
        return 3;
    }

    static String name(f pet) {
        int index=breed(pet.y);
        return names[index]==null?GF3HouseData.TEXT[8+index]:names[index];
    }

    static boolean unavailable(int row) {
        if(row<68 || row>72 && row!=75)return false;
        for(int layer=0;layer<2;layer++){
            for(f actor=f.heads[layer];actor!=null;actor=actor.next){
                if(GF3Dogs.dog(actor) && breed(actor.y)==breed(row) &&
                        (actor.a(512) || actor.a(4096))){
                    a.c(56);
                    a.a(GF3HouseData.TEXT[22],GF3HouseData.TEXT[23],7);
                    return true;
                }
            }
        }
        return (row==71 || row==75 || GF3Doghouse.resident(null)!=null) && barnFull();
    }

    static boolean houseUnavailable(int row) {
        return row>=24 && row<=26 && GF3Doghouse.placed(null)!=null && barnFull();
    }

    private static boolean barnFull() {
        if(a.totalStored(5)>=a.capacity()){
            a.a(GF3HouseData.TEXT[24],GF3HouseData.TEXT[25],7);
            return true;
        }
        return false;
    }

    private static void begin(f pet,boolean renamed) {
        editing=breed(pet.y);
        input=name(pet);
        collar=renamed;
        accepted=false;
        caps=false;
        digits=false;
        a.a(SCREEN);
    }

    static void collar(int slot,int button) {
        f pet=GF3Doghouse.resident(null);
        if(pet==null){
            a.a(GF3HouseData.TEXT[16],GF3HouseData.TEXT[17],7);
            return;
        }
        if(a.Q[slot]!=0?a.spend(a.Q[slot]):a.f(a.R[slot])){
            a.c(61);
            begin(pet,true);
        }else a.gf3PreviousBuy(button);
    }

    static void place() {
        f arriving=a.placedPet;
        int mode=a.mode;
        boolean placed=arriving!=null && (mode==0 || mode==4);
        boolean change=placed && GF3Dogs.dog(arriving);
        boolean house=placed && arriving.q==50 && arriving.y>=24 && arriving.y<=26;
        f old=change?GF3Doghouse.resident(arriving):house?GF3Doghouse.placed(arriving):null;
        a.gf3PreviousPlacement();
        if(house){
            GF3DogTutorial.placed(arriving.y);
            if(old!=null){
                if(old.a(2))a.b(old);
                a.c(old);
                a.a(GF3HouseData.TEXT[26],GF3HouseData.TEXT[27],7);
            }
            f resident=GF3Doghouse.resident(null);
            if(resident!=null)GF3Dogs.floor(resident,GF3HouseData.FLOOR[arriving.y-24]);
            return;
        }
        if(!change)return;
        if(old!=null && breed(old.y)!=breed(arriving.y)){
            if(old.a(2))a.b(old);
            a.c(old);
            swapped=true;
        }
        GF3Dogs.floor(arriving,GF3Doghouse.floor());
        if(mode==0){
            names[breed(arriving.y)]=null;
            pending=arriving;
        }
    }

    private static boolean adoption(){
        if(a.bD==null || a.cb==null)return false;
        for(int i=0;i<a.bD.length;i++)if((a.bD[i]==9297 || a.bD[i]==9299) && a.cb[i]==2)return true;
        return false;
    }
    static boolean naming(f pet){return pending==pet || editing>=0 || pet!=null && adoption() && names[breed(pet.y)]==null;}
    static void farmTick(f pet) {
        if(pet==null || a.F!=0 || editing>=0 || a.a()!=17 || a.transition!=-1 || !pet.a(512) || pet.a(4096))return;
        if(pending==null && adoption() && names[breed(pet.y)]==null)pending=pet;
        if((pending==null && !swapped) || (pending!=null && pet!=pending))return;
        if(swapped){
            swapped=false;
            a.a(GF3HouseData.TEXT[18],GF3HouseData.TEXT[19],7);
        }else{
            pending=null;
            begin(pet,false);
        }
    }

    private static void letters() {
        String[] labels=a.captions[GUI];
        labels[3]=GF3HouseData.TEXT[12];
        labels[4]=null;
        labels[7]=digits?"ABC":"123";
        labels[9]="Borrar";
        labels[11]="Listo";
        labels[13]="May\u00fas";
        labels[15]="Espacio";
        String keys=digits?SYMBOLS:caps?LETTERS.toUpperCase():LETTERS;
        for(int i=0;i<26;i++) labels[43+i]=keys.substring(i,i+1);
    }

    private static void close(boolean keep) {
        if(keep){
            String upper=input.toUpperCase();
            boolean valid=input.trim().length()>0;
            for(int i=0;i<GF3HouseData.BAD.length && valid;i++)
                if(upper.indexOf(GF3HouseData.BAD[i])>=0) valid=false;
            if(!valid){
                a.a(GF3HouseData.TEXT[20],GF3HouseData.TEXT[21],7);
                return;
            }
            names[editing]=input;
        }else if(!collar && names[editing]==null){
            // Explicit cancel accepts the suggested name; don't reopen forever.
            names[editing]=GF3HouseData.TEXT[8+editing];
        }
        a.c(true);
        accepted=true;
        a.a(GF3HouseData.TEXT[12],GF3HouseData.TEXT[collar?15:13],7);
    }

    static boolean screen(int phase) {
        if(phase==0) GF3Doghouse.load(GUI);
        if(phase==1){
            if(accepted){a.t();return false;}
            GF3Doghouse.enterCache(GUI);
            a.E(GUI);
            letters();
            a.gf();a.H(GUI);
        }
        if(phase==2){
            int key=g.i();
            if(key==19 || key==11){a.c(61);close(false);}
        }
        if(phase==3){
            if(input==null)input="";
            a.captions[GUI][16]=(System.currentTimeMillis()/500L&1L)==0?input:input+"_";
            GF3Doghouse.draw(GUI);
        }
        if(phase==4) GF3Doghouse.leaveCache();
        if(phase==5){
            GF3Doghouse.unload();
            editing=-1;input=null;accepted=false;
        }
        return false;
    }

    static void hit(int id) {
        if(editing<0 || editing>=names.length || input==null)return;
        if(id==2){a.c(61);close(false);return;}
        if(id==10){a.c(61);close(true);return;}
        if(id==8){
            if(input.length()>0)input=input.substring(0,input.length()-1);
        }else if(id==6){
            digits=!digits;caps=false;
            letters();
        }else if(id==12){
            if(!digits){caps=!caps;letters();}
        }else if(input.length()>=MAX_NAME)return;
        else if(id==14)input=input+" ";
        else if(id>=17 && id<=42)input=input+a.captions[GUI][43+id-17];
        a.c(135);
    }

    static byte[] pack(byte[] main) {
        int pos=main.length;
        byte[] data=new byte[pos+4*(1+MAX_NAME*2)+4];
        System.arraycopy(main,0,data,0,pos);
        for(int i=0;i<4;i++){
            String value=names[i];
            int length=value==null?0:value.length();
            data[pos++]=(byte)length;
            for(int j=0;j<length;j++){
                int c=value.charAt(j);
                data[pos+j*2]=(byte)(c>>>8);
                data[pos+j*2+1]=(byte)c;
            }
            pos+=MAX_NAME*2;
        }
        data[pos]='D';data[pos+1]='P';data[pos+2]='N';data[pos+3]=1;
        return data;
    }

    static void reset() {
        for(int i=0;i<4;i++)names[i]=null;
        pending=null;swapped=false;editing=-1;accepted=false;input=null;
    }

    static byte[] unpack(byte[] data) throws IOException {
        int tail=data.length-4;
        if(tail<0 || data[tail]!='D' || data[tail+1]!='P' || data[tail+2]!='N')return data;
        int width=1+MAX_NAME*2,pos=tail-4*width;
        if(data[tail+3]!=1 || pos<0)throw new IOException();
        byte[] main=new byte[pos];
        System.arraycopy(data,0,main,0,pos);
        for(int i=0;i<4;i++){
            int count=data[pos++]&255;
            if(count>MAX_NAME)throw new IOException();
            if(count>0){
                char[] chars=new char[count];
                for(int j=0;j<count;j++)
                    chars[j]=(char)((data[pos+j*2]&255)<<8 | data[pos+j*2+1]&255);
                names[i]=new String(chars);
            }
            pos+=MAX_NAME*2;
        }
        return main;
    }
}
