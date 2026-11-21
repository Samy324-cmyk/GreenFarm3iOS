/** Android's animal, pet, and field subcategories over the original MIDP purchase handlers. */
final class GF3MarketFront {
    private static final int GUI=2, PET_BUTTON=122, PET_ACTIVE=123, PET_ICON=124, TAG=64;
    private static final int BACKGROUND_SHEET=171;
    private static int tab=-1, first=-1, shelf=-1;
    private static boolean installing;

    private static void show(int row,boolean visible,boolean hit) {
        short[] control=a.controls[GUI][row];control[10]=(short)(visible?1:0);
        control[18]=(short)(hit?1:0);
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
        rows[125][15]=(short)(tab==5?1:0);
        show(126,tab==5,false);
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
        tab=index;
        if(tab==0 || tab==1 || tab==4) categories(tab);
        else if(tab==2 || tab==3) selectShelf(tab==2?12:13);
        else {
            // Android only inserts a promotional animal when its timed
            // offer has arrived. Four banked MIDP rows use category -1.
            first=shelf=-1;a.gf3MarketPopulate(0,TAG-1);a.cv=-1;
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
                if(shelf>=0) selectShelf(shelf); else if(first>=0) categories(tab);
                nav();
            }
        }
        if(phase==3 && tab==0 && first==9 && GF3HiveLimits.capacity()>0){
            short[][] rows=a.controls[GUI];
            // Android panel 2/36 draws the tally over the third crop family.
            int offset=rows[56][2]-rows[28][2];
            a.a(Integer.toString(GF3HiveLimits.owned())+"/"+GF3HiveLimits.capacity(),GUI,27,offset,20);
        }
        if(phase==3 && tab==5)a.a(GF3MarketRows.empty,GUI,125,0,0);
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
