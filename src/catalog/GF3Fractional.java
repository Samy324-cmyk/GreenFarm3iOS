import java.io.DataInputStream;
import java.io.IOException;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Project the 72x36 Android modules onto the circular, rotated MIDP terrain cache. */
final class GF3Fractional {
    private static final int BLOCK_W=72,BLOCK_H=36,PIXELS=72*36;
    private static final int[] rgba=new int[PIXELS];
    private static final int[] cellX=new int[BLOCK_W],sampleX=new int[BLOCK_W],fractionX=new int[BLOCK_W];
    private static int[] colors;
    private static boolean active(){return a.B>50 && a.B<100;}
    static boolean prescaled(int id){return !active() && a.zoomPreScaled(id);}
    static int centerX(){return (a.camera.r+400)*100/a.B;}
    static int centerY(){return (a.camera.s+240)*100/a.B;}
    static void center(int z,int x,int y){a.camera.c(x*z/100-400,y*z/100-240);}
    private static void extent(int z){
        int[] state=k.state[0];
        state[5]=state[2]*BLOCK_W*z/100;
        state[6]=state[3]*BLOCK_H*z/100;
    }
    static void loadMap(){
        a.loadZoomMap();
        if(active())extent(a.B);
    }
    static void zoom(int z){
        if(z==a.B)return;
        if(z==50 || a.B==50 || a.camera==null){
            f.changeZoom(z);
            if(active())extent(z);
        }else{
            int x=centerX(),y=centerY();
            a.B=z;
            extent(z);
            center(z,x,y);
            k.invalidate();
            a.l=true;
        }
    }
    static int tileSheet(){return a.B==50?158:0;}
    static int mapZoom(){return a.B==50?50:100;}
    private static void load(){
        if(colors!=null)return;
        DataInputStream data=new DataInputStream(new GF3Fractional().getClass().getResourceAsStream("/tiles.rgb"));
        try{
            int[] palette=new int[data.readUnsignedShort()];
            for(int i=0;i<palette.length;i++) {
                int c=(data.readUnsignedByte()<<16)|(data.readUnsignedByte()<<8)|data.readUnsignedByte();
                palette[i]=c==0xff00ff?0:0xff000000|c;
            }
            int[] expanded=new int[48*PIXELS];
            byte[] row=new byte[PIXELS];
            for(int m=0;m<48;m++){
                data.readFully(row);
                for(int i=0;i<PIXELS;i++)expanded[m*PIXELS+i]=palette[row[i]&255];
            }
            data.close();
            colors=expanded;
        }catch(IOException ex){throw new IllegalStateException("tiles.rgb");}
    }
    // The red and blue lanes fit into one integer with an 8-bit fixed-point weight.
    private static int mix(int a,int b,int weight){
        if(a==b || weight==0)return a;
        int rb=(((a&0xff00ff)*(256-weight)+(b&0xff00ff)*weight+0x800080)>>>8)&0xff00ff;
        int g=(((a&0x00ff00)*(256-weight)+(b&0x00ff00)*weight+0x008000)>>>8)&0x00ff00;
        return 0xff000000|rb|g;
    }
    private static int axis(int physical,int z) {
        // GLES texels are centred at half-integers; destination pixel centres
        // determine their bilinear footprint on the full-resolution module.
        return ((physical*100+50)*256)/z-128;
    }
    private static int renderedZoom;
    private static byte[] renderedMap,renderedFlips;
    private static final int CAPACITY=96;
    private static final Image[] images=new Image[CAPACITY];
    private static final int[] keys=new int[CAPACITY];
    private static final int[][] terrainIds=new int[CAPACITY][9];
    private static int nextImage;
    private static void resetCache(int z,byte[] map,byte[] flips){
        if(renderedZoom==z && renderedMap==map && renderedFlips==flips)return;
        for(int i=0;i<CAPACITY;i++)images[i]=null;
        renderedZoom=z;renderedMap=map;renderedFlips=flips;
        nextImage=0;
    }
    private static final int[] ids=new int[9];
    private static Image block(int bx,int by,int columns,int rows,int z,byte[] map,byte[] flips){
        // At >50%, one physical cache block can cross up to three source tiles per axis.
        int startX=bx*BLOCK_W,startY=by*BLOCK_H;
        int firstX=(startX*100)/z/BLOCK_W,firstY=(startY*100)/z/BLOCK_H;
        for(int j=0;j<3;j++)for(int i=0;i<3;i++){
            int x=firstX+i,y=firstY+j;
            int key=255;
            if(x>=0 && x<columns && y>=0 && y<rows){int index=y*columns+x;
                key=(map[index]&255) | ((flips==null?0:flips[index]&3)<<8);}
            ids[j*3+i]=key;
        }
        int blockKey=(by<<16) | (bx&65535);
        for(int i=0;i<CAPACITY;i++)if(images[i]!=null && keys[i]==blockKey){
            int j=0;while(j<9 && ids[j]==terrainIds[i][j])j++;
            if(j==9)return images[i];
        }
        for(int x=0;x<BLOCK_W;x++){
            int physical=startX+x,fp=axis(physical,z);
            int tx=physical<0?-1:(fp+128)/(BLOCK_W*256);
            int pos=Math.max(0,Math.min((BLOCK_W-1)*256,fp-tx*BLOCK_W*256));
            cellX[x]=tx;sampleX[x]=pos>>8;fractionX[x]=pos&255;
        }
        for(int y=0;y<BLOCK_H;y++){
            int physical=startY+y,fp=axis(physical,z);
            int ty=physical<0?-1:(fp+128)/(BLOCK_H*256);
            int pos=Math.max(0,Math.min((BLOCK_H-1)*256,fp-ty*BLOCK_H*256));
            int sourceY=pos>>8,wy=pos&255;
            for(int x=0;x<BLOCK_W;x++){
                int tx=cellX[x],rgb=0;
                if(tx>=0 && tx<columns && ty>=0 && ty<rows) {
                    int v=ids[(ty-firstY)*3+(tx-firstX)],id=v&255;
                    if(id<48){
                        int fx=(v&256)==0?1:-1,fy=(v&512)==0?1:-1;
                        int iy=fy==1?sourceY:BLOCK_H-1-sourceY;
                        int offset=id*PIXELS+iy*BLOCK_W+(fx==1?sampleX[x]:BLOCK_W-1-sampleX[x]);
                        int c00=colors[offset],wx=fractionX[x];
                        int c0=wx==0?c00:mix(c00,colors[offset+fx],wx);
                        if(wy==0)rgb=c0;
                        else{
                            int next=offset+fy*BLOCK_W,c10=colors[next];
                            int c1=wx==0?c10:mix(c10,colors[next+fx],wx);
                            rgb=mix(c0,c1,wy);
                        }
                    }
                }
                rgba[x*BLOCK_H+BLOCK_H-1-y]=rgb;
            }
        }
        int slot=nextImage;
        nextImage=(nextImage+1)%CAPACITY;
        keys[slot]=blockKey;
        System.arraycopy(ids,0,terrainIds[slot],0,9);
        images[slot]=Image.createRGBImage(rgba,BLOCK_H,BLOCK_W,true);
        return images[slot];
    }
    static void tiles(Graphics gc,int layer,int bx,int by,int wlast,int hlast,int ox,int oy,boolean local){
        if(!active()){k.drawTiles(gc,layer,bx,by,wlast,hlast,ox,oy,local);return;}
        if(wlast<0 || hlast<0)return;
        load();
        int[] state=k.state[layer];
        int ww=state[7],hh=state[8],columns=state[2],rows=state[3],z=a.B;
        byte[] ground=k.maps[layer][0],flips=k.maps[layer][1];
        resetCache(z,ground,flips);
        int cx=gc.getClipX(),cy=gc.getClipY(),cw=gc.getClipWidth(),ch=gc.getClipHeight();
        gc.setClip(0,0,hh,ww);
        for(int j=by;j<=by+hlast;j++){
            int destY=(j*BLOCK_H+oy)%hh;if(destY<0)destY+=hh;
            for(int i=bx;i<=bx+wlast;i++){
                int destX=(i*BLOCK_W+ox)%ww;if(destX<0)destX+=ww;
                gc.drawImage(block(i,j,columns,rows,z,ground,flips),hh-destY-BLOCK_H,destX,Graphics.TOP|Graphics.LEFT);
            }
        }
        gc.setClip(cx,cy,cw,ch);
        if(!local)a.l=true;
    }
}