"""Translate Android's seven feed recipes for the original MIDP mill."""
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.timing.classfile import ClassFile, code_parts, pack_code, u2


def append_recipe(mobile_feed, android_feed, converted_products):
    """Return table 22. The inventory port supplies table 1 and its localized IDs."""
    from tools.world import table

    row_format, original = table(mobile_feed)
    source = table(android_feed)[1]
    products = table(converted_products)[1]
    if ([r[1] for r in original] != list(range(6500, 6506))
            or [r[1] for r in source] != list(range(6500, 6507))):
        raise ValueError("Unexpected mill recipe IDs")
    rows = []
    for recipe in source:
        for index in (recipe[5], recipe[8], recipe[14]):
            if index < 0 or index >= len(products) or products[index][1] != 4000 + index:
                raise ValueError(f"Unknown mill product {index} in recipe {recipe[1]}")
        # The Android recipe label and its output product have the same name.
        # Use that product's already localized MIDP label. The MIDP regional
        # initializer copies its alternate XP in col14 to the base XP in col13.
        row = list(recipe[:14]) + [recipe[13], recipe[14]]
        row[2] = products[recipe[14]][2]
        rows.append(row)
    header = bytearray(mobile_feed[:9 + len(original[0])])
    struct.pack_into("<i", header, 1, len(rows))
    return bytes(header) + b"".join(row_format.pack(*r) for r in rows)


def patch_mill(data):
    """Expand only recipe/product checks; the six visible slots are paged by MIDP."""
    edits = {
        # Upper bound of feed IDs used by 'go to mill' action. The original J[5]
        # expression is five bytes long, including getstatic, iconst and saload.
        ("f", "(II)V"): [(427, "b200f50835", "11196a0000")],
        # Mission/loot rewards for feed products go to their silo index.
        ("aR", "(I)V"): [(512, "1074", "1075")],
        # Resolve a queued recipe by ID at collection and refund.
        ("g", "(II)V"): [(54, "1006", "1007")],
        ("au", "(I)V"): [(12, "1006", "1007")],
        # Two encoded mirrors store silo stock, separate from barn product
        # counts. Initialize and total all seven positions in the native flow.
        ("p", "(Z)V"): [(124, "1006", "1007"), (131, "1006", "1007"),
                        (141, "1006", "1007")],
        ("z", "()I"): [(5, "1006", "1007")],
        # Cache all seven valid feed IDs at initialization.
        ("q", "(Z)V"): [(1975, "1006", "1007"), (1992, "1006", "1007")],
        # Output 117 now exists. Only table22 (not all product references) is
        # in scope for these checks; retain their previous behavior for >=118.
        ("r", "(I)Z"): [(256, "1075a2", "1075a3"), (349, "1075a2", "1075a3")],
    }
    cf = ClassFile(data)
    for _, n, d, attrs in cf.methods:
        key = cf.string(n), cf.string(d)
        if key not in edits:
            continue
        for i, (attribute, contents) in enumerate(attrs):
            if cf.string(attribute) != "Code":
                continue
            header, code, exceptions, extra = code_parts(contents)
            changed = bytearray(code)
            for pc, old, new in edits.pop(key):
                original, replacement = bytes.fromhex(old), bytes.fromhex(new)
                if changed[pc:pc + len(original)] != original:
                    raise ValueError(f"Unexpected reference mill bytecode {key} +{pc}")
                changed[pc:pc + len(original)] = replacement
            attrs[i] = attribute, pack_code(header, changed, exceptions, extra)
            break
    if edits:
        raise ValueError(f"Missing reference mill call sites {edits.keys()}")
    return patch_mill_lesson(cf.bytes())


def patch_mill_lesson(data):
    """Apply cGame.Gx's four zero costs while the first dog mission is active."""
    from .hives import patch_code

    cf = ClassFile(data)
    name = 'gf3MillValue'
    lookup = b'\xb8' + u2(cf.ref('a', name, '(II)I'))
    fields = cf.intern(b'\x0c' + u2(cf.utf('a')) + u2(cf.utf('[[I')))
    rows = b'\xb4' + u2(cf.intern(b'\x09' + u2(cf.cls('h')) + u2(fields)))
    fields = cf.intern(b'\x0c' + u2(cf.utf('a')) + u2(cf.utf('[Lh;')))
    tables = b'\xb2' + u2(cf.intern(b'\x09' + u2(cf.cls('h')) + u2(fields)))
    active = b'\xb8' + u2(cf.ref('a', 'i', '(I)Z'))
    # if (recipe == 6 && questActive(297)) return 0;
    # return h.tables[22].rows[recipe][column];
    code = (bytes.fromhex('1a1006a0000e110129') + active + bytes.fromhex('99000503ac') +
            tables + bytes.fromhex('101632') + rows + bytes.fromhex('1a321b2eac'))
    frame = u2(1) + u2(17) + u2(2) + b'\x01\x01' + u2(0)
    body = pack_code(u2(2)+u2(2), code, u2(0), [(cf.utf('StackMap'), frame)])
    cf.methods.append((10,cf.utf(name),cf.utf('(II)I'),[(cf.utf('Code'),body)]))
    edits = []
    for pc, column in ((139,7), (188,10), (200,11), (222,12)):
        operand = bytes((0x10,column))
        original = b'\x2a'+rows+b'\x1c\x32'+operand+b'\x2e'
        edits.append((pc,original,b'\x1c'+operand+lookup))
    patch_code(cf,'gz','()V',edits)
    return cf.bytes()
