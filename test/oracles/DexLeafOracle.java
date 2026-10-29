public class DexLeafOracle {
    public static void C2(int i, byte[] bArr, int i5) {
        bArr[i5] = (byte) (i >>> 24);
        int i6 = i5 + 1;
        bArr[i6] = (byte) (i >>> 16);
        int i7 = i6 + 1;
        bArr[i7] = (byte) (i >>> 8);
        bArr[i7 + 1] = (byte) i;
    }
    public static final int H4(int i) {
        int i5 = (((((i >> 16) & 255) * 30) + (((i >> 8) & 255) * 59)) + ((i & 255) * 11)) / 100;
        return (((i >> 24) & 255) << 24) | (i5 << 16) | (i5 << 8) | i5;
    }
    public static byte[] H7(int[] iArr, boolean z, byte[] bArr) {
        int length = iArr.length << 2;
        if (z) {
            int i = iArr[iArr.length - 1];
            if (i > length) {
                return null;
            }
            length = i;
        }
        if (bArr == null) {
            bArr = new byte[length];
        }
        for (int i5 = 0; i5 < length; i5++) {
            bArr[i5] = (byte) ((iArr[i5 >>> 2] >>> ((i5 & 3) << 3)) & 255);
        }
        return bArr;
    }
    public static float[] I3(float f5, float f6, float f7, float f8, float f9, float f10) {
        float f11 = f6 - f5;
        float f12 = f8 - f7;
        float f13 = f10 - f9;
        return new float[]{2.0f / f11, 0.0f, 0.0f, (-(f6 + f5)) / f11, 0.0f, 2.0f / f12, 0.0f, (-(f8 + f7)) / f12, 0.0f, 0.0f, 2.0f / f13, (-(f10 + f9)) / f13, 0.0f, 0.0f, 0.0f, 1.0f};
    }
    public static int[] I7(byte[] bArr, boolean z, int[] iArr) {
        int length = (bArr.length & 3) == 0 ? bArr.length >>> 2 : (bArr.length >>> 2) + 1;
        if (z) {
            if (iArr == null) {
                iArr = new int[length + 1];
            }
            iArr[length] = bArr.length;
        } else if (iArr == null) {
            iArr = new int[length];
        }
        int length2 = bArr.length;
        for (int i = 0; i < length2; i++) {
            int i5 = i >>> 2;
            iArr[i5] = iArr[i5] | ((bArr[i] & 255) << ((i & 3) << 3));
        }
        return iArr;
    }
    public static byte[] U2(int[] iArr, int i) {
        byte[] bArr = new byte[i];
        int i5 = 0;
        for (int i6 = 0; i6 < i; i6 += 4) {
            bArr[i6 + 0] = (byte) (iArr[i5] & 255);
            bArr[i6 + 1] = (byte) ((iArr[i5] >>> 8) & 255);
            bArr[i6 + 2] = (byte) ((iArr[i5] >>> 16) & 255);
            bArr[i6 + 3] = (byte) ((iArr[i5] >>> 24) & 255);
            i5++;
        }
        return bArr;
    }
    public static int f3(int i) {
        int i5 = 0;
        while (true) {
            int i6 = 1 << i5;
            if (i6 >= i) {
                return i6;
            }
            i5++;
        }
    }
    public static int o0(int[] iArr, int i, int i5, int i6, int i7) {
        while (i < i5) {
            if (iArr[i] >= i6 && iArr[i] <= i7) {
                return i;
            }
            i++;
        }
        return i5;
    }
    public static int o3(byte[] bArr, int i) {
        int i5 = i + 1;
        int i6 = i5 + 1;
        int i7 = (bArr[i] & 255) | ((bArr[i5] & 255) << 8);
        int i8 = i6 + 1;
        return ((bArr[i8] & 255) << 24) | i7 | ((bArr[i6] & 255) << 16);
    }
    public static long p3(byte[] bArr, int i) {
        int i5 = i + 1;
        long j = bArr[i] & 255;
        int i6 = i5 + 1;
        long j5 = j | (((long) (bArr[i5] & 255)) << 8);
        int i7 = i6 + 1;
        long j6 = j5 | (((long) (bArr[i6] & 255)) << 16);
        int i8 = i7 + 1;
        long j7 = j6 | (((long) (bArr[i7] & 255)) << 24);
        int i9 = i8 + 1;
        long j8 = j7 | (((long) (bArr[i8] & 255)) << 32);
        int i10 = i9 + 1;
        long j9 = j8 | (((long) (bArr[i9] & 255)) << 40);
        return (((long) (bArr[i10 + 1] & 255)) << 56) | j9 | (((long) (bArr[i10] & 255)) << 48);
    }
    public static short q3(byte[] bArr, int i) {
        int i5 = i + 1;
        return (short) (((bArr[i5] & 255) << 8) | (bArr[i] & 255));
    }
    public static int r0(int[] iArr, int i) {
        if (i > 0) {
            int i5 = i - 1;
            int i6 = iArr[i5];
            while (i5 >= 0 && iArr[i5] == i6) {
                i5--;
            }
            if (i5 >= 0) {
                return iArr[i5];
            }
        }
        return -1;
    }
    public static int t0(int i, int i5) {
        if (i5 == 18) {
            return i;
        }
        if (i5 == 3) {
            return i | 64;
        }
        return i5 == 0 ? i | 128 : i;
    }
    public static int u3(byte[] bArr, int i, int i5) {
        int i6 = i + 1;
        bArr[i] = (byte) (i5 & 255);
        int i7 = i6 + 1;
        bArr[i6] = (byte) ((i5 >>> 8) & 255);
        int i8 = i7 + 1;
        bArr[i7] = (byte) ((i5 >>> 16) & 255);
        int i9 = i8 + 1;
        bArr[i8] = (byte) ((i5 >>> 24) & 255);
        return i9;
    }
    public static int v3(byte[] bArr, int i, long j) {
        int i5 = i + 1;
        bArr[i] = (byte) (j & 255);
        int i6 = i5 + 1;
        bArr[i5] = (byte) ((j >>> 8) & 255);
        int i7 = i6 + 1;
        bArr[i6] = (byte) ((j >>> 16) & 255);
        int i8 = i7 + 1;
        bArr[i7] = (byte) ((j >>> 24) & 255);
        int i9 = i8 + 1;
        bArr[i8] = (byte) ((j >>> 32) & 255);
        int i10 = i9 + 1;
        bArr[i9] = (byte) ((j >>> 40) & 255);
        int i11 = i10 + 1;
        bArr[i10] = (byte) ((j >>> 48) & 255);
        int i12 = i11 + 1;
        bArr[i11] = (byte) ((j >>> 56) & 255);
        return i12;
    }
    public static int w3(byte[] bArr, int i, short s) {
        int i5 = i + 1;
        bArr[i] = (byte) (s & 255);
        int i6 = i5 + 1;
        bArr[i5] = (byte) ((s >>> 8) & 255);
        return i6;
    }
}