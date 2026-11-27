import java.io.IOException;

/** Offline branch of cGame's level-fifteen beekeeping lesson, 1060 through 1082. */
final class GF3HoneyTutorial {
    private static final f[] found=new f[1];
    private static int stage;
    private static boolean speaking,focused,harvested,jarMade,redraw,growing,smoked;
    private static f hive;
    private static boolean smokeAllowed;
    private static long stageAt;
    private static int redrawFrames;

    private static boolean active() {
        if(a.bD==null || a.cb==null || !a.h(9302) || !a.h(9303))return false;
        for(int i=0;i<a.bD.length;i++)if(a.bD[i]==9302 || a.bD[i]==9303 || a.bD[i]==9297 || a.bD[i]==9299)return false;
        for(int i=0;i<a.bD.length;i++) if(a.bD[i]==9304 && a.cb[i]==2) return true;
        return false;
    }

    static int phase() {return stage;}

    private static void pointer(int panel,int index) {
        if(a.controls==null || a.controls[panel]==null || index>=a.controls[panel].length)return;
        short[] marker=a.controls[panel][index];short visible=marker[10];
        try{marker[10]=1;a.a(panel,marker,0,0,index);}finally{marker[10]=visible;}
    }

    static void drawPress() {
        if(stage==1077) pointer(22,192);
        else if(stage==1078) pointer(22,193);
        else if(stage==1079) pointer(22,191);
    }

    static boolean inventory(int phase) {
        boolean handled=a.gf3HoneyInventory(phase);
        if(phase==3 && stage==1071) pointer(10,69);
        return handled;
    }

    private static void go(int target) {
        stage=target; speaking=false; focused=false;smokeAllowed=false;stageAt=System.currentTimeMillis();
    }

    private static f find(int type,int row) {
        for(int layer=0;layer<2;layer++)
            if(f.a(layer,type,row,found,1)>0) return found[0];
        return null;
    }

    private static f colony() {
        f normal=find(52,22);
        return normal!=null?normal:find(52,23);
    }

    private static void focus(f target) {
        if(focused || target==null || a.c==null) return;
        a.c.a(target.r,target.s,0);
        a.a(target,0,-70);
        k.f();redrawFrames=3;
        focused=true;
    }

    private static boolean line(int id) {
        if(speaking) return true;
        speaking=true;
        redraw=true;
        // The original pack includes Android's beekeeper portrait in slot 136.
        if(a.assets[136]==null) {
            g.open("/7"); e portrait=new e();portrait.a(g.readEntry(136),0);g.l();
            a.assets[136]=portrait;
        }
        a.a(GF3HoneyWords.line(id),136,0);
        return false;
    }

    static void harvest(int id,int quantity) {
        if(stage==1069 && (id==3022 || id==3023) && quantity>0) harvested=true;
    }

    static boolean requestSmoke() {
        if(stage==0) return true;
        if(stage!=1073 || System.currentTimeMillis()-stageAt<300) return false;
        smokeAllowed=true;
        return true;
    }

    static boolean canSmoke() {return stage==0 || (stage==1073 && smokeAllowed);}

    static boolean refill() {
        if(stage!=1077) return false;
        int[] recipe=h.tables[7].rows[93];
        int missing=recipe[7]-a.g(0,recipe[6]);
        if(missing>0 && !a.stock(0,recipe[6],missing)) return false;
        go(1078);
        return true;
    }

    static void extracted() {if(stage==1078) jarMade=true;}
    static void extractionFinished() {if(stage==1078 && jarMade) go(1079);}

    static void kitchen() {
        if(stage==1075) {
            int[] recipe=h.tables[7].rows[93];
            go(a.g(0,recipe[6])>=recipe[7]?1078:1076);
        } else if(stage==1076 && line(12354)) go(1077);
    }

    static boolean farm(int event) {
        if(event==3 && redrawFrames>0 && a.F==0) {
            a.redrawActors=true;redrawFrames--;
        }
        boolean handled=a.gf3HoneyFarm(event);
        if(event==1 && redraw && a.F==0 && a.a()==17) {k.f();redrawFrames=3;redraw=false;}
        if(event!=2 || a.F!=0 || a.a()!=17 || a.transition!=-1 || a.c==null) return handled;
        if(!active()) {
            if(stage!=0) {go(0);hive=null;harvested=false;jarMade=false;growing=false;smoked=false;}
            return handled;
        }
        if(stage==0) go(1060);
        switch(stage) {
            case 1060: go(1061);break;
            case 1061:
                if(line(12349)) go(GF3HomePredator.thief()==0?1066:1062);
                break;
            case 1062: if(line(12356)) go(1063);break;
            case 1063:
                int predator=GF3HomePredator.thief();
                if(predator!=0) focus(find(54,predator==1?73:74));
                go(1064);break;
            case 1064: if(GF3HomePredator.thief()==0) go(1065);break;
            case 1065: if(line(12357)) go(1066);break;
            case 1066: case 1067:
                hive=colony();
                if(hive==null) break;
                if(!growing) {hive.h(2);growing=true;}
                focus(hive);
                if(hive.D==3) {a.a(false,null);go(1068);}
                else if(a.selected==hive) {
                    hive.K=0;
                    a.captions[1][5]="0";
                    if(stage==1066) go(1067);
                }
                break;
            case 1068: if(line(12350)) go(1069);break;
            case 1069:
                hive=colony();focus(hive);
                if(harvested && f.a(2,47,-1,found,1)==0) {
                    a.objective(3022,1,48,false);
                    go(1070);
                }
                break;
            case 1070:
                if(line(12351)) {go(1071);a.dW=0;a.a(28);}
                break;
            case 1071: go(1072);break;
            case 1072: if(line(12352)) go(1073);break;
            case 1073:
                hive=colony();
                if(hive==null) break;
                if(!focused && hive.D!=6 && !smoked && hive.D!=5) hive.h(5);
                focus(hive);
                if(hive.D==6) smoked=true;
                if(smoked && hive.D==2) go(1074);
                break;
            case 1074: if(line(12353)) go(1075);break;
            case 1075: case 1076: case 1077: case 1078: focus(find(50,28));break;
            case 1079: go(1080);break;
            case 1080: go(1081);break;
            case 1081: if(line(12355)) go(1082);break;
            case 1082:
                a.objective(6093,1,48,false);go(0);hive=null;harvested=false;jarMade=false;growing=false;smoked=false;
                break;
        }
        return handled;
    }

    static void write(String name,byte[] main) throws IOException {
        if(stage==0) {GF3HomePredator.write(name,main);return;}
        byte[] data=new byte[main.length+7];
        System.arraycopy(main,0,data,0,main.length);
        data[main.length]=(byte)(stage-1060);
        data[main.length+1]=(byte)((harvested?1:0)|(growing?2:0)|(smoked?4:0));data[main.length+2]=(byte)(jarMade?1:0);
        data[main.length+3]='B';data[main.length+4]='E';data[main.length+5]='E';data[main.length+6]=1;
        GF3HomePredator.write(name,data);
    }

    static byte[] read(String name) throws IOException {
        byte[] data=GF3HomePredator.read(name);go(0);redraw=false;redrawFrames=0;hive=null;harvested=false;jarMade=false;growing=false;smoked=false;
        if(data==null || data.length<7) return data;
        int n=data.length-7;
        if(data[n+3]!='B'|| data[n+4]!='E'||data[n+5]!='E'||data[n+6]!=1) return data;
        int phase=1060+(data[n]&255);
        if(phase>1082) throw new IOException();
        harvested=(data[n+1]&1)!=0; growing=(data[n+1]&2)!=0;smoked=(data[n+1]&4)!=0;jarMade=data[n+2]!=0;
        if(phase==1078 && jarMade) phase=1079;
        if(phase==1071) phase=1070;
        go(phase);
        byte[] main=new byte[n];System.arraycopy(data,0,main,0,n);return main;
    }
}
