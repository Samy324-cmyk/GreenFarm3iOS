/** Walt's flyover ripens the planted fields and trees at the end of the cutscene. */
final class GF3CropDuster {
    private static boolean flying;

    static int available() { return flying ? -1 : a.bT; }

    static void launch(int ignored) { flying=true; }

    static void land() {
        a.w|=1;
        for(f actor=f.heads[0];actor!=null;actor=actor.next) {
            if((actor.q==49 && actor.D!=1) || actor.q==52) actor.F();
        }
        a.bT=0;
        flying=false;
    }
}
