"""Expand the original quest registry, completion array and journal navigation."""
from tools.timing.classfile import ClassFile, code_parts, pack_code, u2
from .hives import patch_code


def patch_retrieval_batches(data):
    """Only place the next journal search when the previous farm crates are gone."""
    cf = ClassFile(data)
    marker_type = cf.intern(b'\x0c' + u2(cf.utf('h')) + u2(cf.utf('S')))
    marker = b'\xb2' + u2(cf.intern(b'\x09' + u2(cf.cls('a')) + u2(marker_type)))
    name = 'gf3CanPlaceSearch'
    # Preserve the journal's per-quest marker. A deferred search must still be
    # eligible when the player opens that objective after collecting the old lot.
    before = marker + bytes.fromhex('1c04609f0015')
    after = b'\x1c\xb8' + u2(cf.ref('a',name,'(I)Z')) + bytes.fromhex('0000990015')
    patch_code(cf,'aB','()V',[(371,before,after)])
    # Android cGame.zB queries s1.n for any actor of type 22 before placement.
    # The native MIDP overload scans all actors in the equivalent farm layer.
    find = b'\xb8' + u2(cf.ref('f','a','(II[Lf;I)I'))
    code = (bytes.fromhex('1a0460') + marker + bytes.fromhex('9f001303101604bd') +
            u2(cf.cls('f')) + b'\x04' + find + bytes.fromhex('9a000504ac03ac'))
    stack_map = u2(1) + u2(25) + u2(1) + b'\x01' + u2(0)
    body = pack_code(u2(4)+u2(1),code,u2(0),[(cf.utf('StackMap'),stack_map)])
    cf.methods.append((0x000a,cf.utf(name),cf.utf('(I)Z'),[(cf.utf('Code'),body)]))
    return cf.bytes()


def patch_journal(data):
    sites = {
        'ei()V':[(14,297)], 'ej()V':[(15,297)], 'ek()V':[(17,296)], 'el()V':[(18,296)],
        'f(I)Ljava/lang/String;':[(8,297)], 'q(Z)V':[(1867,297),(1875,297),(1893,297)],
        '<clinit>()V':[(11771,297)]
    }
    cf = ClassFile(data)
    for _,n,d,attrs in cf.methods:
        key = cf.string(n)+cf.string(d)
        if key not in sites:
            continue
        for j,(tag,body) in enumerate(attrs):
            if cf.string(tag) != 'Code':
                continue
            header, code, exc, extra = code_parts(body)
            updated = bytearray(code)
            for pc,value in sites.pop(key):
                if updated[pc:pc+3] != b'\x11' + value.to_bytes(2,'big'):
                    raise ValueError(f'Unsupported journal {key} at {pc}')
                updated[pc+1:pc+3] = (value+7).to_bytes(2,'big')
            attrs[j] = tag,pack_code(header,updated,exc,extra)
    if sites:
        raise ValueError('Missing journal entry points')
    return patch_retrieval_batches(cf.bytes())
