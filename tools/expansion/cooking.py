"""Adapt the Android recipe catalog to the MIDP cooker's native tabs and recipe queue."""
from pathlib import Path
import subprocess
import tempfile
from tools.catalog_ext import encode_table
from tools.media import read_groups, write_groups
from tools.world import table, labels
from tools.timing.classfile import ClassFile, code_parts, convert_helper, pack_code, u2


def build_recipes(mobile, android, apk, locale):
    source = table(android[7])[1]
    reference = table(mobile[7])[1]
    stock, products = table(mobile[1])[1], table(android[1])[1]
    if [item[:2] for item in stock] != [item[:2] for item in products]:
        raise ValueError('All Android recipe ingredients must exist in inventory')
    if len(reference) != 83 or [r[1] for r in source] != list(range(6000,6104)):
        raise ValueError('Unsupported recipe IDs')
    groups = read_groups(locale)
    strings = {(g,t):g*1024+i for g,items in groups.items() for i,t in enumerate(items)}
    es = labels(apk.read('assets/800x480/LATAM'))
    recipes = []
    for row in source:
        name = es[row[2]]
        group = row[2] >> 10
        if (group,name) not in strings:
            if len(groups[group]) >= 1024:
                raise ValueError('No free recipe language slots')
            strings[group,name] = group*1024+len(groups[group])
            groups[group].append(name)
        if any(not 0 <= row[k] < len(products) for k in (6,9,17)):
            raise ValueError('Recipe points outside the product registry')
        # MIDP has a second regional XP field at 17. Android stores its
        # output at 17 and a telemetry ID at 18.
        recipes.append([*row[:2],strings[group,name],*row[3:17],row[16],row[17]])
    return encode_table(mobile[7],recipes), write_groups(groups)


def patch_cooking(data):
    cf = ClassFile(data)
    category = b'\xb8' + u2(cf.ref('GF3HoneyKitchen','category','([[II)I'))
    records = b'\xb8' + u2(cf.ref('GF3HoneyKitchen','starredRecord','([[II)[I'))
    award = b'\xb8' + u2(cf.ref('a','gf3AwardStarred','(I)V'))
    # Only the category lookup in each method changes. Other column-4
    # reads in these long methods concern product icons and stay original.
    edits = {'q(I)Z':[(293,b'\x32\x07\x2e',category)],
             'gt()V':[(40,b'\x32\x07\x2e',category)],
             'v(I)V':[(96,b'\x32\x07\x2e',category)],
             's(Z)V':[(52,b'\x04\x60\x32',records)],
             'g(II)V':[(314,b'\x10\x53',b'\x10\x68'),
                       (413,bytes.fromhex('031504046004b804b357'),b'\x15\x04'+award+b'\x00'*5)],
             'aq(I)V':[(12,b'\x10\x53',b'\x10\x68')],
             'q(Z)V':[(1933,b'\x10\x53',b'\x10\x68'),(1950,b'\x10\x53',b'\x10\x68')]}
    for _, n, d, attrs in cf.methods:
        key = cf.string(n)+cf.string(d)
        if key not in edits:
            continue
        for i,(tag,body) in enumerate(attrs):
            if cf.string(tag) != 'Code':
                continue
            header, ins, exceptions, extra = code_parts(body)
            code = bytearray(ins)
            for pc,old,new in edits.pop(key):
                if code[pc:pc+len(old)] != old or len(old) != len(new):
                    raise ValueError(f'Unsupported native recipe call site {key}+{pc}')
                code[pc:pc+len(old)] = new
            attrs[i] = tag,pack_code(header,code,exceptions,extra)
    if edits:
        raise ValueError('Missing native recipe method')
    star = u2(cf.ref('GF3HoneyKitchen','starred','(I)I'))
    add_stock = u2(cf.ref('a','a','(III)Z'))
    code = b'\x03\x1a\xb8' + star + b'\x04\xb8' + add_stock + b'\x57\xb1'
    cf.methods.append((10,cf.utf('gf3AwardStarred'),cf.utf('(I)V'),[
        (cf.utf('Code'),pack_code(u2(3)+u2(1),code,u2(0),[]))]))
    src = Path(__file__).resolve().parents[2] / 'src/expansion/GF3HoneyKitchen.java'
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(['javac','--release','8','-g:none','-d',tmp,str(src)],check=True)
        helper = convert_helper((Path(tmp)/'GF3HoneyKitchen.class').read_bytes())
    return {'a.class':cf.bytes(), 'GF3HoneyKitchen.class':helper}
