"""Credit a collected request to the neighbor whose mailbox card was tapped."""
from .hives import patch_code
from tools.timing.classfile import ClassFile, u2


def patch_mailbox(data):
    game=ClassFile(data)
    def field(name,desc):
        key=game.intern(b'\x0c'+u2(game.utf(name))+u2(game.utf(desc)))
        return b'\xb2'+u2(game.intern(b'\x09'+u2(game.cls('a'))+u2(key)))
    offset=field('eM','I')
    # MIDP calls the same fly-out twice. Android w8 triggers it once,
    # then uses slot+offset for both the inventory and quest recipient.
    duplicate=(b'\x10\x0e\x1a\x10\x0b\x68\x60'+field('e','[[I')+
               b'\x1a'+offset+b'\x60\x32\x07\x2e\x03\xb8'+u2(game.ref('a','e','(IIZ)V')))
    patch_code(game,'aL','(I)V',[(68,duplicate,b'\x1a'+offset+b'\x60\x3c'),
                                 (112,field('eS','I'),b'\x1b')])
    return game.bytes()
