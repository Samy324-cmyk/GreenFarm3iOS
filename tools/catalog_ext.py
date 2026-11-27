"""Adapt native farm catalog columns and stable game IDs to the MIDP engine."""
import struct
from pathlib import Path
import subprocess
import tempfile

from .media import PET_SOURCE_TO_SLOT, read_groups, write_groups
from .world import entries, labels, pack, table
from .timing.classfile import ClassFile, code_parts, convert_helper, instruction_offsets, pack_code, u2


# Source columns in the order consumed by the touchscreen engine. That
# engine has a second regional economy mode (a.q(boolean)); both variants
# now intentionally receive the APK's value for each duplicated column.
INVENTORY = (0,1,2,3,4,5,5,6,6,7,8,9,10,11,12,13,14,15)
CROPS = (0,1,2,3,4,5,6,18,19,20,21,22,23,23,24,25,26,26,27,28,29)
BUILDINGS = (0,1,2,4,5,6,7,8,9,10,11,12,13,14,14,15,15,16,17,18,19,20,21,
             22,23,24,25,26,27,28,29,30,30,31,33)
ANIMALS = (0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,16,*range(17,38))
DECOR = (*range(20),19)
SCHEMAS = {0: ANIMALS, 1: INVENTORY, 2: CROPS, 3: BUILDINGS, 4: DECOR}
BASE = {0: 64, 1: 117, 2: 22, 3: 20, 4: 63}
FULL = {0: 76, 1: 141, 2: 24, 3: 30, 4: 69}


def encode_table(original, rows):
    """Keep each legacy column width unless the APK values require widening."""
    widths = list(original[9:9+len(rows[0])])
    if any(len(row) != len(widths) for row in rows):
        raise ValueError('Inconsistent target table width')
    types = {1:'b', 2:'h', 4:'i'}
    for col, width in enumerate(widths):
        low, high = min(row[col] for row in rows), max(row[col] for row in rows)
        widths[col] = next(w for w in types if w >= width and
                           -(1 << (8*w-1)) <= low <= high < (1 << (8*w-1)))
    fmt = struct.Struct('<' + ''.join(types[w] for w in widths))
    return (b'\2' + struct.pack('<2I',len(rows),len(widths)) + bytes(widths) +
            b''.join(fmt.pack(*row) for row in rows))


def build_catalog(jar, apk, table_pack, locale_pack, counts=None):
    """Apply verified common economy changes and rows supported by the caller.

    The first new product, dog chow, uses the restored dog-feed frame in UI
    sprite 34. Increase further counts once their renderer/behavior is wired.
    """
    limits = {**BASE, 1:118, **(counts or {})}
    mobile, android = entries(table_pack), entries(apk.read('assets/800x480/13'))
    en_mobile, en_android = labels(jar.read('EN')), labels(apk.read('assets/800x480/EN'))
    es_android = labels(apk.read('assets/800x480/LATAM'))
    groups = read_groups(locale_pack)
    es_ids = {(g,s): g*1024+i for g,rows in groups.items() for i,s in enumerate(rows)}
    report = {}

    def localized(key):
        if key <= 0:
            return key
        g,s = key >> 10, es_android[key]
        if (g,s) not in es_ids:
            if len(groups[g]) >= 1024:
                raise ValueError(f'No remaining language slots in group {g}')
            es_ids[g,s] = g*1024 + len(groups[g])
            groups[g].append(s)
        return es_ids[g,s]

    for idx,schema in SCHEMAS.items():
        original, source = table(mobile[idx])[1], table(android[idx])[1]
        if (len(original),len(source)) != (BASE[idx],FULL[idx]) or not BASE[idx] <= limits[idx] <= FULL[idx]:
            raise ValueError(f'Unsupported catalog dimensions for table {idx}')
        rows = []
        for i,row in enumerate(source[:limits[idx]]):
            mapped = [row[col] for col in schema]
            if i < len(original):
                old = original[i]
                if old[:2] != row[:2] or en_mobile.get(old[2]) != en_android.get(row[2]):
                    raise ValueError(f'ID or name mismatch in table {idx}, row {i}')
                # Preserve release-specific atlas frame, palette and collision
                # dimensions. Shared IDs use the MIDP label already localized.
                common = {
                    0: (6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26),
                    1: tuple(range(5,18)),
                    2: tuple(range(6,19)),
                    3: (6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,31,32,33),
                    4: (6,7,8,18,19,20),
                }[idx]
                result = list(old)
                for col in common:
                    result[col] = mapped[col]
                if idx==0 and row[37]==20:
                    result[37] = 21
            else:
                result = mapped
                result[2] = localized(row[2])
                if idx == 0:
                    # MIDP uses one extra leading sound in this group.
                    result[37] = PET_SOURCE_TO_SLOT.get(row[37],row[37]+1)
                    result[27:29] = [s//2 for s in row[27:29]]
                    # Android category zero is the separate Super Animals
                    # tab in MIDP. Normal livestock starts at zero here.
                    result[9] = row[10]-1
                    if i in (66,67):
                        # The original MIDP pig has fewer palettes and other
                        # animation anchors. World slot 188 is the converted
                        # full Android slot 19 exclusively for these two rows.
                        result[3],result[31] = 1188,188
                elif idx == 2:
                    # The MIDP shop combines fields, trees and hives.
                    result[5] = i
                elif idx == 3 and 24 <= i <= 26:
                    # The APK has a separate doghouse shelf. Present these
                    # after the extractor on the single MIDP buildings tab.
                    result[5] = 6 + (limits[3] > 28) + i-24
                elif idx == 4 and i >= 64:
                    result[5] = 64+row[5]
            if idx==0 and 28<=i<40 and limits[0]>66:
                result[5] = row[6]
            if idx==4 and i<63 and limits[4]>63:
                result[5] = row[5]
            rows.append(tuple(result))
        mobile[idx] = encode_table(mobile[idx], rows)
        report[str(idx)] = {'sharedRowsUpdated':sum(a!=b for a,b in zip(original,rows)),
                            'addedGameIds':[r[1] for r in rows[len(original):]],
                            'sourceRows':len(source)}
    if limits[0] >= 70:
        categories = table(mobile[13])[1]
        if len(categories)!=5:
            raise ValueError('Unexpected animal category list')
        dog = table(android[13])[1][6]
        mobile[13] = encode_table(mobile[13],[*categories,(5,localized(dog[1]),dog[2],dog[3])])
    return pack(mobile), write_groups(groups), report


# Verified immediates in the reference class. These methods also contain
# unrelated numeric menu coordinates, text IDs and sprite IDs of the same
# value, so change only the operands consumed by the corresponding code.
SITES = {
    117: {
        'gh()V': (9,70,156), 'n(I)I': (58,), 'b(I)I': (48,),
        'q(Z)V': (1580,1587,1594,1610), 'b()Z': (564,575,1571,1582),
        'a(ILh;)V': (248,259), 'n(I)Z': (51,), 'a([I)V': (194,),
        'gt()V': (103,), 'q(I)Z': (379,488), 'aA(I)V': (25,),
        'w(I)Z': (197,204,211,218,225,232,239,246,253),
        'x(I)Z': (182,189,196,203,210,217,224),
    },
    20: {'gh()V': (18,79,162), 'n(I)I': (74,), 'b(I)I': (54,), 'a([I)V': (212,),
         'q(Z)V': (2017,2033)},
    63: {'gh()V': (27,88,168), 'n(I)I': (90,), 'b(I)I': (60,), 'a([I)V': (221,),
         'q(Z)V': (1826,1842), 'b()Z': (887,898)},
    64: {'gh()V': (36,97,174), 'n(I)I': (106,), 'b(I)I': (66,), 'a([I)V': (203,),
         'q(Z)V': (1724,1731,1747)},
    10: {'gh()V': (45,106,180), 'n(I)I': (122,), 'b(I)I': (72,), 'a([I)V': (234,)},
    22: {'q(Z)V': (1663,1670,1686)},
    159: {'q(Z)V': (1345,1452,1479,1512,1545)},
    122: {'q(Z)V': (1460,1489,1522,1555), 'fC()V': (89,100)},
    6: {'c(Z)V': (507,), 'b(Z)Z': (561,)},
}


def reserve_constants(cf, values):
    # Keep jumps, exception tables and CLDC StackMap PCs intact. An LDC of
    # an integer can replace a two-byte bipush even when the new count >127.
    # Fieldrefs at low indices have no constant-pool inbound references in
    # CLDC 1.1: their only users are the four field-access opcodes below.
    displaced, constants = {}, {}
    for count in sorted(set(values)):
        entry = b'\3' + struct.pack('>i',count)
        if entry in cf.pool[:256]:
            constants[count] = cf.pool.index(entry)
        else:
            index = next(i for i,ref in enumerate(cf.pool[:256]) if ref and ref[0]==9)
            displaced[index] = len(cf.pool)
            cf.pool.append(cf.pool[index])
            cf.pool[index] = entry
            constants[count] = index
    if displaced:
        for _,_,_,attrs in cf.methods:
            for i,(tag,body) in enumerate(attrs):
                if cf.string(tag)!='Code':
                    continue
                header,ins,ex,extra = code_parts(body)
                code = bytearray(ins)
                for pc in instruction_offsets(ins):
                    if 0xb2 <= ins[pc] <= 0xb5:
                        index = int.from_bytes(ins[pc+1:pc+3],'big')
                        if index in displaced:
                            code[pc+1:pc+3] = u2(displaced[index])
                if code != ins:
                    attrs[i] = tag,pack_code(header,code,ex,extra)
    return constants


def patch_catalog_class(data, counts=None, feed_count=7):
    limits = {**BASE, 1:118, **(counts or {})}
    resize = {117:limits[1], 20:limits[3], 63:limits[4], 64:limits[0],
              22:limits[2], 10:limits[2]-12, 159:189, 122:138, 6:feed_count}
    cf = ClassFile(data)
    constants = reserve_constants(cf,(resize[n] for n in (117,122) if resize[n]>127))

    sites = {(method,pc):(old,resize[old]) for old, methods in SITES.items()
             for method, pcs in methods.items() for pc in pcs}
    savehooks = {('c(Z)V',1409):('write','(Ljava/lang/String;[B)V'),
                 ('b(Z)Z',2):('read','(Ljava/lang/String;)[B')}
    for flags,n,d,attrs in cf.methods:
        method = cf.string(n)+cf.string(d)
        for i,(tag,body) in enumerate(attrs):
            if cf.string(tag) != 'Code':
                continue
            header,ins,exceptions,extra = code_parts(body)
            code = bytearray(ins)
            for pc in instruction_offsets(ins):
                key = method,pc
                if key in savehooks:
                    name,desc = savehooks.pop(key)
                    if ins[pc:pc+3] != b'\xb8'+u2(cf.ref('g','a',desc)):
                        raise ValueError(f'Unexpected RMS call at {key}')
                    code[pc+1:pc+3] = u2(cf.ref('GF3CatalogSave',name,desc))
                if key not in sites:
                    continue
                old,new = sites.pop(key)
                if ins[pc]==0x11 and int.from_bytes(ins[pc+1:pc+3],'big')==old:
                    code[pc+1:pc+3] = u2(new)
                elif ins[pc]==0x10 and ins[pc+1]==old:
                    code[pc:pc+2] = bytes((0x10,new)) if new<=127 else bytes((0x12,constants[new]))
                else:
                    raise ValueError(f'Unexpected catalog operand at {key}')
            if code != ins:
                attrs[i] = tag,pack_code(header,code,exceptions,extra)
    if sites or savehooks:
        raise ValueError('Required catalog patch sites missing')
    return cf.bytes()


def catalog_save_helper(javac='javac'):
    """Compile the RMS adapter against the two package-private engine APIs."""
    source = Path(__file__).resolve().parents[1]/'src/catalog/GF3CatalogSave.java'
    with tempfile.TemporaryDirectory() as temp:
        folder = Path(temp)
        stub = folder/'g.java'
        stub.write_text('class g {static byte[] a(String n){return null;} '
                        'static void a(String n,byte[] d){}} '
                        'class h {static h[] a; int b;}',encoding='ascii')
        subprocess.run([javac,'--release','8','-g:none','-d',str(folder),
                        str(stub),str(source)],check=True)
        return convert_helper((folder/'GF3CatalogSave.class').read_bytes())
