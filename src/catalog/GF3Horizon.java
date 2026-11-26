/** Northern scenery from cGame.Kv and s1.H1/q1, in tile-cache coordinates. */
final class GF3Horizon {
    private static final int HORIZON = 648;
    private static int lastX = -1, lastY = -1, lastZoom = -1;
    private static int left, top, right, bottom;
    private static boolean parallax;
    // Six native tile-cache damage rectangles can split at each of the
    // two wrapping axes. One more entry holds the repainted parallax band.
    private static final int[][] regions = new int[25][4];
    private static int regionCount;
    private static int actorLeft, actorTop, actorRight, actorBottom;

    static f firstActor(int group) {
        if (group == 0) worldActors();
        return f.actors[group];
    }

    private static void addRegion(int x, int y, int endX, int endY) {
        if (x >= endX || y >= endY) return;
        if(regionCount>=regions.length){a.l=true;return;}
        int[] rect = regions[regionCount++];
        rect[0] = x;
        rect[1] = y;
        rect[2] = endX;
        rect[3] = endY;
    }

    static f[] worldActors() {
        int x = k.cameraX(0), y = k.cameraY(0), zoom = a.B;
        // Prescaled sheets can extend one raster row beyond their logical
        // damage bounds. Recompose them when the underlying tiles change.
        if (zoom != lastZoom || zoom != 100 && k.dirtyCount > 0) a.l = true;
        int horizon = HORIZON * zoom / 100;
        boolean moved = x != lastX || y != lastY || zoom != lastZoom;
        parallax = y < horizon && (moved || k.dirtyCount > 0);
        lastX = x;
        lastY = y;
        lastZoom = zoom;
        regionCount = 0;
        if (k.layer == null || k.layer[0] == null || k.tiles == null) return f.actors;
        int[] tile = k.layer[0];
        int tileWidth = (tile[15] & 256) == 0 ? k.tiles[2] : tile[2];
        int tileHeight = (tile[15] & 256) == 0 ? k.tiles[5] : tile[3];
        if (tileWidth <= 0 || tileHeight <= 0) return f.actors;
        left = x / tileWidth * tileWidth;
        top = y / tileHeight * tileHeight;
        right = left + tile[7];
        bottom = top + tile[8];
        if (!a.l) {
            int groundStarts = parallax ? horizon : top;
            if (parallax) addRegion(left, top, right, Math.min(bottom, horizon));
            for (int i = 0; i < k.dirtyCount; i++)
                addTileDamage(k.dirty[0][i], groundStarts, tile[7], tile[8]);
        }
        return f.actors;
    }

    // The tile engine reports damage in ring-buffer pixels. Convert each
    // wrapped piece back to world coordinates before clipping the actors.
    private static void addTileDamage(int[] rect, int groundStarts, int width, int height) {
        int ringX = left % width, ringY = top % height;
        int endX = rect[0] + rect[2], endY = rect[1] + rect[3];
        for (int x = rect[0]; x < endX;) {
            int dx = x - ringX, w = endX - x;
            if (dx < 0) {
                dx += width;
                w = Math.min(w, ringX - x);
            }
            for (int y = rect[1]; y < endY;) {
                int dy = y - ringY, h = endY - y;
                if (dy < 0) {
                    dy += height;
                    h = Math.min(h, ringY - y);
                }
                addRegion(left + dx, Math.max(top + dy, groundStarts), left + dx + w, top + dy + h);
                y += h;
            }
            x += w;
        }
    }

    private static boolean touches(int x, int y, int endX, int endY) {
        return actorRight >= x && actorLeft <= endX && actorBottom >= y && actorTop <= endY;
    }

    static void paintActor(f actor, int slot, int frame) {
        if (!a.l && regionCount == 0 && f.eraseCount == 0) return;
        e sprite = (slot & 0x8000) == 0 ? a.b[slot] : a.ui[slot & 0x7fff];
        if (sprite == null || frame < 0) return;
        int zoom = a.B;
        int frameZoom = zoom;
        // The original renderer selects the second half of certain sheets
        // at half scale. Use the bounds of the frame it actually paints.
        int renderedFrame = frame;
        if (zoom < 100 && a.prescaled(slot)) {
            renderedFrame += sprite.frames() / 2;
            frameZoom = 100;
        }
        actorLeft = actor.r * zoom / 100 + sprite.left(renderedFrame) * frameZoom / 100;
        actorTop = actor.s * zoom / 100 + sprite.top(renderedFrame) * frameZoom / 100;
        actorRight = actorLeft + (sprite.width(renderedFrame) * frameZoom + 99) / 100;
        actorBottom = actorTop + (sprite.height(renderedFrame) * frameZoom + 99) / 100;
        if (!touches(left, top, right, bottom)) return;
        actor.paintTile(slot, frame);
    }

    static void staticSprite(int layer, e sprite, int frame, int x, int y, boolean all, int[] clip) {
        if (all) {
            k.sprite(layer, sprite, frame, x, y, true, clip);
            return;
        }
        for (int i = 0; i < regionCount; i++) {
            int[] rect = regions[i];
            if (touches(rect[0], rect[1], rect[2], rect[3]))
                k.sprite(layer, sprite, frame, x, y, true, rect);
        }
    }

    static boolean draw() {
        int zoom = a.B;
        int x = k.cameraX(0), y = k.cameraY(0);
        if (zoom <= 0 || y >= HORIZON * zoom / 100 || !a.l && !parallax) return true;
        int worldX = x * 100 / zoom, worldY = y * 100 / zoom;
        k.buffers[0][0].setColor(0x10b5f2);
        int sky = (int)(HORIZON - (HORIZON - worldY) * 215.0f / HORIZON + 0.5f);
        k.fill(0, 0, k.e(), sky * zoom / 100, true);
        // The background sky stays at native scale even at 50% zoom.
        k.sprite(0, a.b[79], 0, x, y + (433 - worldY) * zoom / 100, true, null);
        if (zoom != 100) {
            g.o();
            g.n(zoom);
        }
        int mountains = (int)(HORIZON - (HORIZON - worldY) * 40.0f / HORIZON + 0.5f);
        int xShift = x - (worldX >> 4) * zoom / 100;
        repeat(78, xShift, mountains * zoom / 100, 240, zoom);
        repeat(77, 0, HORIZON * zoom / 100, 400, zoom);
        if (zoom != 100) g.p();
        return true;
    }

    private static void repeat(int slot, int anchor, int y, int worldStep, int zoom) {
        // Scale each world position independently, including at 67% and 75%,
        // so a fractional step never accumulates an error across the map.
        int step = worldStep * zoom;
        int first = Math.max(0, (left - anchor) * 100 / step - 1);
        int worldWidth = k.e() * 100 / zoom;
        for (int i = first; i * worldStep < worldWidth; i++) {
            int x = anchor + i * step / 100;
            if (x >= right) break;
            k.sprite(0, a.b[slot], 0, x, y, true, null);
        }
    }
}
