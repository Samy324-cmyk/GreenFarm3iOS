"""Render continuously zoomed terrain with the original map and full-size /9 atlas."""
import struct
from .expansion.hives import patch_code
from .expansion.neighbor import expose
from .sprites import convert_sprite, geometry, midp_modules, shards
from .timing.classfile import pack_code, u2


def wrap(cf, name, desc, original, helper, args, stack, locals_, ret):
    for i, (flags, n, d, attrs) in enumerate(cf.methods):
        if (cf.string(n), cf.string(d)) == (name, desc):
            cf.methods[i] = flags & ~2, cf.utf(original), d, attrs
            code = bytes.fromhex(args) + b'\xb8' + u2(cf.ref('GF3Fractional', helper, desc)) + bytes([ret])
            cf.methods.append((flags, n, d, [(cf.utf('Code'), pack_code(u2(stack)+u2(locals_), code, u2(0), []))]))
            return
    raise ValueError('Missing tile renderer '+name+desc)


def patch_fractional(game, actor, tiles, apk):
    wrap(actor, 'e', '(I)V', 'changeZoom', 'zoom', '1a', 1, 1, 177)
    wrap(game, 'g', '(I)Z', 'zoomPreScaled', 'prescaled', '1a', 1, 1, 172)
    wrap(game, 'a', '()V', 'loadZoomMap', 'loadMap', '', 0, 0, 177)
    wrap(tiles, 'a', '(Ljavax/microedition/lcdui/Graphics;IIIIIIIZ)V', 'drawTiles', 'tiles',
         '2a1b1c1d15041505150615071508', 9, 9, 177)
    expose(tiles, tiles.fields, {('a','[[I'), ('a','[[[B')})
    expose(game, game.fields, {('c','Lf;')})
    # Dirty rectangles follow the physical circular-cache block grid (72x36 for
    # the intermediate scales), independently of the displayed size of a cell.
    patch_code(actor,'h','(II)V',[(p,bytes.fromhex('11009e'),b'\xb8'+u2(actor.ref('GF3Fractional','tileSheet','()I')))
                                  for p in (162,178)])
    # Purchased acres edit unscaled source tiles. The native 50% fast path
    # halves both coordinates and tile dimensions before indexing its map.
    patch_code(game,'o','(Z)V',[(p,bytes.fromhex('b200d5'),b'\xb8'+u2(game.ref('GF3Fractional','mapZoom','()I')))
                               for p in (252,290)])
    # Multiply before dividing when converting the center for quest rewards.
    patch_code(game,'ax','()V',[(p,bytes.fromhex('1064b200d56c68'),bytes.fromhex('106468b200d56c'))
                                for p in (50,59)])
    path='assets/800x480/9'
    source=convert_sprite(shards(apk,path)[path][0])
    shape,_,reader,flags,_=geometry(source)
    _,colors,palette,blocks=midp_modules(shape, reader, flags)
    if len(blocks)!=48 or any(len(b)!=72*36 for b in blocks):
        raise ValueError('Original Android ground module dimensions changed')
    rgb=b''.join(palette[i:i+3][::-1] for i in range(0,colors*3,3))
    return struct.pack('>H',colors)+rgb+b''.join(blocks)
