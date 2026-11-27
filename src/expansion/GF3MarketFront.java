import java.util.Calendar;
import java.util.Random;
import javax.microedition.lcdui.Image;
import javax.microedition.lcdui.Graphics;
import java.io.IOException;

/** Android's animal, pet, and field subcategories over the original MIDP purchase handlers. */
final class GF3MarketFront {
    private static final int GUI=2, PET_BUTTON=122, PET_ACTIVE=123, PET_ICON=124, TAG=64;
    private static final int BACKGROUND_SHEET=171;
    private static int tab=-1, first=-1, shelf=-1;
    private static boolean installing;
    private static Image billPreview,offerClock;
    private static String timer;
    private static long timerSecond=-1;
    // A local RMS record makes the lottery stable across shop visits and restarts.
    // The date key is based on the local civil day, not elapsed UTC hours (DST safe).
    private static final String OFFER_SAVE="GF3-DAILY-1";
    private static int offerWeek=-1, offerCount, offerRedeemed;
    private static final int[] offerIds=new int[3], offerDiscount=new int[3], offerCoins=new int[3], offerBills=new int[3];
    private static boolean offersLoaded;

    static int dayKey(int year,int month,int day) {
        int y=year-(month<=2?1:0);
        int era=y/400, yoe=y-era*400;
        int doy=(153*(month+(month>2?-3:9))+2)/5+day-1;
        int days=era*146097+yoe*365+yoe/4-yoe/100+doy-719468;
        return days; // Local civil date, not an elapsed 24-hour interval.
    }

    private static int currentDay() {
        try {
            Calendar c=Calendar.getInstance();
            return dayKey(c.get(Calendar.YEAR),c.get(Calendar.MONTH)+1,c.get(Calendar.DATE));
        }catch(Exception unsupported) {
            return (int)((System.currentTimeMillis()/86400000L));
        }
    }

    static int secondsToReset(int h,int m,int s){return 86400-h*3600-m*60-s;}
    private static String two(int n){return n<10?"0"+n:Integer.toString(n);}
    static String countdown(){
        Calendar c=Calendar.getInstance();
        int seconds=secondsToReset(c.get(Calendar.HOUR_OF_DAY),c.get(Calendar.MINUTE),c.get(Calendar.SECOND));
        return "Próxima rotación en: "+two(seconds/3600)+"h "+two(seconds/60%60)+"m "+two(seconds%60)+"s";
    }

    private static int getInt(byte[] b,int pos) {
        return (b[pos]&255)|((b[pos+1]&255)<<8)|((b[pos+2]&255)<<16)|((b[pos+3]&255)<<24);
    }
    private static void putInt(byte[] b,int pos,int value) {
        for(int i=0;i<4;i++)b[pos+i]=(byte)(value>>>(8*i));
    }
    private static void loadOffers() {
        if(offersLoaded)return;
        offersLoaded=true;
        byte[] data=null;
        try {data=g.readOffer(OFFER_SAVE);}catch(Exception unavailable){return;}
        if(data==null || data.length!=60 || getInt(data,0)!=0x314f4647)return;
        int count=data[8]&255;
        if(count<2 || count>3)return;
        for(int i=0;i<count;i++){
            int p=12+16*i,id=getInt(data,p),discount=getInt(data,p+4),coins=getInt(data,p+8),bills=getInt(data,p+12);
            if(id< -1 || id>=68 || discount<0 || discount>50 || coins<0 || bills<0 || bills>10)return;
            if(id==-1 && (coins<=0 || bills<3))return;
            if(id>=0 && (discount<15 || chosen(id,i,offerIds)))return;
            offerIds[i]=id;offerDiscount[i]=discount;offerCoins[i]=coins;offerBills[i]=bills;
        }
        offerWeek=getInt(data,4);offerCount=count;
        offerRedeemed=(data[11]&255)&7;
    }
    private static void saveOffers() {
        byte[] data=new byte[60];
        putInt(data,0,0x314f4647);putInt(data,4,offerWeek);putInt(data,8,offerCount);data[11]=(byte)offerRedeemed;
        for(int i=0;i<offerCount;i++){
            int p=12+16*i;
            putInt(data,p,offerIds[i]);putInt(data,p+4,offerDiscount[i]);putInt(data,p+8,offerCoins[i]);putInt(data,p+12,offerBills[i]);
        }
        try {g.writeOffer(OFFER_SAVE,data);}catch(Exception unavailable){}
    }
    private static boolean chosen(int id,int used,int[] ids) {
        for(int i=0;i<used;i++)if(ids[i]==id)return true;
        return false;
    }
    private static void ensureOffers() {
        loadOffers();
        int now=currentDay();
        // A device clock rollback must not repeatedly mint a new lottery.
        if(offerWeek>=now && offerCount>=2)return;
        int[] previous=new int[3];
        System.arraycopy(offerIds,0,previous,0,offerCount);
        int oldCount=offerCount;
        Random rng=new Random(System.currentTimeMillis() ^ ((long)now<<27) ^ a.d());
        offerCount=2+rng.nextInt(2);offerWeek=now;offerRedeemed=0;
        int[][] rows=h.tables[0].rows;
        int[] candidates=new int[rows.length];int n=0;
        // Choose purchasable adults/calves, never mature variants, wild
        // animals or unique dogs. Preserve the normal level requirements.
        for(int i=0;i<rows.length;i++){
            int[] row=rows[i];
            if(row[5]>=0 && row[2]>=0 &&
               (row[6]>0 || row[7]>0) && row[8]<=a.f() &&
               (i<68) && !chosen(i,oldCount,previous))candidates[n++]=i;
        }
        if(n<offerCount)for(int i=0;i<rows.length;i++){
            int[] row=rows[i];
            if(i<68 && row[2]>=0 && row[5]>=0 &&
                (row[6]>0 || row[7]>0) && row[8]<=a.f() && !chosen(i,n,candidates))candidates[n++]=i;
        }
        // At least one animal; a second or third card can exchange farm
        // coins for a limited bundle of bills, with no real-money purchase.
        int cashSlot=rng.nextInt(2)==0?1+rng.nextInt(offerCount-1):-1;
        if(n<offerCount && n>0)cashSlot=offerCount-1;
        for(int i=0;i<offerCount;i++){
            if(i==cashSlot || n==0){
                offerIds[i]=-1;offerDiscount[i]=0;offerBills[i]=3+rng.nextInt(8);
                offerCoins[i]=offerBills[i]*(90+10*rng.nextInt(4));
            }else{
                int pick=rng.nextInt(n);offerIds[i]=candidates[pick];candidates[pick]=candidates[--n];
                offerDiscount[i]=15+5*rng.nextInt(8);offerCoins[i]=offerBills[i]=0;
            }
        }
        saveOffers();
    }

    private static int discounted(int base,int percent) {
        return base<=0?0:Math.max(1,(base*(100-percent)+99)/100);
    }
    private static void offers() {
        ensureOffers();
        h registry=h.tables[0];int[][] original=registry.rows;int old=registry.b;
        int[][] selected=new int[offerCount][];
        for(int i=0;i<offerCount;i++){
            int id=offerIds[i];int[] source=original[id<0?1:id];
            int[] row=new int[source.length];System.arraycopy(source,0,row,0,source.length);
            row[5]=i;row[9]=TAG-1;
            if(id<0){
                // Populate with a valid animal sheet first: the original card
                // initializer interprets animal sheet/frame numbers as actors.
                // The already loaded wallet icon is installed below as static UI.
                row[2]=(offerRedeemed&(1<<i))!=0?GF3MarketRows.soldLabel:GF3MarketRows.cashLabels[offerBills[i]-3];
                row[6]=offerCoins[i];row[7]=0;row[8]=0;
            }else{
                row[6]=discounted(row[6],offerDiscount[i]);row[7]=discounted(row[7],offerDiscount[i]);
            }
            selected[i]=row;
        }
        registry.rows=selected;registry.b=selected.length;
        try {a.gf3MarketPopulate(0,TAG-1);}
        finally {registry.rows=original;registry.b=old;}
    }
    // Do not write offer-specific frame, animation or cache indices into the
    // native controls. Those very same objects are reused by all six tabs.
    static void drawControl(int gui,short[] control,int x,int y,int index) {
        if(gui==GUI && tab==5 && a.a()==7 && index>=28 && index<112 &&
                a.controls!=null && a.controls[GUI]!=null) {
            int local=(index-28)/14,part=(index-28)%14,i=local+a.ct;
            if(i>=0 && i<offerCount) {
                if(offerIds[i]<0 && (part==8 || part==10 || part==13))return;
                if(part==2 && offerIds[i]<0) {
                    // The Android resource-shop pack is sheet 38/frame 0, decoded
                    // into a standalone rotated PNG. Draw even if the native
                    // placeholder preview is hidden. Never read its cache.
                    short[] card=a.controls[GUI][28+14*local];
                    if(card[10]!=1)return;
                    try {
                        if(billPreview==null)billPreview=Image.createImage("/gf3-bills.png");
                        Graphics gr=g.graphics;
                        if(gr!=null)gr.drawImage(billPreview,479-(card[3]+108),card[2]+86,Graphics.HCENTER|Graphics.VCENTER);
                    }catch(IOException missing){System.out.println("GF3 bill preview "+missing);}
                    return;
                }
                if(part==2 && control[10]==1) {
                    // Use the known, loaded currency price sheet for bills.
                    // Never pass a synthetic control to the renderer's image cache.
                    boolean cash=offerIds[i]<0;
                    short[] price=a.controls[GUI][28+14*local+5];
                    int sheet=cash?price[5]:control[5];
                    int frame=cash?114:control[6];
                    e[] bank=sheet>=1000?a.worldAssets:a.assets;
                    int slot=sheet>=1000?sheet-1000:sheet;
                    if(bank!=null && slot>=0 && slot<bank.length && bank[slot]!=null && frame>=0) {
                        e art=bank[slot];
                        if(frame<art.frames()){
                            int w=art.d(frame),h=art.e(frame),largest=Math.max(w,h);
                            if(w>0 && h>0) {
                                int scale=Math.min(100,8800/largest);
                                int old=art.palette();
                                try {
                                    if(!cash && control[9]==1 && control[8]>=0 && control[8]<255)
                                        art.setPalette(control[8]);
                                    art.paintScaled(g.graphics,frame,control[2]-(art.f(frame)+w/2)*scale/100,
                                        control[3]-(art.g(frame)+h/2)*scale/100,scale);
                                } finally {art.setPalette(old);}
                                return;
                            }
                        }
                    }
                    if(cash)return;
                }
            }
        }
        a.gf3DrawControl(gui,control,x,y,index);
    }

    private static boolean offerHit(int row){
        if(row<28 || row>=28+14*6)return false;
        int i=(row-28)/14+a.ct;
        if(i<0 || i>=offerCount || offerIds[i]>=0)return false;
        if((row-28)%14!=0)return true;
        if((offerRedeemed&(1<<i))!=0 || a.d()<offerCoins[i] || a.e()>a.maxBills-offerBills[i]){
            a.c(56);return true;
        }
        a.giveCoins(-offerCoins[i]);a.giveBills(offerBills[i]);
        offerRedeemed|=1<<i;
        saveOffers();a.saveFarm(true);a.c(49);
        offers();nav();
        return true;
    }

    private static void show(int row,boolean visible,boolean hit) {
        short[] control=a.controls[GUI][row];
        if(control[0]==204)control[15]=(short)(visible?1:0);
        else{control[10]=(short)(visible?1:0);control[18]=(short)(hit?1:0);}
    }

    private static boolean enabled() {
        return a.C==-1 && !a.i(297) && !a.i(298);
    }

    private static void nav() {
        short[][] rows=a.controls[GUI];
        if(a.assets.length<=BACKGROUND_SHEET) {
            e[] pool=new e[BACKGROUND_SHEET+1];
            System.arraycopy(a.assets,0,pool,0,a.assets.length);a.assets=pool;
        }
        if(a.assets[BACKGROUND_SHEET]==null) {
            g.openAsset("/dh"); e sheet=new e();sheet.a(g.readChunk(4),0);g.l();a.assets[BACKGROUND_SHEET]=sheet;
        }
        rows[0][5]=BACKGROUND_SHEET;rows[25][5]=BACKGROUND_SHEET;
        rows[25][6]=0;
        for(int i=0;i<5;i++) {
            int android=i==4?5:i;
            for(int set=0;set<3;set++) {
                short[] ctl=rows[10+set*5+i];
                ctl[2]=(short)GF3MarketRows.x[set*6+android];
                ctl[3]=(short)GF3MarketRows.y[set*6+android];
                if(set==1) ctl[10]=(short)(tab==android?1:0);
                else if(set==2) ctl[6]=(short)GF3MarketRows.icons[android];
            }
        }
        show(PET_BUTTON,true,true);show(PET_ACTIVE,tab==4,false);show(PET_ICON,true,false);
        rows[125][15]=(short)(tab==5 && offerCount==0?1:0);
        rows[127][15]=(short)(tab==5?1:0);
        rows[127][2]=210;rows[127][3]=427;rows[127][5]=510;rows[127][6]=31;
        show(126,false,false);
        a.gf();a.H(GUI);
    }

    private static void categories(int tabIndex) {
        first=tabIndex==0?9:tabIndex==1?0:6;
        int count=tabIndex==1?6:3;
        int[][] rows=new int[count][];
        for(int i=0;i<count;i++) rows[i]=GF3MarketRows.cards[first+i];
        h categories=h.tables[13];
        int[][] prior=categories.rows;
        int previous=categories.b;
        categories.rows=rows;categories.b=count;
        try {a.ad(0);} finally {categories.rows=prior;categories.b=previous;}
        shelf=-1;
    }

    static void populate(int table,int category) {
        if(category<TAG || category>=TAG+GF3MarketRows.items.length) {
            a.gf3MarketPopulate(table,category);return;
        }
        int id=category-TAG;
        if(GF3MarketRows.kinds[id]!=table) throw new IllegalArgumentException();
        int[] indices=GF3MarketRows.items[id];
        h registry=h.tables[table];
        int[][] prior=registry.rows;
        int previous=registry.b;
        int[][] rows=new int[indices.length][];
        for(int i=0;i<rows.length;i++) {
            int[] item=prior[indices[i]];
            rows[i]=new int[item.length];
            System.arraycopy(item,0,rows[i],0,item.length);
            rows[i][5]=i;
            if(table==0) rows[i][9]=category;
        }
        registry.rows=rows;registry.b=rows.length;
        try {a.gf3MarketPopulate(table,category);}
        finally {registry.rows=prior;registry.b=previous;}
    }

    private static void selectShelf(int id) {
        shelf=id;first=-1;
        populate(GF3MarketRows.kinds[id],TAG+id);
    }

    private static void open(int index) {
        // Select the native mode BEFORE populating. The population routine
        // itself lays out and loads the previews using cw; an offers-mode
        // value (4) must never leak into a regular category.
        tab=index;
        a.cw=index==4?1:index==5?4:index;
        if(tab==0 || tab==1 || tab==4) categories(tab);
        else if(tab==2 || tab==3) selectShelf(tab==2?12:13);
        else {
            first=shelf=-1;
            try {offers();}catch(Exception invalid){
                a.gf3MarketPopulate(0,TAG-1);offerCount=0;
            }
        }
        a.u(tab==4?1:tab==5?4:tab);
        nav();
    }

    private static void lesson(boolean category) {
        boolean calf=a.C==14;
        if(category)open(calf?1:0);
        else {a.c(61);selectShelf(calf?2:9);nav();}
        short[][] rows=a.controls[GUI];
        for(int i=0;i<rows.length;i++)if(rows[i][0]==205)
            rows[i][18]=(short)(i==(calf && category?56:28)?1:0);
        for(int i=116;i<=121;i++)rows[i][10]=0;
        short[] arrow=rows[119];
        // Android market controls 205, 209 and 207 respectively point to
        // the cow family, the Gelbvieh calf and the plot.
        arrow[2]=(short)(calf?(category?474:213):209);
        arrow[3]=(short)(calf && !category?282:284);
        arrow[6]=(short)(calf && category?2:0);
        arrow[7]=(short)(calf && category?2:0);
        arrow[10]=1;
        a.gf();a.H(GUI);
    }

    static boolean screen(int phase) {
        if(phase==0) {tab=first=shelf=-1;}
        boolean handled=a.gf3MarketScreen(phase);
        // Android's first plot purchase goes through the crop family first
        // (TF 41, 42). The original MIDP uses stage 41 for the second touch.
        if(phase==2 && a.C==41 && a.a()==7 && first!=9 && shelf!=9)
            lesson(true);
        if(phase==2 && a.C==14 && a.a()==7 && first!=0 && shelf!=2)
            lesson(true);
        if(phase==1 && enabled()) {
            if(tab<0 && (a.cv==-1 || a.cu!=0)) open(a.cw==4?5:a.cw);
            else if(tab>=0) {
                if(tab==5){if(offerCount==0)try {offers();}catch(Exception invalid){offerCount=0;}}
                else if(shelf>=0) selectShelf(shelf); else if(first>=0) categories(tab);
                nav();
            }
        }
        if(phase==3 && tab==5){
            if(offerCount==0)a.a(GF3MarketRows.empty,GUI,125,0,0);
            long second=System.currentTimeMillis()/1000L;
            if(second!=timerSecond || timer==null){timer=countdown();timerSecond=second;}
            // Native market drawing leaves a card clip active. Reset it only
            // for this footer and restore it before any subsequent overlay.
            Graphics gr=g.graphics;
            if(gr!=null){
                int x=gr.getClipX(),y=gr.getClipY(),cw=gr.getClipWidth(),ch=gr.getClipHeight();
                try{
                    gr.setClip(0,0,480,800);
                    short[] label=a.controls[GUI][127];label[15]=1;label[16]=-1;label[13]=label[14]=0;label[9]=1;
                    a.a(timer,GUI,127,0,0);
                    gr.setClip(0,0,480,800);
                    try{
                        if(offerClock==null)offerClock=Image.createImage("/gf3-offer-clock.png");
                        gr.drawImage(offerClock,479-440,185,Graphics.HCENTER|Graphics.VCENTER);
                    }catch(IOException ignored){}
                }finally{gr.setClip(x,y,cw,ch);}
            }
        }
        if(phase==3 && tab==0 && first==9 && GF3HiveLimits.capacity()>0){
            short[][] rows=a.controls[GUI];
            // Android panel 2/36 draws the tally over the third crop family.
            int offset=rows[56][2]-rows[28][2];
            a.a(Integer.toString(GF3HiveLimits.owned())+"/"+GF3HiveLimits.capacity(),GUI,27,offset,20);
        }
        if(phase==2 && tab==5 && currentDay()>offerWeek){try {offers();nav();}catch(Exception invalid){offerCount=0;}}
        if(phase==5) {
            tab=first=shelf=-1;
            if(a.assets.length>BACKGROUND_SHEET) a.assets[BACKGROUND_SHEET]=null;
        }
        return handled;
    }

    static void hit(int event) {
        int i=event&65535;
        if((event>>>16)==GUI && a.C==41 && a.a()==7 && tab==0) {
            if(i==28 && first==9) {lesson(false);return;}
            if(i!=28 || shelf!=9)return;
        }
        if((event>>>16)==GUI && a.C==14 && a.a()==7 && tab==1) {
            if(i==56 && first==0){lesson(false);return;}
            if(i!=28 || shelf!=2)return;
        }
        if((event>>>16)==GUI && a.a()==7 && enabled() && !installing) {
            if((i>=10 && i<=14) || i==PET_BUTTON) {
                installing=true;
                try {a.c(61);open(i==PET_BUTTON?4:i==14?5:i-10);}
                finally {installing=false;}
                return;
            }
            if(tab==5 && offerHit(i))return;
            if(first>=0 && i>=28 && i<=98 && (i-28)%14==0) {
                int id=first+a.ct+(i-28)/14;
                if(id<(tab==0?12:tab==1?6:9)) {a.c(61);selectShelf(id);nav();}
                return;
            }
            // The legacy first crop tile also opens the native plot-limit
            // dialog. On Android only the field tile belongs to that rule.
            if(i==28 && (shelf==10 || shelf==11)) {a.af(0);return;}
        }
        a.gf3MarketHit(event);
    }
}
