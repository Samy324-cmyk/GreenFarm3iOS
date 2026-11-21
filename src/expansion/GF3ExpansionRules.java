/**
 * Additional matches from the Android 4.4.4 mission dispatcher cGame.WA.
 * These IDs come from animal table 0 and crop table 2 of the supplied APK.
 * A disabled objective must not advance on a matching purchase or harvest.
 */
final class GF3ExpansionRules {
    static int progress(int previous, boolean disabled, int neededItem, int eventItem,
                        int neededAction, int eventAction) {
        if (previous != 0 || disabled || neededAction != eventAction) {
            return previous;
        }
        switch (neededItem) {
            case 2993:
                return eventItem == 2064 || eventItem == 2065 ? 1 : 0;
            case 2996:
                return eventItem == 2066 || eventItem == 2067 ? 1 : 0;
            case 2992:
                return (eventItem >= 2068 && eventItem <= 2072) || eventItem == 2075 ? 1 : 0;
            case 2989:
                return eventItem == 3022 || eventItem == 3023 ? 1 : 0;
            default:
                return 0;
        }
    }
}
