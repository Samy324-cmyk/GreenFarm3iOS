import javax.microedition.media.Player;

/** Track source duration on providers that leave completed WAV players started. */
final class GF3AudioDevice {
    private static final Player[] players=new Player[8];
    private static final int[] durations=new int[8];
    private static final boolean[] looping=new boolean[8];
    private static final long[] ends=new long[8];
    private static boolean missedEnd;

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
