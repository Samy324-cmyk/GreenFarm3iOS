/** Per-module alpha stored alongside indexed Android artwork in a MIDP sprite. */
final class GF3Alpha {
    private static int readInt(byte[] data, int pos) {
        return (data[pos] & 255) << 24 | (data[pos + 1] & 255) << 16
             | (data[pos + 2] & 255) << 8 | (data[pos + 3] & 255);
    }

    static byte[][] read(byte[] data) {
        if (data == null || data.length < 10 || readInt(data, data.length - 4) != 0x47463341) {
            return null;
        }
        int limit = data.length - 8;
        int pos = readInt(data, limit);
        if (pos < 0 || pos > limit - 2) return null;
        int count = (data[pos] & 255) << 8 | (data[pos + 1] & 255);
        pos += 2;
        if (count > (limit - pos) / 4) return null;
        byte[][] masks = new byte[count][];
        for (int i = 0; i < count; i++) {
            if (limit - pos < 4) return null;
            int length = readInt(data, pos);
            pos += 4;
            if (length < 0 || length > limit - pos) return null;
            masks[i] = new byte[length];
            System.arraycopy(data, pos, masks[i], 0, length);
            pos += length;
        }
        return pos == limit ? masks : null;
    }

    static boolean hasTransparency(boolean original, byte[][] masks) {
        return original || masks != null;
    }

    static int[] apply(int[] rgb, byte[][] masks, int module) {
        if (masks != null && rgb != null) {
            byte[] alpha = masks[module];
            for (int i = 0; i < alpha.length; i++) {
                rgb[i] = (rgb[i] & 0x00ffffff) | (alpha[i] << 24);
            }
        }
        return rgb;
    }
}
