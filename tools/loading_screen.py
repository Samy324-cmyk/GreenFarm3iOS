"""Recover the native offline loading screen and its copyright caption from the Android panel."""
import struct
import zlib
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from .expansion.hives import patch_code
from .expansion.neighbor import expose
from .expansion.visit_predators import _controls
from .sprites import geometry,indices,shards
from .timing.classfile import ClassFile, code_parts, instruction_offsets, convert_helper, u2
from .world import entries, labels, pack


def font_map(raw):
    words=struct.unpack_from('<%dH'%((len(raw)-4)//2),raw,4)
    count=words[0];end=1+2*count
    mapping=dict(zip(words[1:end:2],words[2:end:2]))
    while end<len(words):
        _,count=words[end:end+2];start=end+2;end=start+2*count
        mapping.update(zip(words[start:end:2],words[start+1:end:2]))
    return mapping


def glyphs(font,frame_ids):
    shape,locations,r,_,_=geometry(font)
    pixel,mode,pages=r.num('H'),r.num('H'),r.num('B')
    variants,count=r.num('B'),r.num('B') or 256
    if (pixel,pages,variants)!=(0x8888,1,1):raise ValueError('Unexpected caption texture')
    alpha=r.take(count*4)[3::4]
    width,height=r.num('H'),r.num('H')
    tex=indices(r.take(r.num('I')),mode,width*height,count)
    cursor=0;pieces=[]
    for frame in frame_ids:
        length,first,_=shape[3][frame]
        parts=shape[1][first:first+length]
        for module,x,y,palette,flags,extra in parts[1:]:
            kind,w,h,_,_=shape[0][module]
            page,u,v=locations[module]
            if kind or page or palette or flags or extra:raise ValueError('Unexpected glyph transform')
            data=bytes(alpha[tex[(v+j)*width+u+i]] for j in range(h) for i in range(w))
            pieces.append((cursor+x,y,w,h,data))
        cursor+=parts[0][1]
    return cursor,pieces


def caption(fonts,mapping,text):
    # Frame 1 is the Android font's space advance and has no ink.
    frames=[1 if c==' ' else mapping[ord(c)] for c in text]
    advance,outline=glyphs(fonts[3],frames);width,fill=glyphs(fonts[2],frames)
    if advance!=width:raise ValueError('Outline spacing differs from fill')
    pieces=outline+fill
    left=min(x for x,y,w,h,a in pieces);top=min(y for x,y,w,h,a in pieces)
    w=max(x+pw for x,y,pw,ph,a in pieces)-left
    h=max(y+ph for x,y,pw,ph,a in pieces)-top
    rgba=bytearray(4*w*h)
    for rgb,parts in [((232,84,0),outline),((255,255,255),fill)]:
        for x,y,pw,ph,alpha in parts:
            for j in range(ph):
                for i in range(pw):
                    a=alpha[j*pw+i]
                    if not a:continue
                    pos=4*((j+y-top)*w+i+x-left)
                    b=rgba[pos+3]*(255-a);out=a*255+b
                    for k,color in enumerate(rgb):
                        rgba[pos+k]=(color*a*255+rgba[pos+k]*b+out//2)//out
                    rgba[pos+3]=(out+127)//255
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    scan=b''.join(b'\0'+rgba[j*w*4:(j+1)*w*4] for j in range(h))
    png=(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))
         +chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b''))
    return png,(advance,left,top)


def restore_loading_screen(classes, apk, api):
    panels = entries(classes['6'])
    local = _controls(panels[0], False)
    source = _controls(entries(apk.read('assets/800x480/10'))[0], True)
    ids = [1,17,4,5,3,7,18]
    def control_ids(rows):
        return [struct.unpack_from('<H', row, 1)[0] for row in rows]
    if control_ids(local) != ids[:-1] or control_ids(source) != ids:
        raise ValueError('Unrecognized loading panel')
    for i, target in enumerate(local):
        local[i] = target[:3] + source[i][3:7] + target[7:]
    # Title/copyright share one font and centering mode in the source.
    # MIDP numbers its fonts differently and omits the penultimate text flag.
    if source[4][7] != source[6][7] or source[4][12:24] != source[6][12:24]:
        raise ValueError('Unrecognized loading caption style')
    copyright_row = bytearray(source[6][:-2] + source[6][-1:])
    copyright_row[7] = local[4][7]
    local.append(copyright_row)
    panels[0] = panels[0][:1] + b''.join(local)

    game = ClassFile(classes['a.class'])
    expose(game,game.fields,{('a','[[Ljava/lang/String;'),('a','[[[S')})
    expose(game,game.methods,{('F','(I)V')})
    draw = b'\xb8' + u2(game.ref('a', 'F', '(I)V'))
    target = b'\x03' + draw
    sites = []
    for _, name, desc, attrs in game.methods:
        if game.string(desc) == '(II)Z':
            for tag, value in attrs:
                if game.string(tag) != 'Code':
                    continue
                code = code_parts(value)[1]
                for pc in instruction_offsets(code):
                    if code[pc:pc+4] == target:
                        sites.append((game.string(name), pc+1))
    if len(sites) != 1:
        raise ValueError('Expected one loading panel paint in the native state machine')
    method, pc = sites[0]
    patch_code(game,method,'(II)Z',[(pc,draw,b'\xb8'+u2(game.ref('GF3Loading','draw','(I)V')))])
    words=labels(apk.read('assets/800x480/LATAM'))
    fonts=[b for block in shards(apk,'assets/800x480/2').values() for b in block]
    mapping=font_map(fonts[-1])
    result={'6':pack(panels),'a.class':game.bytes()}
    for name,idx in [('cargando',46),('copyright',12509)]:
        bitmap,placement=caption(fonts,mapping,words[idx])
        expected=129 if idx==46 else 216
        if placement!=(expected,0,-22):raise ValueError('Unexpected original caption baseline')
        result[name+'.png']=bitmap
    with TemporaryDirectory() as scratch:
        root=Path(scratch);stub=root/'a.java'
        stub.write_text('''class a {static String[][] captions;static short[][][] controls;static void F(int p){}}
            class g {static javax.microedition.lcdui.Graphics screen;}''',encoding='ascii')
        src=Path(__file__).resolve().parents[1]/'src/catalog/GF3Loading.java'
        subprocess.run(['javac','--release','8','-cp',str(api),'-g:none','-d',str(root),str(stub),str(src)],check=True)
        helper=ClassFile((root/'GF3Loading.class').read_bytes())
        for name in ('captions','controls','screen'):helper.pool[helper.utf(name)]=helper.pool[helper.utf('a')]
        result['GF3Loading.class']=convert_helper(helper.bytes())
    return result
