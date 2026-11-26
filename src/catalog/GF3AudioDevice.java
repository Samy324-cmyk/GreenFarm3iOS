import java.io.DataInputStream;
import java.io.InputStream;
import java.io.IOException;
import javax.microedition.media.Player;

/** Track source duration on providers that leave completed WAV players started. */
final class GF3AudioDevice {
    private static final Player[] players=new Player[8];
    private static final int[] durations=new int[8];
    private static final boolean[] looping=new boolean[8];
    private static final long[] ends=new long[8];
    private static boolean missedEnd;
    static int soundType;

    private static int readLE32(DataInputStream in) throws IOException {
        return in.readUnsignedByte() | (in.readUnsignedByte()<<8) |
               (in.readUnsignedByte()<<16) | (in.readUnsignedByte()<<24);
    }

    /** Audio has its own stream: never change g's currently open sprite pack. */
    static byte[] readSound(String pack,int cue) throws IOException {
        if(!"/3".equals(pack) || cue<0) return null;
        String name=cue==0 ? "/3" : "/3."+cue;
        InputStream stream=new GF3AudioDevice().getClass().getResourceAsStream(name);
        if(stream==null) return null;
        DataInputStream in=new DataInputStream(stream);
        try {
            int header=0;
            if(cue==0) {
                int count=in.readUnsignedByte() | (in.readUnsignedByte()<<8);
                int parts=in.readUnsignedByte() | (in.readUnsignedByte()<<8);
                if(count<=0 || parts!=count) throw new IOException("Audio shard count");
                for(int i=0;i<parts;i++) {
                    int start=in.readUnsignedByte() | (in.readUnsignedByte()<<8);
                    if(start!=i) throw new IOException("Audio shard index");
                }
                header=4+2*parts;
            }
            int first=readLE32(in), after=readLE32(in);
            if(first!=header+8 || after<first || after-first>4*1024*1024)
                throw new IOException("Audio shard bounds");
            if(after==first) return null;
            soundType=in.readUnsignedByte();
            byte[] pcm=new byte[after-first-1];
            in.readFully(pcm);
            return pcm;
        } finally {
            in.close();
        }
    }

    static boolean ready(int channelState,Player player) {
        return channelState==1 && player!=null && player.getState()>=Player.REALIZED;
    }

    static long time(Player player) {
        return player==null || player.getState()<Player.REALIZED ? -1L : player.getMediaTime();
    }

    private static int littleInt(byte[] bytes,int offset) {
        return (bytes[offset]&255) | ((bytes[offset+1]&255)<<8) |
               ((bytes[offset+2]&255)<<16) | ((bytes[offset+3]&255)<<24);
    }

    static void start(int channel,Player player,byte[] wav,int loops) throws Exception {
        player.setMediaTime(0L);
        player.start();
        players[channel]=null;
        if(wav==null || wav.length<44 || littleInt(wav,0)!=0x46464952 ||
           littleInt(wav,36)!=0x61746164) return;
        int bytesPerSecond=littleInt(wav,28);
        if(bytesPerSecond<=0) return;
        int ms=(int)((littleInt(wav,40)*1000L+bytesPerSecond-1)/bytesPerSecond);
        if(ms<=0) return;
        players[channel]=player;
        durations[channel]=ms;
        looping[channel]=loops==0;
        ends[channel]=System.currentTimeMillis()+ms*Math.max(loops,1);
    }

    static void update() {
        long now=System.currentTimeMillis();
        for(int i=0;i<players.length;i++) {
            Player p=players[i];
            if(p==null || now<ends[i] || (looping[i] && !missedEnd)) continue;
            try {
                if(p.getState()!=Player.STARTED) players[i]=null;
                else if(!looping[i]) {
                    // Allow a native output queue to finish before deciding
                    // that the MMAPI end notification was lost.
                    if(now-ends[i]<120L) continue;
                    p.stop();
                    players[i]=null;
                    missedEnd=true;
                } else {
                    p.stop();
                    p.setMediaTime(0L);
                    p.start();
                    ends[i]=now+durations[i];
                }
            } catch(Exception ended) {
                players[i]=null;
            }
        }
        k.tick();
    }
}
