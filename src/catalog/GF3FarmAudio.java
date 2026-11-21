/** Play the 4.4.4 farm music and ambience alongside the native MIDP effects. */
final class GF3FarmAudio {
    private static final int MUSIC=1,AMBIENCE=2,FARM_LOOP=25,FIRST_EFFECT=3,LAST_EFFECT=7;
    private static final int[] tracks=new int[9];
    private static long musicStarted,ambientRequested;
    private static int next,previous=-1,effectChannel=FIRST_EFFECT;
    private static boolean ambient;

    private static void loadSlot(int cue) {
        if(!k.loaded(cue)) {
            a.e(cue,0);
            a.loadSound(cue);
        }
    }
    private static void load(int cue,int alternate) {
        if(k.loaded(cue) && (alternate<0 || k.loaded(alternate))) return;
        String previous=g.packName;
        try {
            loadSlot(cue);
            if(alternate>=0) loadSlot(alternate);
        } finally {
            // A deferred sound can be requested in the middle of a menu
            // update. Give its sprites back the same indexed resource pack.
            if(previous!=null && !previous.equals(g.packName)) g.open(previous);
        }
    }

    private static void queue(int channel,int cue,boolean repeat) {
        load(cue,-1);
        if(k.loaded(cue)) k.a(channel,cue,repeat?0:1,a.at,0);
    }

    static void original(int source) {
        int cue=GF3AudioIds.slots[source];
        if(source<14 || source==62 || source==63) {
            // Predator arrival and mission themes only fill an idle music channel.
            if(source<14 || !k.playing(MUSIC)) music(cue,false);
        } else if(source==24) {
            if(a.R && a.S) queue(AMBIENCE,cue,true);
        } else effect(cue);
    }

    static void effect(int cue) {
        if(!a.R || !a.S || a.W) return;
        if(cue<15) {
            music(cue,false);
            return;
        }
        // Android cGame.oz rotates ordinary effects through channels 3–7.
        // Its master level comes from the saved setting, including on MMAPI
        // providers that cannot report the volume of a finished waveform.
        int slot=cue==a.aw ? GF3AnimalMarket.alternate(cue) : cue;
        load(slot,-1);
        if(!k.loaded(slot)) return;
        a.aw=slot;
        a.lastEffect=System.currentTimeMillis();
        k.a(effectChannel,slot,1,a.at,2);
        effectChannel=effectChannel==LAST_EFFECT ? FIRST_EFFECT : effectChannel+1;
    }

    static void music(int cue,boolean repeat) {
        if(!a.R || !a.T) return;
        queue(MUSIC,cue,repeat);
        musicStarted=System.currentTimeMillis();
    }

    static void stop() {
        if(a.R) {
            a.gf3StopSound();
            if(k.loaded(0) || k.loaded(13) || k.loaded(FARM_LOOP)) {
                for(int channel=MUSIC;channel<=LAST_EFFECT;channel++) k.a(channel,true);
            }
        }
        ambient=false;
        musicStarted=0;
    }

    static void update() {
        if(!a.R) return;
        if(!a.intro && a.C!=-1) {
            music(13,false);
            a.intro=true;
            return;
        }
        if(a.V) {
            a.V=false;
            music(0,false);
            return;
        }
        long now=System.currentTimeMillis();
        if(a.S && now-ambientRequested>=2000L && (!ambient || !k.playing(AMBIENCE))) {
            queue(AMBIENCE,FARM_LOOP,true);
            ambient=k.loaded(FARM_LOOP);
            ambientRequested=now;
        } else if(!a.S && ambient) {
            k.a(AMBIENCE,true);
            ambient=false;
        }
        if(!a.T || now-musicStarted<25000L || now-a.lastEffect<5000L || k.playing(MUSIC)) return;
        if(next==0) {
            for(int i=0;i<tracks.length;i++) tracks[i]=i+1;
            for(int i=tracks.length-1;i>=0;i--) {
                int j=g.c(0,tracks.length),value=tracks[i];
                tracks[i]=tracks[j];
                tracks[j]=value;
            }
            if(tracks[0]==previous) next++;
        }
        previous=tracks[next];
        next=(next+1)%tracks.length;
        music(previous,false);
    }
}
