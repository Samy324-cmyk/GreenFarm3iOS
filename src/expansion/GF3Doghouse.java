import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;
import java.io.IOException;

/** Android's state 48 adapted to the native MIDP GUI and pet records. */
final class GF3Doghouse {
    private static final int SCREEN=48, GUI=28, BASE=150;
    private static final int[] BREEDS={68,70,72,75,69,71};
    private static final String[] emptyCaptions=new String[80];
    private static f pet;
    private static int house, lastSecond=-1;
    private static l[] priorImages;
    private static byte[] priorFlags;
    private static final l[][] menuImages=new l[2][];
    private static final byte[][] menuFlags=new byte[2][];
    private static boolean cacheActive;
    private static int activeGui=-1;
    private static int assetUsers;
    private static final int[] fixedFrames={12,13,62,206,246,247,248,251};
    private static final Image[] fixedArt=new Image[fixedFrames.length];
    static boolean drawFixed(int gui,short[] row){
        if(gui!=GUI || row[0]!=205 || row[5]!=153 || row[10]!=1)return false;
        int i=0;while(i<fixedFrames.length && fixedFrames[i]!=row[6])i++;
        if(i==fixedFrames.length)return false;
        try{
            if(fixedArt[i]==null)fixedArt[i]=Image.createImage("/gf3-house-"+fixedFrames[i]+".png");
            Image img=fixedArt[i];Graphics gr=g.graphics;
            if(gr==null)return false;
            gr.drawImage(img,480-row[3]-img.getWidth(),row[2],Graphics.TOP|Graphics.LEFT);
            return true;
        }catch(IOException missing){return false;}
    }

    private GF3Doghouse() {}

    static boolean openBuilding(int row) {
        if(row<24 || row>26) return GF3KitchenQueue.openBuilding(row);
        house=row;
        a.c(60);
        a.a(SCREEN);
        return true;
    }

    static f resident(f exclude) {
        for(int layer=0;layer<2;layer++)
            for(f actor=f.heads[layer];actor!=null;actor=actor.next)
                if(actor!=exclude && GF3Dogs.dog(actor) && !actor.a(4096) && actor.a(512))
                    return actor;
        return null;
    }

    static f placed(f exclude) {
        for(int layer=0;layer<2;layer++)
            for(f actor=f.heads[layer];actor!=null;actor=actor.next)
                if(actor!=exclude && actor.q==50 && actor.y>=24 && actor.y<=26 &&
                        !actor.a(4096) && actor.a(512))return actor;
        return null;
    }

    static int floor() {
        f home=placed(null);
        return home==null?0:GF3HouseData.FLOOR[home.y-24];
    }

    static void load(int gui) {
        if(assetUsers>0 && a.assets!=null && a.assets.length>=BASE+16 && a.assets[BASE]!=null){assetUsers++;a.b(gui,true);return;}
        assetUsers=1;
        if(a.assets.length<BASE+16) {
            e[] enlarged=new e[BASE+16];
            System.arraycopy(a.assets,0,enlarged,0,a.assets.length);
            a.assets=enlarged;
        }
        g.open("/dh");
        for(int i=0;i<8;i++){
            e entry=new e();
            entry.a(g.read(i),0);
            a.assets[BASE+i]=entry;
        }
        g.l();
        a.b(gui,true);
    }

    static void unload() {
        leaveCache();
        if(assetUsers<=0)return;
        if(--assetUsers==0){
            if(a.assets!=null)for(int i=0;i<16 && BASE+i<a.assets.length;i++) a.assets[BASE+i]=null;
            for(int i=0;i<2;i++){menuImages[i]=null;menuFlags[i]=null;}
        }
    }

    private static short petSheet(int world) {
        // The farm releases its world registry while a full-screen menu is
        // open. Read the same numbered sheet under a temporary GUI slot.
        int id=world-1000;
        if(id<175 || id>182) throw new IllegalArgumentException();
        int slot=BASE+8+id-175;
        if(a.assets[slot]==null){
            g.open("/5");
            e sheet=new e();
            sheet.a(g.read(id),0);
            g.l();
            a.assets[slot]=sheet;
        }
        return (short)slot;
    }

    static void enterCache(int gui) {
        if(cacheActive && activeGui==gui)return;
        if(cacheActive)leaveCache();
        priorImages=a.images;
        priorFlags=a.flags;
        int slot=gui-GUI;
        if(menuImages[slot]==null){menuImages[slot]=new l[256];menuFlags[slot]=new byte[256];}
        a.images=menuImages[slot];
        a.flags=menuFlags[slot];
        cacheActive=true;activeGui=gui;
    }

    static void leaveCache() {
        if(!cacheActive) return;
        a.images=priorImages;
        a.flags=priorFlags;
        priorImages=null;
        priorFlags=null;
        cacheActive=false;activeGui=-1;
    }

    private static void show(int i,boolean on){
        short[] row=a.controls[GUI][i];
        row[row[0]==204?15:10]=(short)(on?1:0);
    }

    private static void button(int i, boolean on) {
        show(i,on);
        a.controls[GUI][i][18]=(short)(on?1:0);
    }

    private static int breed(){
        if(pet==null) return -1;
        if(pet.y==69)return 1;if(pet.y==71)return 2;
        for(int i=0;i<4;i++) if(pet.y==BREEDS[i]) return i;
        return -1;
    }

    private static void fill() {
        short[][] rows=a.controls[GUI];
        String[] captions=a.captions[GUI];
        captions[2]=g.c(h.registry[3].rows[house][2]);
        captions[5]=GF3HouseData.TEXT[0];
        captions[6]=Integer.toString(a.e());
        captions[10]=Integer.toString(a.d());
        // Android's server currency and promotion controls don't apply offline.
        button(9,false);button(13,false);show(57,false);show(58,false);
        button(56,true);
        for(int i=0;i<5;i++){
            int base=20+7*i;
            button(base,false);
            // The inventory tile remains visible even when the item is absent.
            show(base,true);
            for(int j=1;j<=6;j++) show(base+j,false);
            button(base+5,false);
        }
        int tiles=0;
        for(int i=0;i<4;i++){
            int n=GF3DogToys.quantity(i);
            if(n<=0) continue;
            int item=22+tiles++*7;
            int[] record=h.registry[4].rows[64+i];
            rows[item][5]=petSheet(record[3]);
            rows[item][6]=(short)record[4];
            show(item,true);
            captions[item+1]="x"+n;
            show(item+1,true);
        }
        int add=25+7*tiles;
        button(add,true);
        show(add+1,true);
        captions[add+1]=GF3HouseData.TEXT[1];
        pet=resident(null);
        for(int i=60;i<80;i++) show(i,false);
        button(71,false);
        if(pet==null){
            for(int i=14;i<=18;i++) show(i,false);
            show(3,false);
            return;
        }
        int level=Math.max(0,Math.min(10,GF3Dogs.level(pet))),xp=Math.max(0,GF3Dogs.xp(pet));
        int[] record=h.registry[0].rows[pet.y];
        show(3,true);
        int b=breed();
        captions[3]=GF3PetNames.name(pet);
        rows[60][5]=petSheet(record[3]);rows[60][6]=(short)record[4];
        show(60,true);
        int max=b==0?6:b==2||pet.y==71?4:b==3?7:3;
        int mood=GF3Dogs.happiness(pet);
        for(int i=0;i<max;i++){
            int id=61+i;
            rows[id][6]=(short)(i<mood/3?61:i==mood/3?58+mood%3:58);
            if(max<6){
                rows[id][2]=(short)(a.templates[GUI][id][2]+(4-max)*22);
                rows[id][3]=(short)(a.templates[GUI][id][3]+16);
            }
            show(id,true);
        }
        show(14,level<10);show(15,level<10);
        if(level<10) progress(Math.min(100,xp*100/GF3Dogs.nextXp(level)));
        captions[18]=Integer.toString(level);
        captions[17]=level<10?xp+"/"+GF3Dogs.nextXp(level):"";
        if(level<10){
            for(int i=72;i<=74;i++)show(i,true);
            captions[74]=Integer.toString(GF3Dogs.nextBills(level));
        }
        if(b<0 || level==0 || pet.a(32)) return;
        boolean due=System.currentTimeMillis()>=GF3DogToys.nextBonus;
        for(int i=75;i<=78;i++) show(i,true);
        rows[70][6]=79;
        show(70,true);button(71,true);
        rows[71][6]=(short)(due?247:248);rows[71][18]=(short)(due?1:0);
        show(76,!due);
        captions[75]=GF3HouseData.TEXT[3];
        captions[77]=Integer.toString(GF3HouseData.BONUS[b][level-1]);
        captions[78]=GF3HouseData.TEXT[2];
        clock();
    }

    private static void clock() {
        if(pet==null || breed()<0 || GF3Dogs.level(pet)<=0 || GF3Dogs.level(pet)>10) return;
        int left=(int)Math.max(0L,(GF3DogToys.nextBonus-System.currentTimeMillis()+999L)/1000L);
        if(left==lastSecond) return;
        lastSecond=left;
        a.controls[GUI][71][6]=(short)(left==0?247:248);
        a.controls[GUI][71][18]=(short)(left==0?1:0);
        show(76,left>0);
        int days=left/86400,hours=left%86400/3600,minutes=left%3600/60;
        StringBuffer duration=new StringBuffer();
        if(days>0)duration.append(days).append(GF3HouseData.TEXT[4]);
        if(hours>0)duration.append(' ').append(hours).append(GF3HouseData.TEXT[5]);
        if(minutes>0)duration.append(' ').append(minutes).append(GF3HouseData.TEXT[6]);
        duration.append(' ').append(left%60).append(GF3HouseData.TEXT[7]);
        a.captions[GUI][76]=duration.toString();
        if(left==0){a.gf();a.H(GUI);}
    }

    private static void progress(int percent){
        short[][] rows=a.controls[GUI];
        e sheet=a.assets[rows[14][5]];
        int bottom=rows[14][6],top=rows[15][6],max=Integer.MIN_VALUE;
        int start=sheet.c[bottom];
        for(int i=0;i<sheet.j(bottom);i++) max=Math.max(max,sheet.b(start+i));
        int count=sheet.j(top);
        if(count>=2) sheet.a(sheet.c[top]+count-2,max*percent/100);
        a.images[top]=null;
    }

    static void draw(int gui){
        boolean overlay=!cacheActive || activeGui!=gui;
        if(overlay)enterCache(gui);
        String[] text=a.captions[gui];
        try {
            a.captions[gui]=emptyCaptions;
            try {a.F(gui);} finally {a.captions[gui]=text;}
            for(int i=0;i<text.length && i<a.controls[gui].length;i++){
                if(text[i]==null || a.controls[gui][i]==null || a.controls[gui][i][0]!=204 || a.controls[gui][i][15]!=1)continue;
                if(gui==GUI && i>=26 && i<=54 && (i-26)%7==0)
                    a.b(text[i],gui,i,i==54?11:0,0);
                else
                    a.a(text[i],gui,i,0,0);
            }
        }finally{
            if(overlay)leaveCache();
        }
    }

    static boolean dispatch(int event,int index){
        int[] stack=a.states;
        if(stack==null || index<0 || index>=stack.length)return false;
        if(stack[index]==49) return GF3PetNames.screen(event);
        if(stack[index]!=SCREEN) return a.gf3PreviousScreen(event,index);
        if(event==0) load(GUI);
        if(event==1){
            enterCache(GUI);
            a.E(GUI);
            lastSecond=-1;
            fill();
            a.gf();
            a.H(GUI);
        }
        if(event==2){
            int key=g.i();
            if(key==19||key==11){if(GF3DogTutorial.closeHouse()){a.c(61);a.t();}}
            else{
                clock();
                GF3DogTutorial.house();
                int hint=GF3DogTutorial.hint();
                show(68,hint==68);show(69,hint==69);
            }
        }
        if(event==3) draw(GUI);
        if(event==4) leaveCache();
        if(event==5){
            unload();
            pet=null;
        }
        return false;
    }

    static void hit(int control){
        if((control>>>16)==29){GF3PetNames.hit(control&65535);return;}
        if((control>>>16)!=GUI){a.gf3PreviousHit(control);return;}
        int id=control&65535;
        if(id==56){if(GF3DogTutorial.closeHouse()){a.c(57);a.t();}return;}
        if(id==71 && pet!=null && !pet.a(32) && breed()>=0 && GF3Dogs.level(pet)>0 && GF3Dogs.level(pet)<=10 &&
                System.currentTimeMillis()>=GF3DogToys.nextBonus){
            a.c(61);
            a.g(GF3HouseData.BONUS[breed()][GF3Dogs.level(pet)-1]);
            GF3DogToys.nextBonus=System.currentTimeMillis()+86400000L;
            GF3DogTutorial.claimed();
            a.c(true);
            fill();
            a.gf();a.H(GUI);
        } else if(id>=25 && id<=53 && (id-25)%7==0 && GF3DogTutorial.hint()<0){
            a.c(61);
            a.d(4,4,true);
        }
    }
}
