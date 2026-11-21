"""Import Android heads-up display and menu artwork at the native MIDP frame IDs."""
import struct

from .sprites import convert_sprite, geometry, indices, midp_modules, midp_pixels, rebuild_shard, shards


# In both releases these sheets address the same control, panel, gesture,
# reward or item by frame number. The touch HUD has two conflicting frames.
HUD_SLOTS = (0,1,3,4,5,6,7,8,9,10,11,13,15,16,17,18,19,21,26,30,32,33,35,36,38,39,42,44,49)
ZOOM_FRAMES = (8,66)
ANDROID_ZOOM_ALIASES = {8:83,66:84}
# The Android shop inserted the dog and its house in the middle of its
# atlas. The MIDlet's existing lock animation still selects frames 11–13.
SHOP_FRAMES = (*range(10),12,13,14,15,10,11,16,17)


def _hud_frames(blob):
    shape,_,reader,flags,extra = geometry(blob)
    modules,parts,rects,frames,_,_ = shape
    if flags not in (0x1018581,0x1018591) or extra or any(m[0] for m in modules):
        raise ValueError('Unrecognized HUD control sheet')
    start = reader.module_end+2+len(parts)*6+2+len(rects)*8+2+len(frames)*4
    bounds = [blob[start+8*i:start+8*i+8] for i in range(len(frames))]
    result = []
    first_box = 0
    for (length,first,count),box in zip(frames,bounds):
        result.append((length,first,rects[first_box:first_box+count],box))
        first_box += count
    if first_box!=len(rects):
        raise ValueError('Inconsistent HUD collision rectangles')
    anim = blob[start+8*len(frames):reader.pos]
    colors = midp_modules(shape,reader,flags)
    return shape,result,anim,colors,flags


def touch_hud(legacy,android):
    """Keep the two signed MIDP magnifiers, including their measured touch rectangles."""
    old,oldframes,_,old_pixels,_ = _hud_frames(legacy)
    src,frames,anim,pixels,flags = _hud_frames(android)
    if (len(frames)!=83 or len(oldframes)!=67 or
            any(row[0] in ZOOM_FRAMES for row in src[4])):
        raise ValueError('The Android HUD frame aliases have changed')
    modules,parts = list(src[0]),list(src[1])
    count,_,colors,images = pixels
    pal = [colors[i:i+3] for i in range(0,len(colors),3)]
    old_count,_,old_colors,old_images = old_pixels
    if count!=old_count or count!=1:
        raise ValueError('Unexpected color variants in the HUD')
    imported = {}
    for i in ZOOM_FRAMES:
        # Preserve the Android blank magnifier and star at unused new IDs.
        # Existing MIDP logic uses frame 8 for zoom in and 66 for zoom out.
        frames.append(frames[i])
        length,first,rectangles,box = oldframes[i]
        frames[i] = length,len(parts),rectangles,box
        for m,x,y,pal_id,tr,_ in old[1][first:first+length]:
            if m not in imported:
                imported[m] = len(modules)
                modules.append(old[0][m])
                indexes = {}
                for idx in sorted(set(old_images[m])):
                    color = old_colors[idx*3:idx*3+3]
                    if color not in pal:
                        pal.append(color)
                    indexes[idx] = pal.index(color)
                images.append(bytes(indexes[v] for v in old_images[m]))
            parts.append((imported[m],x,y,pal_id,tr,b''))
    if len(pal)>256 or len(modules)>256:
        raise ValueError('Combined HUD exceeds the MIDP indexed-color limits')
    rects = [r for _,_,rr,_ in frames for r in rr]
    prefix = bytearray(android[:7])+struct.pack('<H',len(modules))
    for kind,w,h,_,_ in modules:
        prefix.extend(struct.pack('<BHH',kind,w,h))
    prefix.extend(struct.pack('<H',len(parts)))
    for module,x,y,_,transform,_ in parts:
        prefix.extend(struct.pack('<BhhB',module,x,y,transform))
    prefix.extend(struct.pack('<H',len(rects)))
    for r in rects:
        prefix.extend(struct.pack('<4h',*r))
    prefix.extend(struct.pack('<H',len(frames)))
    for length,first,rectangles,_ in frames:
        prefix.extend(struct.pack('<BHB',length,first,len(rectangles)))
    prefix.extend(b''.join(box for *_,box in frames)+anim)
    return midp_pixels((1,len(pal),b''.join(pal),images),flags,prefix)


def shop_controls(legacy,android):
    src,frames,_,_,_ = _hud_frames(android)
    shape,_,reader,_,_ = geometry(android)
    old = geometry(legacy)[0]
    if (len(frames)!=len(SHOP_FRAMES) or len(old[3])!=14 or
            tuple((SHOP_FRAMES.index(f),*vals) for f,*vals in src[4])!=old[4] or src[5]!=old[5]):
        raise ValueError('Unknown lock animation in shop controls')
    start = reader.module_end+2+len(shape[1])*6
    reordered = [frames[source] for source in SHOP_FRAMES]
    prefix = bytearray(android[:start])+struct.pack('<H',len(shape[2]))
    for _,_,rectangles,_ in reordered:
        for rect in rectangles:
            prefix.extend(struct.pack('<4h',*rect))
    prefix.extend(struct.pack('<H',len(frames)))
    for count,first,rectangles,_ in reordered:
        prefix.extend(struct.pack('<BHB',count,first,len(rectangles)))
    prefix.extend(b''.join(box for *_,box in reordered))
    prefix.extend(struct.pack('<H',len(src[4])))
    for frame,duration,x,y,transform in src[4]:
        prefix.extend(struct.pack('<BBbbB',SHOP_FRAMES.index(frame),duration,x,y,transform))
    if len(prefix)>reader.pos:
        raise ValueError('Unexpected shop frame metadata')
    return bytes(prefix)+android[len(prefix):]


def build_hud_art(jar,apk,updates):
    source = [b for group in shards(apk,'assets/800x480/11').values() for b in group]
    original = [b for group in shards(jar,'7').values() for b in group]
    class Overlay:
        def read(self,key):
            return updates[key] if key in updates else jar.read(key)
    overlay = Overlay()
    result = {}
    offset = 0
    for name,blocks in shards(overlay,'7').items():
        changed = False
        for slot in (*HUD_SLOTS,*FARM_CONTROLS):
            local = slot-offset
            if not 0<=local<len(blocks):
                continue
            old = geometry(original[slot])[0]
            art = geometry(source[slot])[0]
            if len(art[3])<len(old[3]) or (slot!=10 and any(old[i]!=art[i][:len(old[i])] for i in (4,5))):
                raise ValueError(f'Unknown control or animation indices in menu sheet {slot}')
            if slot in FARM_CONTROLS:
                blocks[local] = _farm_controls(original[slot],source[slot],FARM_CONTROLS[slot],
                                              PAUSE_FRAMES if slot==20 else ())
                changed = True
                continue
            data = convert_sprite(source[slot])
            if slot==1:
                data=touch_hud(original[slot],data)
            elif slot==10:
                data=shop_controls(original[slot],data)
            blocks[local] = data
            changed = True
        if changed:
            raw = overlay.read(name)
            header = 0 if '.' in name else 4+2*struct.unpack_from('<H',raw,2)[0]
            result[name] = rebuild_shard(blocks,raw[:header])
        offset += len(blocks)
    return result


# The touch engine refers to the rest of sheet 20 by its own frame IDs.
# Merge only shared control poses, keeping every remaining menu entry intact.
FARM_CONTROLS = {20:(0,1,15,16,17,70,75,113,118,122,147),41:(0,1,2,3)}
# Panel 15 and the Latin American choice of Android panel 26 need these
# source frame IDs. Keep the stock JAR's 199 public menu indices unchanged.
PAUSE_FRAMES = (27,28,29,30,139,140,146,172,173,175,269,283,284)
PAUSE_ALIAS = {frame:199+i for i,frame in enumerate(PAUSE_FRAMES)}

def _frames(sprite):
    (mods,parts,rects,frames,animation_parts,animations),loc,r,flags,_=geometry(sprite)
    if animation_parts or animations or flags&(0x800|0x1000|0x2000) or not flags&0x8000:
        raise ValueError('Unknown standalone HUD frame layout')
    size=8 if flags&0x400 else 4
    start=r.pos-4-len(frames)*size
    off=0
    records=[]
    for i,(n,first,nr) in enumerate(frames):
        rect=rects[off:off+nr];off+=nr
        fmt='<4h' if size==8 else '<bbBB'
        bounds=struct.unpack_from(fmt,sprite,start+i*size)
        records.append((parts[first:first+n],rect,bounds))
    return mods,loc,records,r,flags

def _farm_controls(old,android,chosen,appended=()):
    oldmods,_,frames,reader,flags=_frames(old)
    _,n,oldpal,oldblocks=midp_modules(geometry(old)[0],reader,flags)
    mods,loc,source,reader,_=_frames(android)
    pixel,mode,pages=reader.num('H'),reader.num('H'),reader.num('B')
    if pixel!=0x8808:raise ValueError('Unexpected farm control color model')
    colors=[]
    for _ in range(pages):
        variants,count=reader.num('B'),reader.num('B') or 256
        if variants!=1:raise ValueError('Unsupported farm control color variants')
        colors.append((count,reader.take(3*count)))
    sheets=[]
    for count,_ in colors:
        w,h=reader.num('H'),reader.num('H')
        sheets.append((w,indices(reader.take(reader.num('I')),mode,w*h,count)))
    modules=list(oldmods)
    banks=[0]*len(modules); blocks=list(oldblocks); added={}
    palettes=[(n,oldpal),*colors]
    if appended and len(frames)!=199: raise ValueError('Unknown pause atlas frame count')
    for i in (*chosen,*appended):
        parts,rect,bounds=source[i]
        revised=[]
        for src,x,y,pal,flip,extra in parts:
            if src not in added:
                kind,w,h,color,params=mods[src]
                j,u,v=loc[src];stride,tex=sheets[j];added[src]=len(modules)
                modules.append(mods[src]);banks.append(j+1)
                blocks.append(b''.join(tex[row*stride+u:row*stride+u+w] for row in range(v,v+h)) if not kind else b'')
            revised.append((added[src],x,y,pal,flip,extra))
        if i in appended: frames.append((revised,rect,bounds))
        else: frames[i]=(revised,rect,bounds)
    # Use separate source palettes so controls keep their exact original
    # colors while older frame IDs keep the palette they shipped with.
    out=bytearray(old[:3])+struct.pack('<IH',0x41118595,len(modules))
    for (kind,w,h,color,params),bank in zip(modules,banks):
        if kind not in (0,254) or params:raise ValueError('Unmapped HUD primitive')
        out.append(kind)
        out.extend(bytes([bank]) if kind==0 else struct.pack('<I',color))
        out.extend(struct.pack('<HH',w,h))
    out.extend(struct.pack('<H',sum(len(v[0]) for v in frames)))
    for parts,_,_ in frames:
        for m,x,y,pal,flip,extra in parts:
            if pal or extra:raise ValueError('Unmapped HUD module transform')
            out.extend(struct.pack('<HhhB',m,x,y,flip))
    out.extend(struct.pack('<H',sum(len(v[1]) for v in frames)))
    for _,rect,_ in frames:
        for r in rect:out.extend(struct.pack('<4h',*r))
    out.extend(struct.pack('<H',len(frames)));first=0
    for parts,rect,_ in frames:
        out.extend(struct.pack('<BHB',len(parts),first,len(rect)))
        first+=len(parts)
    for _,_,bounds in frames:out.extend(struct.pack('<4h',*bounds))
    out.extend(struct.pack('<HHHB',0,0,0x8808,len(palettes)))
    for count,rgb in palettes:
        out.extend(bytes([1,count%256])+rgb)
    out.extend(struct.pack('<H',0x5602))
    for block in blocks:out.extend(struct.pack('<I',len(block))+block)
    return bytes(out)

def farm_hud_panel(raw,android):
    from .expansion.visit_predators import _controls
    from .world import entries,pack
    dst=entries(raw);local=_controls(dst[1],False)
    by_id={struct.unpack_from('<H',b,1)[0]:b for b in _controls(entries(android)[1],True)}
    # Cash, coin/cash numerals, experience star, meter/title, journal.
    # MIDP's signed zoom controls have separate touch and gesture behavior.
    for index in (12,13,15,16,21,22,23,44):
        item=bytearray(local[index]);src=by_id[struct.unpack_from('<H',item,1)[0]]
        if src[0]!=item[0]:raise ValueError('Farm HUD ID changed control type')
        item[3:7]=src[3:7]
        local[index]=bytes(item)
    dst[1]=dst[1][:1]+b''.join(local)
    # The level-up screen clips the offline reward counters to control ID
    # 60. Android gives the reward area 300px starting at y=206.
    level=_controls(dst[12],False)
    promo={struct.unpack_from('<H',b,1)[0]:b for b in _controls(entries(android)[12],True)}
    card=bytearray(level[8]);origin=promo[60]
    if struct.unpack_from('<H',card,1)[0]!=60 or card[8:10]!=bytes([20,193]) or origin[8:11]!=bytes([20,75,0]):
        raise ValueError('Unknown level-up reward clip')
    card[3:7]=origin[3:7];card[9]=origin[9]
    level[8]=bytes(card);dst[12]=dst[12][:1]+b''.join(level)
    return pack(dst)
