"""Bind the 4.4.4 farm atlases through the shared actors' actual catalog records."""
import struct
from .sprites import convert_sprite, geometry, rebuild_shard, shards
from .world import entries, table
from .timing.classfile import ClassFile, code_parts, instruction_offsets, pack_code, u2


def world_slots(jar, apk):
    # Costs/text and menu indices moved. These columns are the world images
    # consumed by each release's actor factory (NPC IDs come from table 8).
    j = entries(jar.read('9'))
    a = entries(apk.read('assets/800x480/13'))
    sources = {}
    for idx,old,new in ((0,31,31),(2,9,20),(3,25,24),(4,12,12),(8,3,3),(15,1,1)):
        for ref,src in zip(table(j[idx])[1],table(a[idx])[1]):
            if ref[:2]!=src[:2] or ref[old]!=src[new]:
                raise ValueError(f'Unmapped world art in table {idx}, row {ref[0]}')
            sources.setdefault(ref[old],set()).add(idx)
    # These direct references live in the actor renderer instead of a
    # catalog: tilled soil, player, placement and selection outlines, the
    # truck, field markers, farm grass and signs, dust and the flying flock.
    # Scenery 77–79 is drawn by f.b(); 135 accompanies the manor's slot 128.
    for slot in (1,2,3,10,14,77,78,79,80,84,98,135,141,143,147,157):
        sources.setdefault(slot,set()).add(-1)
    return sources


def sheep_aliases(sprite):
    # MIDP uses legacy direct lookups for its market portrait (67) and the
    # two sheep emotes (95,96). Android's table 0 specifies 35,63,64.
    # Keep the full Android frame order and append the old entry points.
    sig, _, reader, flags, extra = geometry(sprite)
    modules, fmods, rects, frames, _, _ = sig
    if len(frames)!=65 or flags & (0x1000|0x2000|0x800) or not flags&0x8000 or extra:
        raise ValueError('Unknown sheep frame layout')
    xy = 2 if flags&0x400 else 1
    record = (2 if flags&0x100000 else 1)+2*xy+(1 if flags&0x4000 else 0)+1
    pos = reader.module_end+2+len(fmods)*record+2+len(rects)*4*xy
    if struct.unpack_from('<H',sprite,pos)[0]!=65:
        raise ValueError('Could not locate sheep frame records')
    start = pos+2
    bounds = start+4*65
    tail = bounds+4*xy*65
    aliases = range(33,65)
    # Every frame keeps its own module start/length and true bounding box.
    # Hit rectangles are already present on the normal gameplay frames.
    extended = b''.join(sprite[start+4*i:start+4*i+3]+b'\0' for i in aliases)
    boxes = b''.join(sprite[bounds+4*xy*i:bounds+4*xy*(i+1)] for i in aliases)
    result = (sprite[:pos]+struct.pack('<H',97)+sprite[start:bounds]+extended
              +sprite[bounds:tail]+boxes+sprite[tail:])
    after = geometry(result)[0]
    if (after[3][:65]!=frames or after[4:]!=sig[4:]
            or any(after[3][i][:2]!=frames[i-32][:2] for i in range(65,97))):
        raise ValueError('Legacy sheep frame aliases do not match their APK poses')
    return result


def build_farm_art(jar, apk, updates):
    selected = world_slots(jar,apk)
    source = [b for blocks in shards(apk,'assets/800x480/9').values() for b in blocks]
    class Overlay:
        def read(self,name):
            return updates[name] if name in updates else jar.read(name)
    parts = shards(Overlay(),'5')
    original = [b for blocks in shards(jar,'5').values() for b in blocks]
    result = {}
    index = 0
    for name, blocks in parts.items():
        changed = False
        for i in range(len(blocks)):
            slot = index
            index += 1
            if slot not in selected:
                continue
            old = geometry(original[slot])[0]
            current = geometry(source[slot])[0]
            # The first action set holds the full-size poses, the latter
            # MIDP set serves its baked zoom. Actor state numbers stay fixed.
            if slot==157:
                # Both editions play one flock animation. MIDP repeats the
                # same four cels three times; APK runs its four once per
                # cycle with the offsets used by the original camera.
                if (old[5]!=((12,0),) or current[5]!=((4,0),) or
                        tuple(a[:2] for a in old[4])!=tuple(a[:2] for a in current[4])*3):
                    raise ValueError('Unrecognized flock animation')
            elif current[5] != old[5][:len(current[5])]:
                raise ValueError(f'Unmapped action IDs in farm sprite {slot}')
            if slot in (2,5,7,8,17,18,19,20,*range(86,96)):
                for n,(count,start) in enumerate(current[5]):
                    for a,b in zip(old[4][start:start+count],current[4][start:start+count]):
                        shift = 32 if slot==20 and n>=5 else 0
                        if a[0]-shift!=b[0] or a[1:]!=b[1:]:
                            raise ValueError(f'Unmapped actor pose {slot}/{n}')
            art = convert_sprite(source[slot])
            blocks[i] = sheep_aliases(art) if slot==20 else art
            changed = True
        if changed:
            raw = Overlay().read(name)
            end = 0 if '.' in name else 4+2*struct.unpack_from('<H',raw,2)[0]
            result[name] = rebuild_shard(blocks,raw[:end])
    return result, sorted(selected)


def patch_farm_zoom(data, selected):
    # f renders old half-size copies by indexing the second half of a
    # resource only for members of a.be. Converted atlases use the normal
    # scale-aware MIDP renderer at all zooms, like the added dog actors.
    cf = ClassFile(data)
    field_type = cf.intern(b'\x0c'+u2(cf.utf('be'))+u2(cf.utf('[I')))
    be = u2(cf.intern(b'\x09'+u2(cf.cls('a'))+u2(field_type)))
    for _,name,_,attrs in cf.methods:
        if cf.string(name)!='<clinit>':
            continue
        for j,(tag,body) in enumerate(attrs):
            if cf.string(tag)!='Code':
                continue
            header,code,ex,extra = code_parts(body)
            pc = list(instruction_offsets(code))
            end, = [i for i,p in enumerate(pc) if code[p:p+3]==b'\xb3'+be]
            start = next(i for i in range(end-1,0,-1) if code[pc[i]:pc[i]+2]==b'\xbc\x0a')
            result = bytearray(code)
            for n in range(start+1,end,4):
                dup,_,value,store = pc[n:n+4]
                if code[dup]!=0x59 or code[store]!=0x4f:
                    raise ValueError('Invalid MIDP pre-scaled sprite registry')
                op=code[value]
                slot = op-3 if 3<=op<=8 else int.from_bytes(code[value+1:store],'big',signed=True)
                if slot in selected:
                    result[value:store]=b'\x02'+b'\0'*(store-value-1)
            attrs[j] = tag,pack_code(header,result,ex,extra)
            return cf.bytes()
    raise ValueError('Missing sprite zoom registry')


def patch_farm_decode_buffer(data):
    cf = ClassFile(data)
    before = b'\x03'+struct.pack('>i',44400)
    if before not in cf.pool:
        raise ValueError('Missing expanded ASprite decode buffer')
    # Native common scenery slot 81 contains a 68,105-pixel raster module.
    cf.pool[cf.pool.index(before)] = b'\x03'+struct.pack('>i',68105)
    return cf.bytes()
