"""Translate verified parts of the 4.4.4 farm data to the MIDP reader."""
import struct
from .media import read_groups, write_groups


def entries(data):
    count, parts, first = struct.unpack_from('<3H', data)
    if (parts, first) != (1, 0):
        raise ValueError('Expected a single-part resource')
    offsets = struct.unpack_from(f'<{count + 1}I', data, 6)
    if (offsets[0] != 6 + 4 * len(offsets) or offsets[-1] != len(data)
            or sorted(offsets) != list(offsets)):
        raise ValueError('Invalid resource index')
    return [data[a:b] for a, b in zip(offsets, offsets[1:])]


def pack(chunks):
    positions = [6 + 4 * (len(chunks) + 1)]
    for chunk in chunks:
        positions.append(positions[-1] + len(chunk))
    return (struct.pack('<3H', len(chunks), 1, 0)
            + struct.pack(f'<{len(positions)}I', *positions) + b''.join(chunks))


def table(data):
    if data[0] != 2:
        raise ValueError('Expected numeric table')
    rows, columns = struct.unpack_from('<2i', data, 1)
    widths = data[9:9 + columns]
    fmt = struct.Struct('<' + ''.join({1: 'b', 2: 'h', 4: 'i'}[w] for w in widths))
    values = list(fmt.iter_unpack(data[9 + columns:]))
    if len(values) != rows:
        raise ValueError('Row count differs from header')
    return fmt, values


def labels(binary):
    result = {}
    for chunk in entries(binary):
        if chunk[0] != 2:
            raise ValueError('Expected indexed language resource')
        group = chunk[1]
        count, = struct.unpack_from('<I', chunk, 2)
        ends = struct.unpack_from(f'<{count}I', chunk, 6)
        base, start = 6 + count * 4, 0
        for index, end in enumerate(ends):
            if end < start or base + end > len(chunk):
                raise ValueError('Bad string offset')
            result[(group << 10) + index] = chunk[base + start:base + end].decode('utf-8')
            start = end
        if base + start != len(chunk):
            raise ValueError('Unexpected string data')
    return result


def translated_recipes(mobile, android, mobile_names, android_names):
    # MIDP a.gt() versus APK cGame.Bb(): output product changed from column
    # 18 to 17. Product rows, text IDs and the Android per-recipe text in
    # column 18 are not interchangeable between releases.
    fmt, original = table(mobile[7])
    android_recipes = table(android[7])[1]
    products = table(mobile[1])[1]
    other_products = table(android[1])[1]
    by_id = {row[1]: row for row in android_recipes}
    product_index = {(row[1], mobile_names[row[2]]): row[0] for row in products}
    converted, missing = [], []
    for row in original:
        source = by_id.get(row[1])
        if (source is None or source[2] not in android_names or row[2] not in mobile_names
                or android_names[source[2]] != mobile_names[row[2]]):
            missing.append(row[1])
            converted.append(row)
            continue
        new = list(row)
        for src_col, dst_col in ((6, 6), (9, 9), (17, 18)):
            product = other_products[source[src_col]]
            key = product[1], android_names[product[2]]
            if key not in product_index:
                break
            new[dst_col] = product_index[key]
        else:
            for col in (7, 8, 10, 11, 12, 14, 15, 16):
                new[col] = source[col]
            converted.append(tuple(new))
            continue
        missing.append(row[1])
        converted.append(row)
    widths = mobile[7][9:9 + len(original[0])]
    payload = mobile[7][:9] + widths + b''.join(fmt.pack(*row) for row in converted)
    return payload, {
        'commonRecipesTranslated': len(converted) - len(missing),
        'recipesWithUpdatedValues': sum(a != b for a, b in zip(original, converted)),
        'unmatchedReferenceRecipeIds': missing,
        'androidOnlyRecipeIds': sorted(set(by_id) - {row[1] for row in original}),
    }


def translate_campaign(mobile, android, localized, android_text):
    """Resolve all Android quest rows for the MIDP journal and its three objective slots."""
    groups = read_groups(localized)
    by_text = {(group, text): (group << 10) + index for group, rows in groups.items()
               for index, text in enumerate(rows)}
    added = 0

    def localized_id(value):
        nonlocal added
        if value <= 0:
            return value
        group = value >> 10
        text = android_text[value]
        if (group, text) not in by_text:
            if group not in groups or len(groups[group]) >= 1024:
                raise ValueError(f'Quest language group {group} exceeds MIDP addressing')
            by_text[group, text] = (group << 10) + len(groups[group])
            groups[group].append(text)
            added += 1
        return by_text[group, text]

    fmt, original = table(mobile)
    source = table(android)[1]
    result = []
    # J2ME a.f(int,int,boolean) and APK cGame.VA have the same three
    # objective slots. Android inserted telemetry columns between them.
    if len(original) != 297 or len(source) != 304:
        raise ValueError('Unknown quest catalog')
    for i,new in enumerate(source):
        old = original[i] if i < len(original) else None
        if new[0] != i or (old and old[:2] != new[:2]):
            raise ValueError('Quest ID/order mismatch')
        row = list(old) if old else [0]*len(original[0])
        row[:3] = new[:3]
        for to, frm in ((3,3),(5,5),(6,6),(13,11),(18,16),(23,22),(28,28)):
            row[to] = localized_id(new[frm])
        for to, frm in ((4,4),(7,7),(8,8),(9,8),(10,9),(11,9),
                        (14,12),(15,13),(16,14),(17,15)):
            row[to] = new[frm]
        # VA awards experience and coins; its completion method has no third
        # reward. The older MIDP completion method would grant extra currency.
        row[12] = 0
        for start, src in ((19,17),(24,23),(29,29)):
            if old and (old[start],old[start+2],old[start+3]) != (new[src],new[src+2],new[src+3]):
                raise ValueError(f'Unmapped quest objective in {row[1]}')
            row[start:start+4] = new[src:src+4]
        if any(pre >= len(source) for pre in row[15:18]):
            raise ValueError(f'Unknown quest prerequisite in {row[1]}')
        result.append(fmt.pack(*row))
    header = bytearray(mobile[:9 + len(original[0])])
    struct.pack_into('<I',header,1,len(result))
    return (header + b''.join(result), write_groups(groups),
            {'sharedQuestDefinitions': len(original), 'totalQuestDefinitions':len(result),
             'additionalTextSlots': added, 'newQuestIds': [row[1] for row in source[len(original):]]})


def build_world(jar, apk, localized):
    prefix = 'assets/800x480/'
    mobile_map = entries(jar.read('10'))
    android_map = entries(apk.read(prefix + '14'))
    if (mobile_map[1:3] != android_map[1:3] or
            not set(android_map[0][1:]).issubset(mobile_map[0][1:]) or
            len(android_map[0]) != len(mobile_map[0])):
        raise ValueError('Terrain layout or tile numbering is incompatible')
    # Android's northernmost 18 rows contain only transparent tile 0xff.
    # GF3Horizon composes the three source scenery layers under that space.
    original_tiles, android_tiles = mobile_map[0][1:], android_map[0][1:]
    if android_map[2][1:5] != struct.pack('<HH',58,58) or android_tiles[:18*58]!=b'\xff'*(18*58):
        raise ValueError('Unknown Android northern horizon layout')
    changed_tiles = sum(a != b for a,b in zip(original_tiles,android_tiles))
    mobile_map[:3] = android_map[:3]
    mobile = entries(jar.read('9'))
    android = entries(apk.read(prefix + '13'))
    if len(mobile) != len(android) or len(mobile) != 34:
        raise ValueError('Unexpected catalogue')
    mobile[7], report = translated_recipes(mobile, android, labels(jar.read('EN')),
                                          labels(apk.read(prefix + 'EN')))
    mobile[6], localized, report['campaign'] = translate_campaign(
        mobile[6], android[6], localized, labels(apk.read(prefix + 'LATAM')))
    report['terrainCellsFromAndroid'] = len(android_tiles)
    report['terrainCellsUsingOriginalTouchGround'] = 0
    report['terrainCellsChanged'] = changed_tiles
    report['tableRowCounts'] = [
        {'table': i, 'reference': len(table(left)[1]), 'android': len(table(right)[1])}
        for i, (left, right) in enumerate(zip(mobile, android))
    ]
    return {'9': pack(mobile), '10': pack(mobile_map)}, localized, report
