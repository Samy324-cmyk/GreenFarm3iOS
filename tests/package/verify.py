"""Check the install descriptor, CLDC stack maps and device API linkage of the packaged MIDlet."""
from pathlib import Path
import argparse
import hashlib
import struct
import sys
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.timing.classfile import ClassFile, Reader, code_parts, instruction_offsets


def classname(cf, index):
    return cf.string(int.from_bytes(cf.pool[index][1:3], 'big'))


def read_classes(archive):
    with ZipFile(archive) as jar:
        return {name[:-6]: ClassFile(jar.read(name)) for name in jar.namelist() if name.endswith('.class')}


def class_members(classes):
    result = {}
    for name, cf in classes.items():
        declaration = Reader(cf.declaration)
        declaration.take(4)
        superclass = declaration.u2()
        parents = [classname(cf, superclass)] if superclass else []
        parents.extend(classname(cf, declaration.u2()) for _ in range(declaration.u2()))
        members = {(cf.string(n), cf.string(d)) for flags, n, d, attrs in cf.fields + cf.methods}
        result[name] = members, parents
    return result


def resolves(registry, owner, key):
    if owner not in registry:
        return False
    members, parents = registry[owner]
    return key in members or (key[0] != '<init>' and any(resolves(registry, p, key) for p in parents))


def check_code(cf, data):
    _, code, handlers, attributes = code_parts(data)
    boundaries = set(instruction_offsets(code))
    targets = {h for _, _, h, _ in struct.iter_unpack('>4H', handlers[2:])}
    for pc in boundaries:
        op = code[pc]
        if 0x99 <= op <= 0xa8 or op in (0xc6, 0xc7):
            targets.add(pc + struct.unpack_from('>h', code, pc+1)[0])
        elif op in (0xc8, 0xc9):
            targets.add(pc + struct.unpack_from('>i', code, pc+1)[0])
        elif op in (0xaa, 0xab):
            offset = (pc+4) & ~3
            default, first = struct.unpack_from('>ii', code, offset)
            targets.add(pc+default)
            if op == 0xaa:
                last, = struct.unpack_from('>i', code, offset+8)
                targets.update(pc+j for j in struct.unpack_from('>'+str(last-first+1)+'i', code, offset+12))
            else:
                targets.update(pc+struct.unpack_from('>i', code, offset+12+8*i)[0] for i in range(first))
    frames = {0}
    for tag, payload in attributes:
        if cf.string(tag) != 'StackMap':
            continue
        reader = Reader(payload)
        for _ in range(reader.u2()):
            frames.add(reader.u2())
            for group in range(2):
                for _ in range(reader.u2()):
                    if reader.u1() in (7, 8):
                        reader.take(2)
        if reader.pos != len(payload):
            raise ValueError('Invalid CLDC frame table')
    if targets - frames or (frames | targets) - boundaries:
        raise ValueError(f'Invalid CLDC branch frames {sorted(targets-frames)}, offsets {sorted(frames-boundaries)}')


def check(jar, jad, libraries):
    classes = read_classes(jar)
    standard = {}
    for library in libraries:
        standard.update(read_classes(library))
    registry = class_members(dict(standard, **classes))
    count = methods = 0
    for name, cf in classes.items():
        if cf.header[4:8] != bytes.fromhex('0003002d'):
            raise ValueError(f'Unexpected device class version in {name}')
        for _, n, d, attrs in cf.methods:
            for tag, data in attrs:
                if cf.string(tag) == 'Code':
                    try:
                        check_code(cf, data)
                    except ValueError as err:
                        raise ValueError(f'{name}.{cf.string(n)}{cf.string(d)}: {err}') from err
                    methods += 1
        if not name.startswith('GF3'):
            continue
        for ref in cf.pool:
            if not ref or ref[0] not in (9, 10, 11):
                continue
            owner = classname(cf, int.from_bytes(ref[1:3], 'big'))
            signature = cf.pool[int.from_bytes(ref[3:5], 'big')]
            key = cf.string(int.from_bytes(signature[1:3], 'big')), cf.string(int.from_bytes(signature[3:5], 'big'))
            if not resolves(registry, owner, key):
                raise ValueError(f'{name} calls unresolved {owner}.{key[0]}{key[1]}')
            count += 1
    fields = dict(line.split(': ', 1) for line in jad.read_text('utf-8').splitlines() if line)
    with ZipFile(jar) as archive:
        manifest = dict(line.split(': ',1) for line in archive.read('META-INF/MANIFEST.MF').decode('utf8').splitlines() if ': ' in line)
        suite_icon = manifest['MIDlet-Icon']
        if manifest['MIDlet-1'].split(',')[1].strip() != suite_icon:
            raise ValueError('The launcher and the suite use different artwork')
        icon = archive.read(suite_icon.lstrip('/'))
        if struct.unpack_from('>II',icon,16) != (512,512) or hashlib.sha256(icon).hexdigest() != 'c999c9fa409b39ff1c48cb957c047ddbb5a77221c4bedb00f54587c5cc92e1a5':
            raise ValueError('The launcher icon differs from the default Android 4.4.4 mipmap')
    for key in ('MIDlet-Name','MIDlet-Vendor','MIDlet-Version','MIDlet-1','MIDlet-Icon','MicroEdition-Profile','MicroEdition-Configuration'):
        if fields[key] != manifest[key]:
            raise ValueError(f'Manifest/JAD mismatch for {key}')
    if fields.get('Nokia-UI-Enhancement')!='EnableMultiPointTouchEvents' or fields.get('Nokia-UI-Enhancement')!=manifest.get('Nokia-UI-Enhancement'):
        raise ValueError('The JAD and JAR must request the same multipoint touch events')
    if fields.get('MIDlet-ScreenSize')!='480x800' or manifest.get('MIDlet-ScreenSize')!='480x800':
        raise ValueError('Manic EMU must detect the native 480x800 touch canvas on import')
    if fields['MIDlet-Jar-URL'] != jar.name or int(fields['MIDlet-Jar-Size']) != jar.stat().st_size:
        raise ValueError('Descriptor does not identify this JAR')
    if fields['MIDlet-Version'] != '4.4.4':
        raise ValueError('The install descriptor must identify the ported Android release')
    print(f'MIDP_PACKAGE_OK classes={len(classes)} methods={methods} helperLinks={count}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('jar','jad','cldc_api','midp_api'):
        parser.add_argument(key,type=Path)
    args = parser.parse_args()
    check(args.jar,args.jad,[args.cldc_api,args.midp_api])
