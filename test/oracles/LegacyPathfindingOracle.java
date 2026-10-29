// Reference reconstruction of GLLibPathFinding s.b/h/i/j from the APK's
// fallback instruction listing. Uses Java's actual byte/short/int semantics.
// Source: source/game-java/c/c/a/a/a/w/s.java; fallback labels L142, L27e,
// L37c, L4cb, and i:L11. Default JADX b/i contain invalid control flow.
// Regenerate: java test/oracles/LegacyPathfindingOracle.java > test/world/fixtures/pathfinding.json
import java.util.*;

class LegacyPathfindingOracle {
    static final int[] D = {0,-1,0,1,-1,0,1,0,-1,-1,1,-1,-1,1,1,1};
    short[] parent, prev, next, g, h;
    byte[] map;
    int width, height, straight, diagonal, turn, dirs, mask, head;
    boolean soft;
    LegacyPathfindingOracle(int w, int ht, int[] input, int sc, int dc, int tc, int directions, int m, boolean s) {
        width=w; height=ht; straight=sc; diagonal=dc; turn=tc; dirs=directions; mask=m; soft=s;
        map=new byte[input.length]; for(int j=0;j<input.length;j++) map[j]=(byte)input[j];
        parent=new short[9216]; prev=new short[9216]; next=new short[9216]; g=new short[9216]; h=new short[9216];
    }
    boolean wall(int x,int y) {return (map[y*width+x]&mask)!=0;}
    int cost(int x,int y,int nx,int ny,int d,boolean start) {
        int c=straight, severe=straight*1000, mild=straight*10;
        boolean inWall=!start&&wall(x,y);
        if(d>=4) {
            c=diagonal;
            if(!inWall) {
                if(d==4 && (wall(x-1,y)||wall(x,y-1))) c+=severe;
                else if(d==5 && (wall(x+1,y)||wall(x,y-1))) c+=severe;
                else if(d==6 && (wall(x-1,y)||wall(x,y+1))) c+=severe;
                else if(d==7 && (wall(x+1,y)||wall(x,y+1))) c+=severe;
            }
        }
        if(!wall(nx,ny))return c;
        if(inWall)return c+mild;
        return c<severe?c+severe:c;
    }
    void insert(int node) {
        if(head==-1){head=node;return;}
        int score=g[node]+h[node], cursor=head;
        while(cursor!=-1) {
            if(score<g[cursor]+h[cursor]) {
                if(prev[cursor]==-1)head=node;
                else next[prev[cursor]]=(short)node;
                prev[node]=prev[cursor]; next[node]=(short)cursor; prev[cursor]=(short)node;return;
            }
            if(next[cursor]==-1){next[cursor]=(short)node;prev[node]=(short)cursor;return;}
            cursor=next[cursor];
        }
    }
    void remove(int node) {
        if(next[node]!=-1)prev[next[node]]=prev[node];
        if(head==node)head=next[node];
        else if(prev[node]!=-1)next[prev[node]]=next[node];
        prev[node]=-1;next[node]=-1;
    }
    int[] find(int sx,int sy,int direction,int tx,int ty,int rx,int ry,int rw,int rh,boolean directional) {
        if(rx<0){rw+=rx;rx=0;} if(ry<0){rh+=ry;ry=0;}
        Arrays.fill(parent,(short)-1);Arrays.fill(prev,(short)-1);Arrays.fill(next,(short)-1);
        Arrays.fill(g,(short)0);Arrays.fill(h,(short)0);head=-1;
        int start=(sy-ry)*rw+(sx-rx), current=start;tx-=rx;ty-=ry;
        while(current!=-1) {
            remove(current);short currentCost=g[current];g[current]=-1;h[current]=-1;
            int x=current%rw,y=current/rw;
            if(x==tx&&y==ty)break;
            for(int d=0;d<dirs;d++) {
                if(directional&&(map[width*y+x]&mask&(1<<d))==0)continue;
                int nx=x+D[2*d],ny=y+D[2*d+1];
                if(nx<0||nx>=rw||ny<0||ny>=rh)continue;
                int n=ny*rw+nx;if(g[n]==-1)continue;
                int step;
                if(soft)step=cost(x+rx,y+ry,nx+rx,ny+ry,d,current==start);
                else {
                    step=straight;
                    if(d>=4){
                        step=diagonal;
                        if(!directional){
                            if(d==4&&(wall(x-1+rx,y+ry)||wall(x+rx,y-1+ry)))continue;
                            if(d==5&&(wall(x+1+rx,y+ry)||wall(x+rx,y-1+ry)))continue;
                            if(d==6&&(wall(x-1+rx,y+ry)||wall(x+rx,y+1+ry)))continue;
                            if(d==7&&(wall(x+1+rx,y+ry)||wall(x+rx,y+1+ry)))continue;
                        }
                    }
                    if(!directional&&wall(nx+rx,ny+ry))continue;
                }
                int score=currentCost+step+(direction==d?0:turn);
                int ax=Math.abs(nx-tx),ay=Math.abs(ny-ty), estimate;
                if(dirs==4)estimate=straight*(ax+ay);
                else if(ax>ay)estimate=diagonal*ay+straight*(ax-ay);
                else estimate=diagonal*ax+straight*(ay-ax);
                if(prev[n]==-1&&next[n]==-1&&head!=n){parent[n]=(short)current;g[n]=(short)score;h[n]=(short)estimate;insert(n);}
                else if(g[n]>score){parent[n]=(short)current;g[n]=(short)score;remove(n);insert(n);}
            }
            current=head;
            if(current!=-1) {
                int p=parent[current],xNow=current%rw,xPrevious=p%rw;
                // L4de is a != comparison, even for movement toward smaller Y.
                if(xNow!=xPrevious)direction=xNow>xPrevious?3:2;
                else direction=current/rw!=p/rw?1:0;
            }
        }
        if(current==-1)return new int[0];
        ArrayList<Integer> path=new ArrayList<>();
        while(current!=-1){path.add((int)(short)(((current/rw+ry)*width)+(current%rw)+rx));current=parent[current];}
        return path.stream().mapToInt(Integer::intValue).toArray();
    }
    static boolean comma=false;
    static void emit(String name,int w,int ht,int[] map,int sc,int dc,int tc,int dirs,int mask,boolean soft,int sx,int sy,int direction,int tx,int ty,int rx,int ry,int rw,int rh,boolean directional) {
        LegacyPathfindingOracle p=new LegacyPathfindingOracle(w,ht,map,sc,dc,tc,dirs,mask,soft);
        int[] route=p.find(sx,sy,direction,tx,ty,rx,ry,rw,rh,directional);
        if(comma)System.out.println(",");comma=true;
        System.out.print("{\"name\":\""+name+"\",\"width\":"+w+",\"height\":"+ht+",\"map\":"+Arrays.toString(map)+",\"straight\":"+sc+",\"diagonal\":"+dc+",\"turn\":"+tc+",\"dirs\":"+dirs+",\"mask\":"+mask+",\"soft\":"+soft+",\"start\":["+sx+","+sy+"],\"direction\":"+direction+",\"target\":["+tx+","+ty+"],\"region\":["+rx+","+ry+","+rw+","+rh+"],\"directional\":"+directional+",\"reverse\":"+Arrays.toString(route)+"}");
    }
    public static void main(String[] args) {
        System.out.println("[");
        int[] empty=new int[25];
        emit("equal_score_four",5,5,empty,10,14,0,4,-1,false,0,0,0,4,4,0,0,5,5,false);
        emit("equal_score_eight",5,5,empty,10,14,0,8,-1,false,0,0,0,4,4,0,0,5,5,false);
        emit("vertical_direction_quirk",5,5,empty,10,14,7,4,-1,false,4,4,0,0,0,0,0,5,5,false);
        emit("start_equals_target",5,5,empty,10,14,0,8,-1,false,2,2,0,2,2,0,0,5,5,false);
        emit("clipped_negative_region",5,5,empty,10,14,1,8,-1,false,0,0,0,2,2,-1,-1,4,4,false);
        emit("outside_target",5,5,empty,10,14,0,8,-1,false,1,1,0,4,4,1,1,3,3,false);
        int[] corner={0,1,0,1,0,0,0,0,0};
        emit("no_corner_cut",3,3,corner,10,14,0,8,-1,false,0,0,0,2,2,0,0,3,3,false);
        emit("soft_corner",3,3,corner,10,14,0,8,-1,true,0,0,0,2,2,0,0,3,3,false);
        emit("short_cost_overflow",5,5,empty,10000,14000,1000,8,-1,false,0,0,0,4,4,0,0,5,5,false);
        Random random=new Random(0x47);
        for(int seed=0;seed<80;seed++) {
            int w=5+random.nextInt(5),ht=5+random.nextInt(5),dirs=seed%2==0?4:8;
            boolean directional=seed%7==0,soft=seed%5==0;
            int[] map=new int[w*ht];
            for(int i=0;i<map.length;i++)map[i]=directional?random.nextInt(256):(random.nextInt(5)==0?1:0);
            int rx=seed%3==0?1:0,ry=rx,rw=w-rx,rh=ht-ry;
            int sx=rx+random.nextInt(rw),sy=ry+random.nextInt(rh),tx=rx+random.nextInt(rw),ty=ry+random.nextInt(rh);
            if(!directional){map[sy*w+sx]=0;map[ty*w+tx]=0;}
            emit("seed_"+seed,w,ht,map,10,14,seed%4,dirs,-1,soft,sx,sy,random.nextInt(dirs),tx,ty,rx,ry,rw,rh,directional);
        }
        System.out.println("\n]");
    }
}
