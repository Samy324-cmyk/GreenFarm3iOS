/** Offline livestock counters and achievement rules from Android cGame.QG and GA. */
final class GF3Flock {
    static boolean adult(int id) {
        int[][] species = a.gf3AnimalRows();
        int i = id-2000;
        return i >= 0 && i < species.length && species[i][1] == id && species[i][34] != 1;
    }

    static int distinct() {
        int count = 0;
        int[][] species = a.gf3AnimalRows();
        for (int i=0; i<species.length; i++) {
            if (species[i][34] != 1 && f.a(0,54,i,i) > 0) count++;
        }
        return count;
    }

    static boolean countable(f animal) {
        return !animal.a(32) && !animal.a(8192);
    }

    static int pigs(int layer, int kind, int first, int last) {
        return f.a(layer,kind,first,last) + f.a(layer,kind,66,67);
    }
}
