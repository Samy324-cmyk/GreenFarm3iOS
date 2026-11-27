"""Inspect ASprite geometry and graphics across MIDP modules and Android atlases."""
import struct
from collections import defaultdict


class Reader:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def take(self, count):
        chunk = self.data[self.pos:self.pos + count]
        if len(chunk) != count:
            raise ValueError('Truncated ASprite')
        self.pos += count
        return chunk

    def num(self, fmt):
        return struct.unpack('<' + fmt, self.take(struct.calcsize('<' + fmt)))[0]


def shards(jar, name):
    base = jar.read(name)
    count, parts = struct.unpack_from('<HH', base)
    starts = [*struct.unpack_from(f'<{parts}H', base, 4), count]
    result = {}
    for part, (first, after) in enumerate(zip(starts, starts[1:])):
        key = name if not part else f'{name}.{part}'
        data = base if not part else jar.read(key)
        header = 4 + 2 * parts if not part else 0
        offsets = struct.unpack_from(f'<{after-first+1}I', data, header)
        if (offsets[-1] != len(data) or offsets[0] != header + len(offsets) * 4
                or list(offsets) != sorted(offsets)):
            raise ValueError(f'Bad shard {key}')
        result[key] = [data[start:end] for start, end in zip(offsets, offsets[1:])]
    return result


def geometry(data):
    r = Reader(data)
    if r.take(3) != b'\x02\xdf\x05':
        raise ValueError('Expected ASprite 0x05df')
    flags = r.num('I')
    extra = r.num('I') if flags & 0x400000 else 0
    xy = 'h' if flags & 0x400 else 'b'
    dimensions = 'H' if flags & 16 else 'B'
    modules, locations = [], []
    for _ in range(r.num('H')):
        kind = r.num('B')
        image, x, y = 0, 0, 0
        color = 0
        if kind == 0:
            image = r.num('B') if flags & 4 else 0
            addr = 'H' if flags & 32 else 'B' if flags & 2 else None
            if addr:
                x, y = r.num(addr), r.num(addr)
        elif kind in (255, 254, 252, 251, 250, 249, 248, 247):
            color = r.num('I')
        elif kind != 253:
            raise ValueError(f'Unknown module type {kind}')
        params = r.take(6) if kind == 247 else b''
        w, h = (0, 0) if kind in (250, 249) else (r.num(dimensions), r.num(dimensions))
        if kind in (252, 251):
            params = r.take(4)
        if kind in (250, 249):
            params = r.take(8)
        locations.append((image, x, y))
        modules.append((kind, w, h, color, params))
    r.module_end = r.pos
    fmods = []
    for _ in range(r.num('H')):
        idx = r.num('H' if flags & 0x100000 else 'B')
        x, y = r.num(xy), r.num(xy)
        palette = r.num('B') if flags & 0x4000 else 0
        transform = r.num('B')
        custom = r.take(2) if extra & 16 else b''
        fmods.append((idx, x, y, palette, transform, custom))
    rectangles = []
    if flags & 0x8000:
        rectangles = [tuple(r.num(xy) for _ in range(4)) for _ in range(r.num('H'))]
    frames = []
    for _ in range(r.num('H')):
        frames.append((r.num('H' if flags & 0x800 else 'B'), r.num('H'),
                       r.num('B') if flags & 0x8000 else 0))
    for present in (not flags & 0x1000, flags & 0x2000):
        if present:
            for _ in frames:
                for _ in range(4):
                    r.num(xy)
    axy = 'h' if flags & 0x40000 else 'b'
    aframes = [(r.num('H' if flags & 0x200000 else 'B'), r.num('B'), r.num(axy),
                r.num(axy), r.num('B')) for _ in range(r.num('H'))]
    animations = [(r.num('H' if flags & 0x80000 else 'B'), r.num('H'))
                  for _ in range(r.num('H'))]
    signature = tuple(tuple(group) for group in
                      (modules, fmods, rectangles, frames, aframes, animations))
    return signature, locations, r, flags, extra


def indices(data, mode, pixels, colors):
    if mode == 0x5602:
        values = data
    elif mode in (0x200, 0x400, 0x1600):
        bits = {0x200: 1, 0x400: 2, 0x1600: 4}[mode]
        mask = (1 << bits) - 1
        values = bytes((octet >> shift) & mask for octet in data
                       for shift in range(8 - bits, -1, -bits))[:pixels]
    elif mode == 0x64f0:
        bits = max(1, (colors - 1).bit_length())
        values = b''.join(bytes([item & ((1 << bits) - 1)]) * (1 + (item >> bits))
                          for item in data)
    elif mode in (0x27f1, 0x56f2):
        r, values = Reader(data), bytearray()
        while r.pos < len(data):
            item = r.num('B')
            if mode == 0x27f1:
                if item > 127:
                    values.extend(r.take(1) * (item - 128))
                else:
                    values.append(item)
            elif item >= 128:
                values.extend(r.take(max(1, item - 128)))
            else:
                values.extend(r.take(1) * max(1, item))
    else:
        raise ValueError(f'Unknown indexed pixel format {mode:#x}')
    if len(values) != pixels:
        raise ValueError('Incorrect number of decoded sprite pixels')
    return bytes(values)


def android_modules(sig, locations, r, extra):
    if not extra & 0x100000 or not sig[0]:
        return None
    pixel, mode, sheets = r.num('H'), r.num('H'), r.num('B')
    if pixel != 0x8808 or sheets != 1 or mode == 0xa562:
        return None
    palettes, colors = r.num('B'), r.num('B') or 256
    palette = r.take(palettes * colors * 3)
    w, h = r.num('H'), r.num('H')
    atlas = indices(r.take(r.num('I')), mode, w * h, colors)
    if r.pos != len(r.data):
        raise ValueError('Unexpected Android image tail')
    blocks = []
    for (kind, mw, mh, _, _), (sheet, x, y) in zip(sig[0], locations):
        if kind != 0:
            blocks.append(b'')
            continue
        if x + mw > w or y + mh > h or sheet:
            raise ValueError('Module outside original Android texture')
        blocks.append(b''.join(atlas[row*w+x:row*w+x+mw] for row in range(y, y+mh)))
    return palettes, colors, palette, blocks


def midp_modules(sig, r, flags):
    if flags & 0x40000000 or not flags & 0x1000000 or not sig[0]:
        return None
    pix = r.num('H')
    if pix != 0x8808:
        return None
    palettes, colors = r.num('B'), r.num('B') or 256
    palette = r.take(palettes * colors * 3)
    mode = r.num('H')
    blocks = []
    for kind, width, height, _, _ in sig[0]:
        payload = r.take(r.num('I' if flags & 128 else 'H'))
        blocks.append(indices(payload, mode, width*height, colors) if kind == 0 else b'')
    if r.pos != len(r.data):
        raise ValueError('Unexpected MIDP image tail')
    return palettes, colors, palette, blocks


def visually_related(old, new):
    if old[0] != new[0]:
        return False
    # Require the actual pixel silhouettes to agree and the color samples to
    # match closely. Shared geometry alone does not identify artwork.
    old_rgb, new_rgb = old[2], new[2]
    checked = different = 0
    for left, right in zip(old[3], new[3]):
        for i in range(0, len(left), max(1, len(left)//64)):
            a, b = left[i]*3, right[i]*3
            c, d = old_rgb[a:a+3], new_rgb[b:b+3]
            if (c == b'\xff\x00\xff') != (d == b'\xff\x00\xff'):
                different += 1
            elif max(abs(x-y) for x,y in zip(c,d)) > 35:
                different += 1
            checked += 1
    return checked > 0 and different * 10 <= checked


def midp_pixels(source, flags, prefix):
    palettes, colors, palette, blocks = source
    flags |= 128
    out = bytearray(prefix)
    struct.pack_into('<I', out, 3, flags)
    out.extend(struct.pack('<HBB', 0x8808, palettes, colors % 256))
    out.extend(palette)
    out.extend(struct.pack('<H', 0x5602))
    for block in blocks:
        out.extend(struct.pack('<I', len(block)))
        out.extend(block)
    return bytes(out)


def rebuild_shard(parts, prefix):
    offsets = [len(prefix) + 4 * (len(parts) + 1)]
    for block in parts:
        offsets.append(offsets[-1] + len(block))
    return prefix + struct.pack(f'<{len(offsets)}I', *offsets) + b''.join(parts)


def convert_sprite(blob):
    """Convert modules from every atlas page, retaining the original frame data."""
    sig, locations, r, flags, extra = geometry(blob)
    if extra != 0x100000 or flags & (0x4000 | 0x2000 | 0x200000 | 0x80000):
        raise ValueError('Unsupported Android frame layout')
    shape_tail = blob[r.module_end:r.pos]
    pixel, mode, sheets = r.num('H'), r.num('H'), r.num('B')
    per_pixel_alpha = (pixel, mode) == (0x8888, 0xa562)
    if pixel != 0x8808 and not per_pixel_alpha:
        raise ValueError(f'Unsupported Android pixel format {pixel:#x}/{mode:#x}')
    palettes, counts = [], []
    for _ in range(sheets):
        variants, colors = r.num('B'), r.num('B') or 256
        if not 1 <= variants <= 16:
            raise ValueError('Palette count exceeds the MIDP renderer')
        raw = r.take(variants * colors * (4 if per_pixel_alpha else 3))
        rgb = b''.join(raw[i:i+3] for i in range(0,len(raw),4)) if per_pixel_alpha else raw
        palettes.append(bytes([variants, colors % 256]) + rgb)
        counts.append(colors)
    atlases = []
    for colors in counts:
        w, h = r.num('H'), r.num('H')
        raw = r.take(r.num('I'))
        if per_pixel_alpha:
            if len(raw) != 2*w*h:
                raise ValueError('Invalid Android alpha atlas')
            pixels, alpha = raw[1::2], raw[::2]
        else:
            pixels, alpha = indices(raw, mode, w*h, colors), b''
        if pixels and max(pixels) >= colors:
            raise ValueError('Android palette index out of bounds')
        atlases.append((w, h, pixels, alpha))
    if r.pos != len(blob):
        raise ValueError('Trailing Android atlas bytes')

    out_flags = (flags | 0x1000090) & ~(0x400000 | 0x40000000 | 0x22)
    if sheets > 1:
        out_flags |= 0x40000000
    out = bytearray(blob[:3]) + struct.pack('<IH', out_flags, len(locations))
    blocks, masks = [], []
    for (kind, mw, mh, color, params), (sheet, x, y) in zip(sig[0], locations):
        out.append(kind)
        block = mask = b''
        if kind == 0:
            if out_flags & 4:
                out.append(sheet)
            w, h, pixels, alpha = atlases[sheet]
            if x+mw > w or y+mh > h:
                raise ValueError('Module outside atlas')
            spans = [slice(row*w+x, row*w+x+mw) for row in range(y,y+mh)]
            block = b''.join(pixels[span] for span in spans)
            mask = b''.join(alpha[span] for span in spans) if per_pixel_alpha else b''
        elif kind != 253:
            out.extend(struct.pack('<I', color))
        if kind == 247:
            out.extend(params)
        if kind not in (249, 250):
            out.extend(struct.pack('<HH', mw, mh))
        if kind in (249, 250, 251, 252):
            out.extend(params)
        blocks.append(block)
        masks.append(mask)
    out.extend(shape_tail)
    out.extend(struct.pack('<H', 0x8808))
    if sheets > 1:
        out.append(sheets)
    out.extend(b''.join(palettes))
    out.extend(struct.pack('<H', 0x5602))
    for block in blocks:
        out.extend(struct.pack('<I',len(block)))
        out.extend(block)
    if per_pixel_alpha:
        alpha_offset = len(out) - 1  # Loader strips the pack's resource type.
        out.extend(struct.pack('>H', len(masks)))
        for mask in masks:
            out.extend(struct.pack('>I',len(mask)))
            out.extend(mask)
        out.extend(struct.pack('>I4s', alpha_offset, b'GF3A'))
    if geometry(out)[0] != sig:
        raise ValueError('Converted sprite geometry differs from Android')
    return bytes(out)


def extend_sprite_pack(jar, updates, android, dest):
    groups = shards(jar, str(dest))
    first = sum(len(blocks) for blocks in groups.values())
    last_key = next(reversed(groups))
    # Preserve all original shard numbers and offsets used by the loader.
    class Overlay:
        def read(self, key):
            return updates[key] if key in updates else jar.read(key)
    existing = shards(Overlay(), str(dest))[last_key]
    new = [convert_sprite(blob) for blob in android[first:]]
    if dest == 5:
        # Saddleback pigs use the Android pig sheet's extra palettes and
        # frame numbers. Existing MIDP pigs still address their original sheet.
        new.append(convert_sprite(android[19]))
    updates[last_key] = rebuild_shard(existing + new, b'')
    base = bytearray(updates.get(str(dest), jar.read(str(dest))))
    struct.pack_into('<H', base, 0, first+len(new))
    updates[str(dest)] = bytes(base)
    result = shards(Overlay(), str(dest))
    if result[last_key] != existing + new:
        raise ValueError('Expanded sprite index failed to round trip')
    return list(range(first, first+len(new)))


def build_sprites(jar, apk):
    from .world import entries, table
    reference_items = table(entries(jar.read('9'))[1])[1]
    apk_items = table(entries(apk.read('assets/800x480/13'))[1])[1]
    icons = {}
    for old, new in zip(reference_items,apk_items):
        if old[:2] != new[:2]:
            raise ValueError('Product registry no longer identifies matching icons')
        if 50 <= old[3] <= 106:
            if icons.setdefault(old[3],new[3]) != new[3]:
                raise ValueError('Ambiguous recipe icon')
    updates, converted, identical, added = {}, [], [], {}
    for source, dest in ((9, 5), (11, 7)):
        src = shards(apk, 'assets/800x480/' + str(source))
        android = [b for blocks in src.values() for b in blocks]
        candidates = defaultdict(list)
        for src_index, data in enumerate(android):
            if not data.startswith(b'\x02\xdf\x05'):
                continue
            sig, locations, reader, _, extra = geometry(data)
            pixels = android_modules(sig, locations, reader, extra)
            if pixels:
                candidates[sig].append((src_index, pixels))
        index = -1
        for name, blocks in shards(jar, str(dest)).items():
            changed = False
            for i, original in enumerate(blocks):
                index += 1
                if not original.startswith(b'\x02\xdf\x05'):
                    continue
                geom, _, j, flags, _ = geometry(original)
                if dest == 7 and index in icons:
                    # The product ID distinguishes visually similar meals which
                    # share dimensions. Some Android versions also moved a
                    # single-module picture one pixel within its frame.
                    src_index = icons[index]
                    other = geometry(android[src_index])[0]
                    if len(geom[3]) != 1 or len(other[3]) != 1:
                        raise ValueError('Unknown recipe thumbnail layout')
                    blocks[i] = convert_sprite(android[src_index])
                    converted.append([dest,index,source,src_index])
                    changed = True
                    continue
                if dest == 5 and index == 13:
                    # The APK added the fox/wolf fight effects to the common
                    # care effect. It preserved frame and animation numbering.
                    extended = geometry(android[index])[0]
                    if any(geom[i] != extended[i][:len(geom[i])] for i in (3,4,5)):
                        raise ValueError('Animal effect frame indices changed')
                    blocks[i] = convert_sprite(android[index])
                    converted.append([dest,index,source,index])
                    changed = True
                    continue
                if dest == 7 and index in (2, 34):
                    extended = geometry(android[index])[0]
                    if any(a != b[:len(a)] for a, b in zip(geom, extended)):
                        raise ValueError('Inventory icon frame numbering changed')
                    blocks[i] = convert_sprite(android[index])
                    converted.append([dest, index, source, index])
                    changed = True
                    continue
                if not candidates.get(geom):
                    continue
                prefix = original[:j.pos]
                old = midp_modules(geom, j, flags)
                if not old:
                    continue
                matches = [(sid, pixels) for sid, pixels in candidates[geom]
                           if visually_related(old, pixels)]
                if len(matches) != 1:
                    continue
                src_index, new = matches[0]
                # Compare every pixel and every colour variant. Equal assets
                # stay in the original compact MIDP representation.
                if old == new:
                    identical.append([dest, index, source, src_index])
                    continue
                candidate = midp_pixels(new, flags, prefix)
                verify_geom, _, verify_reader, verify_flags, _ = geometry(candidate)
                if verify_geom != geom or midp_modules(geom, verify_reader, verify_flags) != new:
                    raise ValueError(f'Lossless module conversion failed: {name} entry {index}')
                blocks[i] = candidate
                converted.append([dest, index, source, src_index])
                changed = True
            if changed:
                raw = jar.read(name)
                header = 0 if '.' in name else 4 + 2 * struct.unpack_from('<H', raw, 2)[0]
                updates[name] = rebuild_shard(blocks, raw[:header])
        added[str(dest)] = extend_sprite_pack(jar, updates, android, dest)
    return updates, {'androidSpriteSlotsReencoded': converted, 'identicalOriginalSlots': identical,
                     'newSpriteSlots': added}
