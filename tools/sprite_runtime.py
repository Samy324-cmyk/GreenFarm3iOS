"""Extend the original ASprite decoder with per-pixel Android alpha."""
import hashlib
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory
from .timing.classfile import ClassFile, code_parts, convert_helper, instruction_offsets, pack_code, u2


def patch_renderer(jar):
    cf = ClassFile(jar.read('e.class'))
    def field(name, desc):
        nt = cf.intern(b'\x0c' + u2(cf.utf(name)) + u2(cf.utf(desc)))
        return u2(cf.intern(b'\x09' + u2(cf.cls('e')) + u2(nt)))
    mask = field('gf3Alpha', '[[B')
    cf.fields.append((2, cf.utf('gf3Alpha'), cf.utf('[[B'), []))
    transparent = field('a', 'Z')
    expected = {'([BI)V':'72b26d8ddc311bdcfff48751dcd917e2a899eaf4f98bf0d7f9d47eda3273f3a3',
                '(I)[I':'e74aca45fb917111b328f1d0ca02a8772c544e19c4fa9abbd93cdf97b649eb73'}
    # Largest converted module is the 44,400-pixel panel in UI slot 124.
    capacity = u2(cf.intern(b'\x03' + struct.pack('>i', 44400)))
    wrappers, resized = [], 0
    for i, (access, name, desc, attrs) in enumerate(cf.methods):
        d = cf.string(desc)
        if cf.string(name) != 'a' or d not in (*expected, '([I)[I'):
            continue
        for j, (tag, body) in enumerate(attrs):
            if cf.string(tag) != 'Code':
                continue
            header, code, exc, extra = code_parts(body)
            if d in expected and hashlib.sha256(code).hexdigest() != expected[d]:
                raise ValueError('Unknown original sprite decoder')
            updated = bytearray(code)
            for pc in instruction_offsets(code):
                if code[pc:pc+5] == bytes.fromhex('116cb8bc0a'):
                    updated[pc:pc+3] = b'\x13' + capacity
                    resized += 1
            attrs[j] = tag, pack_code(header, updated, exc, extra)
        if d not in expected:
            continue
        old_name = 'gf3Load' if d == '([BI)V' else 'gf3Decode'
        old = u2(cf.ref('e', old_name, d))
        cf.methods[i] = 2, cf.utf(old_name), desc, attrs
        if d == '([BI)V':
            read = u2(cf.ref('GF3Alpha','read','([B)[[B'))
            has_alpha = u2(cf.ref('GF3Alpha','hasTransparency','(Z[[B)Z'))
            wrapper = (bytes.fromhex('2a2b1cb7') + old + bytes.fromhex('2a2bb8') + read
                       + b'\xb5' + mask + bytes.fromhex('2a2ab4') + transparent
                       + bytes.fromhex('2ab4') + mask + b'\xb8' + has_alpha + b'\xb5' + transparent + b'\xb1')
            locals_count = 3
        else:
            apply = u2(cf.ref('GF3Alpha','apply','([I[[BI)[I'))
            wrapper = bytes.fromhex('2a1bb7') + old + bytes.fromhex('2ab4') + mask + bytes.fromhex('1bb8') + apply + b'\xb0'
            locals_count = 2
        wrappers.append((access, name, desc, [(cf.utf('Code'),
                         pack_code(u2(3)+u2(locals_count), wrapper, u2(0), []))]))
    if resized != 3 or len(wrappers) != 2:
        raise ValueError('Missing sprite rendering call sites')
    cf.methods.extend(wrappers)
    with TemporaryDirectory() as tmp:
        src = Path(__file__).resolve().parents[1] / 'src/sprites/GF3Alpha.java'
        subprocess.run(['javac','--release','8','-g:none','-d',tmp,str(src)], check=True)
        helper = convert_helper((Path(tmp)/'GF3Alpha.class').read_bytes())
    return {'e.class':cf.bytes(), 'GF3Alpha.class':helper}
