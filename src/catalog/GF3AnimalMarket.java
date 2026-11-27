/** Schedule the added farm art in the engine's normal loading pass. */
final class GF3AnimalMarket {
    static void worldArt(int group,int slot,int palettes,int action,int flags,int first,int last) {
        a.a(group,slot,palettes,action,flags,first,last);
        if (h.a[0].b > 64) {
            sprite(160,1);
            sprite(159,1);
        }
        if (h.a[0].b > 66) sprite(188,1 << 6);
        if (h.a[0].b > 68) {
            sprite(175,1);
            sprite(176,1);
            sprite(177,1);
            sprite(178,1);
            sprite(171,1);
            sprite(172,1);
        }
        if (h.a[3].b > 20) sprite(167,1);
        if (h.a[3].b > 24) sprite(174,1);
        if (h.a[3].b > 27) {
            sprite(183,1);
            sprite(184,1);
            sprite(185,1);
        }
        if (h.a[4].b > 63) sprite(169,1);
        if (h.a[4].b > 64) {
            for (int item=179; item<=182; item++) sprite(item,1);
        }
        if (h.a[2].b > 22) {
            sprite(173,1);
            sprite(186,1);
            sprite(187,1);
        }
    }

    static void preloadSounds(int slot,int flags) {
        a.e(slot,flags);
        for (int sound=119; sound<127;sound++) {
            // The touch engine mixes the expansion cues on its effect channel.
            a.d[sound]=new int[]{0,2};
            a.e(sound,flags);
            a.e(sound+8,flags);
        }
        a.d[135]=new int[]{0,2};
        a.e(135,flags);
        a.e(136,flags);
    }

    static int alternate(int event) {
        if(event>=137) return event+13;
        if(event==135) return 136;
        return event>=119 ? event+8 : event+52;
    }

    static int decorFrames(e sprite) {
        return sprite.a()>0 ? sprite.a(0) : 0;
    }

    private static void sprite(int slot,int palettes) {
        a.a(0,slot,palettes,0,136,0,-1);
    }

    static void feed(f animal,int original) {
        int slot = animal.E;
        if (slot==159 || slot==160) original = 5;
        if (slot==188) original = 2;
        if (slot>=175 && slot<=178) original = 6;
        animal.a = (short) original;
    }
}
