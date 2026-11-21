/** Read the touchscreen engine's previous fixed-width catalog inventories. */
final class GF3CatalogSave {
    private static final int RECORD_SIZE = 51200;
    private static final int FIELDS = 7;
    private static final int FOOTER = 4 + FIELDS * 2;
    private static final int[] ORIGINAL = {297, 6, 117, 20, 63, 64, 10};
    private static final int COUNTER_ZERO = -1413816336;

    private static int[] widths() {
        // Native table order: quests, feed types, products, buildings,
        // decorations, animals and trees (the first twelve crops are fields).
        int[] ids = {6, 22, 1, 3, 4, 0, 2};
        int[] result = new int[FIELDS];
        for (int i = 0; i < FIELDS; i++) result[i] = h.a[ids[i]].b;
        result[6] -= 12;
        return result;
    }

    static byte[] read(String name) {
        byte[] saved = g.a(name);
        return saved == null ? null : migrate(saved, widths());
    }

    static void write(String name, byte[] state) {
        g.a(name, stamp(state, widths()));
    }

    static byte[] stamp(byte[] state, int[] sizes) {
        if (state.length != RECORD_SIZE) throw new IllegalArgumentException();
        byte[] saved = new byte[RECORD_SIZE + FOOTER];
        System.arraycopy(state, 0, saved, 0, RECORD_SIZE);
        saved[RECORD_SIZE] = 'G';
        saved[RECORD_SIZE + 1] = 'F';
        saved[RECORD_SIZE + 2] = 'C';
        saved[RECORD_SIZE + 3] = 1;
        for (int i = 0; i < FIELDS; i++) {
            int at = RECORD_SIZE + 4 + i * 2;
            saved[at] = (byte) sizes[i];
            saved[at+1] = (byte) (sizes[i] >>> 8);
        }
        return saved;
    }

    static byte[] migrate(byte[] saved, int[] sizes) {
        int[] old = ORIGINAL;
        if (saved.length != RECORD_SIZE) {
            if (saved.length != RECORD_SIZE + FOOTER || saved[RECORD_SIZE] != 'G' ||
                saved[RECORD_SIZE+1] != 'F' || saved[RECORD_SIZE+2] != 'C' ||
                saved[RECORD_SIZE+3] != 1) throw new IllegalArgumentException();
            old = new int[FIELDS];
            for (int i = 0; i < FIELDS; i++) {
                int at = RECORD_SIZE + 4 + i * 2;
                old[i] = (saved[at] & 255) | ((saved[at+1] & 255) << 8);
            }
        }
        byte[] state = new byte[RECORD_SIZE];
        // 19 header bytes and four 23-byte active quest slots precede the
        // per-quest values. 40 currency/stat bytes precede the silo counts.
        int from = 111, to = 111;
        System.arraycopy(saved, 0, state, 0, from);
        for (int i = 0; i < FIELDS; i++) {
            if (old[i] < ORIGINAL[i] || old[i] > sizes[i]) throw new IllegalArgumentException();
            if (i == 1) {
                System.arraycopy(saved, from, state, to, 40);
                from += 40;
                to += 40;
            }
            System.arraycopy(saved, from, state, to, old[i] * 4);
            from += old[i] * 4;
            to += old[i] * 4;
            for (int j = old[i]; j < sizes[i]; j++) {
                // Inventory values store a rotated integer XORed with the
                // native cookie (the encoded representation of zero).
                int initial = i == 0 ? 0 : COUNTER_ZERO;
                for (int k = 0; k < 4; k++) state[to++] = (byte) (initial >>> (8*k));
            }
        }
        // The unused end of the fixed buffer absorbs the additional counts.
        System.arraycopy(saved, from, state, to, RECORD_SIZE - to);
        return state;
    }
}
