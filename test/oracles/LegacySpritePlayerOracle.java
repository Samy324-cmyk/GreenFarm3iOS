// GLLibPlayer instance state from t.l/n/o/p/q/r/s0, with the update branch
// checked against fallback labels L1d/L51/L87. No Android classes are executed.
// Regenerate: java test/oracles/LegacySpritePlayerOracle.java > test/render/fixtures/player.json
import java.nio.file.*;
import java.util.*;

class LegacySpritePlayerOracle {
    int[][] frameIds, units;
    int animation=-1, frame=0, elapsed=0, unit=0, loops=1, transform=0;
    boolean over=true, single;
    LegacySpritePlayerOracle(boolean s) throws Exception {
        single=s;
        List<String> lines=Files.readAllLines(Path.of("test/render/fixtures/animation_units.txt"));
        frameIds=new int[lines.size()][];units=new int[lines.size()][];
        for(int i=0;i<lines.size();i++) {
            String[] entries=lines.get(i).split(","); frameIds[i]=new int[entries.length];units[i]=new int[entries.length];
            for(int j=0;j<entries.length;j++){String[] pair=entries[j].split(":");frameIds[i][j]=Integer.parseInt(pair[0]);units[i][j]=Integer.parseInt(pair[1]);}
        }
        set(-1,-1,-1);
    }
    int totalUnits(int id){return id<0?-1:Arrays.stream(units[id]).sum();}
    void set(int id,int count,int duration){
        if(over||id!=animation){animation=id;unit=duration==-1?40:duration/totalUnits(id);setFrame(0);loops=count-1;over=false;}
    }
    int setFrame(int f){if(animation<0)return -1;frame=f%units[animation].length;elapsed=0;return frame;}
    int duration(){return animation<0?0:units[animation][frame]*unit;}
    void update(int dt){
        if(over||animation<0)return;
        int d=duration();if(d==0)return;
        if(!single){
            while(elapsed>=d){
                elapsed-=d;
                if(frame<units[animation].length-1)frame++;
                else if(loops==0){over=true;break;}
                else{if(loops>0)loops--;frame=0;}
                d=duration();if(d==0)break;
            }
        }else if(elapsed>=d){
            elapsed-=d;
            if(frame<units[animation].length-1)frame++;
            else if(loops==0)over=true;
            else{if(loops>0)loops--;frame=0;}
        }
        elapsed+=dt;
    }
    void operation(String op){
        String[] p=op.split(":");
        if(p[0].equals("set"))set(Integer.parseInt(p[1]),Integer.parseInt(p[2]),Integer.parseInt(p[3]));
        else if(p[0].equals("update"))update(Integer.parseInt(p[1]));
        else if(p[0].equals("frame"))setFrame(Integer.parseInt(p[1]));
        else if(p[0].equals("transform")){int c=Integer.parseInt(p[1]);int[] m={0,2,1,3,5,4,7,6};if(c>=0&&c<8)transform=m[c];}
    }
    String snapshot(){return Arrays.toString(new int[]{animation,frame,elapsed,unit,loops,over?1:0,animation<0?-1:frameIds[animation][frame],transform});}
    static boolean comma=false;
    static void emit(String name,boolean single,String...ops)throws Exception{
        LegacySpritePlayerOracle p=new LegacySpritePlayerOracle(single);
        if(comma)System.out.println(",");comma=true;
        System.out.print("{\"name\":\""+name+"\",\"single\":"+single+",\"steps\":[");
        for(int i=0;i<ops.length;i++){if(i>0)System.out.print(",");p.operation(ops[i]);System.out.print("{\"op\":\""+ops[i]+"\",\"state\":"+p.snapshot()+"}");}
        System.out.print("]}");
    }
    public static void main(String[]args)throws Exception{
        System.out.println("[");
        emit("completion_and_late_delta",false,"set:0:1:-1","update:0","update:200","update:0","update:199","update:1","update:1","update:10000","update:77","update:999");
        emit("same_animation_does_not_restart",false,"set:0:1:-1","update:200","update:0","set:0:9:17","update:10000","update:0","set:0:2:5000");
        emit("infinite_variable_units",false,"set:1:-1:-1","update:2800","update:16000","update:0","update:40","update:0");
        emit("two_loops",false,"set:1:2:3000","update:5000","update:1","update:4000","update:0","update:99");
        emit("single_step_catchup",true,"set:0:2:-1","update:2000","update:0","update:0","update:0","update:0","update:0");
        emit("zero_unit_duration_freezes",false,"set:0:1:1","update:99999","update:1","set:1:1:1","update:1000");
        emit("modulo_frame_and_transform",false,"set:0:-1:-1","frame:42","update:50","frame:19","transform:0","transform:1","transform:2","transform:3","transform:4","transform:5","transform:6","transform:7","transform:99");
        emit("elapsed_java_overflow",true,"set:0:-1:-1","update:2147483647","update:2147483647","update:0");
        emit("stop_animation",false,"set:0:1:-1","update:50","set:-1:-1:-1","update:1000","set:1:1:-1");
        System.out.println("\n]");
    }
}
