/** The original touch UI has three recipe tabs per kitchen. */
final class GF3HoneyKitchen {
    private static boolean honey;

    static void enter() { honey = true; }
    static void leave() { honey = false; }

    static int category(int[][] recipes, int row) {
        int group = recipes[row][4];
        if (honey) return group > 3 ? group - 3 : 0;
        return group <= 3 ? group : 0;
    }

    static int starred(int product) {
        return product + (product >= 121 && product <= 130 ? 10 : 1);
    }

    static int[] starredRecord(int[][] inventory, int product) {
        return inventory[starred(product)];
    }
}
