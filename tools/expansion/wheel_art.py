"""Render specific original Android ASprite frames to independent MIDP PNGs.

The wheel panel uses multi-page textures and per-pixel alpha. Direct PNGs
avoid the shared native sprite/animation cache, including the shop price sheet.
"""
import struct
import zlib
from tools.sprites import geometry, indices, shards

def png(w,h,rgba):
    def chunk(name,data):
        return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data)&0xffffffff)
    scan=b''.join(b'\0'+rgba[y*w*4:(y+1)*w*4] for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b'')

def rgba_frame(blob,frame):
    shape,locations,r,flags,extra=geometry(blob)
    pixel,mode,pages=r.num('H'),r.num('H'),r.num('B')
    if pixel not in (0x8808,0x8888):raise ValueError('Unexpected wheel palette')
    palettes=[]
    for _ in range(pages):
        variants,colors=r.num('B'),r.num('B') or 256
        stride=4 if pixel==0x8888 else 3
        raw=r.take(variants*colors*stride)
        palettes.append((colors,[tuple(raw[i:i+3][::-1]) for i in range(0,colors*stride,stride)]))
    atlases=[]
    for n,pal in palettes:
        w,h=r.num('H'),r.num('H');raw=r.take(r.num('I'))
        if pixel==0x8888:
            if mode!=0xa562 or len(raw)!=2*w*h:raise ValueError('Unknown alpha atlas')
            ix,alpha=raw[1::2],raw[::2]
        else:
            ix=indices(raw,mode,w*h,n);alpha=None
        atlases.append((w,h,pal,ix,alpha))
    count,first,_=shape[3][frame]
    parts=[]
    for m,x,y,pal,transform,custom in shape[1][first:first+count]:
        kind,w,h,color,params=shape[0][m]
        if pal or custom:raise ValueError('Unexpected original wheel palette transform')
        if kind==254:
            # APK panel 45 contains solid ARGB rectangles, including rotated
            # border segments. They have no texture coordinates.
            if transform&~7:raise ValueError('Unexpected rectangle transform')
            if transform&4:w,h=h,w
            rgba=bytes(((color>>16)&255,(color>>8)&255,color&255,(color>>24)&255))
            parts.append((x,y,w,h,rgba*(w*h)))
            continue
        if kind!=0 or transform&~3:raise ValueError('Unexpected original wheel frame transform')
        page,u,v=locations[m]
        aw,ah,colors,ix,alpha=atlases[page]
        if u+w>aw or v+h>ah:raise ValueError('Frame outside APK atlas')
        pixels=bytearray(w*h*4)
        for yy in range(h):
            for xx in range(w):
                index=(v+(h-1-yy if transform&2 else yy))*aw+u+(w-1-xx if transform&1 else xx)
                rgb=colors[ix[index]]
                a=alpha[index] if alpha is not None else (0 if rgb==(255,0,255) else 255)
                pos=(yy*w+xx)*4
                pixels[pos:pos+4]=bytes((*rgb,a))
        parts.append((x,y,w,h,pixels))
    return parts

def blit(dst,w,h,parts,x=0,y=0):
    for ox,oy,pw,ph,rgba in parts:
        for yy in range(ph):
            dy=y+oy+yy
            if not 0<=dy<h:continue
            for xx in range(pw):
                dx=x+ox+xx
                if not 0<=dx<w:continue
                si=(yy*pw+xx)*4;di=(dy*w+dx)*4
                a=rgba[si+3]
                if a==255:dst[di:di+4]=rgba[si:si+4]
                elif a:
                    old=dst[di+3];out=a+old*(255-a)//255
                    for k in range(3):dst[di+k]=(rgba[si+k]*a+dst[di+k]*old*(255-a)//255)//out
                    dst[di+3]=out

def portrait(w,h,pixels):
    result=bytearray(w*h*4)
    for y in range(h):
        for x in range(w):
            i=(y*w+x)*4;j=(x*h+h-1-y)*4
            result[j:j+4]=pixels[i:i+4]
    return png(h,w,result)

def single(parts,scale=1):
    left=min(p[0] for p in parts);top=min(p[1] for p in parts)
    w=max(x+a for x,y,a,b,p in parts)-left
    h=max(y+b for x,y,a,b,p in parts)-top
    data=bytearray(w*h*4);blit(data,w,h,parts,-left,-top)
    if scale!=1:
        data=bytearray(b''.join(bytes(data[(y*w+x)*4:(y*w+x)*4+4])*scale for y in range(h) for _ in range(scale) for x in range(w)))
    return portrait(w*scale,h*scale,data)

def shop_bill(apk):
    source=[b for group in shards(apk,'assets/800x480/11').values() for b in group]
    return single(rgba_frame(source[38],0))

def offer_clock(apk):
    source=[b for group in shards(apk,'assets/800x480/11').values() for b in group]
    return single(rgba_frame(source[48],14))

def stretched(parts,width,height):
    """Expand the original 1px fill strips to the next module origin.
    The Android ASprite renderer does this at runtime for frame 166,198,12,13,167.
    """
    result=[]
    for x,y,w,h,pixels in parts:
        ww,hh=w,h
        if w==1:
            stops=[xx for xx,yy,aw,ah,_ in parts if xx>x and yy<y+h and yy+ah>y]
            ww=(min(stops) if stops else width)-x
        if h==1:
            stops=[yy for xx,yy,aw,ah,_ in parts if yy>y and xx<x+max(ww,1) and xx+aw>x]
            hh=(min(stops) if stops else height)-y
        if ww<=0 or hh<=0:raise ValueError('Invalid original fill bounds')
        if (ww,hh)!=(w,h):
            pixels=bytes().join(pixels[(min(yy,h-1)*w+min(xx,w-1))*4:(min(yy,h-1)*w+min(xx,w-1))*4+4] for yy in range(hh) for xx in range(ww))
        result.append((x,y,ww,hh,pixels))
    return result

def cash_shop_images(apk):
    source=[b for group in shards(apk,'assets/800x480/11').values() for b in group]
    images={}
    card=stretched(rgba_frame(source[20],166),164,150)
    green=stretched(rgba_frame(source[20],198),154,47)
    # A single-pixel center fills the rectangle, not just its corners.
    assert sum(w*h for x,y,w,h,_ in card)>=164*149
    assert sum(w*h for x,y,w,h,_ in green)>=154*46
    for cash in (True,False):
        canvas=bytearray(bytes((245,227,188,255))*(800*480))
        for sheet,frame,x,y in [(22,2,0,-17),(22,0,2,97),(20,12,359,50),(20,120,312,39),(20,13,568,50),(20,121,534,36)]:
            parts=rgba_frame(source[sheet],frame)
            if sheet==20 and frame in (12,13):
                parts=stretched(parts,169 if frame==12 else 126,42)
            blit(canvas,800,480,parts,x,y)
        # Side selector uses the original card and green button resources.
        for tab in range(2):
            x,y=32,112+164*tab
            blit(canvas,800,480,card,x,y)
            icon=rgba_frame(source[37 if tab==0 else 38],3 if tab==0 else 4)
            left=min(q[0] for q in icon);top=min(q[1] for q in icon)
            right=max(q[0]+q[2] for q in icon);bottom=max(q[1]+q[3] for q in icon)
            blit(canvas,800,480,icon,x+82-(right+left)//2,y+64-(bottom+top)//2)
            blit(canvas,800,480,green,x+5,y+103)
        for i,(x,y,ax,ay,bx,by) in enumerate([(213,110,293,179,218,204),(395,110,473,181,400,204),(577,110,660,178,582,204),
                                            (214,273,292,342,219,367),(397,273,478,341,402,367),(577,273,658,340,582,367)]):
            blit(canvas,800,480,card,x,y)
            blit(canvas,800,480,rgba_frame(source[38 if cash else 37],i),ax,ay)
            blit(canvas,800,480,green,bx,by)
            # Original currency art makes the price unit clear without text clipping.
            icon=rgba_frame(source[41],0 if cash else 1)
            # Reduce the original prize icon to fit the 47px native button.
            small=[]
            for ox,oy,iw,ih,rgba in icon:
                sw,sh=max(1,iw*2//3),max(1,ih*2//3)
                small.append((ox*2//3,oy*2//3,sw,sh,bytes().join(rgba[((yy*ih//sh)*iw+xx*iw//sw)*4:((yy*ih//sh)*iw+xx*iw//sw)*4+4] for yy in range(sh) for xx in range(sw))))
            blit(canvas,800,480,small,bx+10,by+10)
        blit(canvas,800,480,rgba_frame(source[33],0),0,0)
        blit(canvas,800,480,rgba_frame(source[20],122),715,10)
        images['gf3-cash-shop.png' if cash else 'gf3-coin-shop.png']=portrait(800,480,canvas)
    return images

def wheel_images(apk):
    source=[b for group in shards(apk,'assets/800x480/11').values() for b in group]
    # APK panel 45: original background, decorative border, close control.
    canvas=bytearray(bytes((245,227,188,255))*(800*480))
    for sheet,frame,x,y in [(22,2,8,2),(22,0,2,115),(33,0,-2,0),(20,122,716,9)]:
        blit(canvas,800,480,rgba_frame(source[sheet],frame),x,y)
    # Original gold button halves, without the embedded advertisement icon.
    blit(canvas,800,480,rgba_frame(source[41],18)[:2],374,224)
    blit(canvas,800,480,rgba_frame(source[41],1),394,230)
    rim=rgba_frame(source[41],34)
    # Keep the original one-pixel origin; its center is at (157,182).
    data=bytearray(316*412*4);blit(data,316,412,rim)
    return {'gf3-wheel-bg.png':portrait(800,480,canvas),
            'gf3-wheel-rim.png':portrait(316,412,data),
            'gf3-wheel-coin.png':single(rgba_frame(source[41],0)),
            'gf3-wheel-bill.png':single(rgba_frame(source[41],1))}
