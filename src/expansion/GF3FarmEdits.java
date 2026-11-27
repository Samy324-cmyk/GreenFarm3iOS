/** Keep the farm's last placed hive and the dog on duty when editing the farm. */
final class GF3FarmEdits {
    static void hit(int event) {
        if ((event == 65610 || event == 65611) && a.selected != null) {
            f item = a.selected;
            if (item.q == 52 && (item.y == 22 || item.y == 23) &&
                    f.b(0,3022) + f.b(0,3023) <= 1) {
                a.a(GF3EditWords.HIVE, GF3EditWords.KEEP_HIVE, 7, 0);
                a.D();
                return;
            }
            // cGame.bi/ci check the selected actor's dog marker for every
            // breed. Replacement by a newly selected dog uses its own flow.
            if (GF3Dogs.dog(item)) {
                a.a(GF3EditWords.DOG, GF3EditWords.KEEP_DOG, 7, 0);
                a.D();
                return;
            }
        }
        a.gf3FarmEditHit(event);
    }
}
