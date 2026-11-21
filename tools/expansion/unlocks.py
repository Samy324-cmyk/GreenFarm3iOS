"""Convert the APK level-up cards and integer economy parameters to MIDP."""
from tools.catalog_ext import encode_table
from tools.timing.classfile import ClassFile,pack_code,u2
from tools.world import table
from .hives import patch_code


def build_unlocks(mobile, android):
    old, source = table(mobile[10])[1], table(android[10])[1]
    if (len(old),len(source)) != (271,297):
        raise ValueError('Unknown level-up catalog')
    rows = []
    for i, row in enumerate(source):
        if row[0] != i or (i < len(old) and old[i][:2] != row[:2]):
            raise ValueError('Level-up item mismatch')
        if i < len(old) and i != 264:
            # The earlier engine reorders the common recipe icon sheets and
            # uses chicken frame 67 for the same thumbnail as Android frame 35.
            rows.append((*row[:3],*old[i][3:]))
        else:
            rows.append(row)
    mobile[10] = encode_table(mobile[10],rows)
    old, source = table(mobile[20])[1], table(android[20])[1]
    if len(old)!=30 or len(source)!=36 or [r[0] for r in source]!=list(range(36)):
        raise ValueError('Unknown economy configuration')
    # The Android package has a single economy. Its upper bounds need
    # signed 32-bit values in both regional columns of the old engine.
    mobile[20] = encode_table(mobile[20],[(i,v,v) for i,v in source])
    prices = table(android[31])[1]
    if (len(prices)!=34 or any(row[:2]!=(i,19000+i) for i,row in enumerate(prices))
            or [r[2] for r in prices[:7]]!=[r[2] for r in prices[7:14]]
            or [r[2] for r in prices[14:24]]!=[r[2] for r in prices[24:]]):
        raise ValueError('Different expansion price tiers for the mill and the kitchen')
    mobile[31]=encode_table(mobile[31],[row[:3] for row in prices])


def patch_unlocks(data):
    engine=ClassFile(data)
    # Slots 127–137 were outside the reference UI pack. gD() used to skip
    # loading them when scrolling between pages of newly unlocked recipes.
    patch_code(engine,'gD','()V',[(95,bytes.fromhex('1b107fa1000a1b110089a40008'),b'')])
    patch_code(engine,'q','(Z)V',[(p,b'\x10\x0e',b'\x10\x22') for p in (1281,1291)])
    restore_card_art(engine)
    return engine.bytes()


def restore_card_art(engine):
    # Entering level 3 directly from the mill can leave a disposed portrait
    # in the UI cache. Open its own pack and construct both the head and
    # the body before the normal unlock list and hit rectangles are built.
    def call(owner,name,desc):
        return b'\xb8'+u2(engine.ref(owner,name,desc))
    field=engine.intern(b'\x09'+u2(engine.cls('a'))+u2(engine.intern(
        b'\x0c'+u2(engine.utf('a'))+u2(engine.utf('[Le;')))))
    pack=engine.intern(b'\x08'+u2(engine.utf('/7')))
    original=call('a','gD','()V')
    code=b'\x13'+u2(pack)+call('g','c','(Ljava/lang/String;)V')
    for slot in (7,21):
        load=b'\x10'+bytes([slot])
        # a.loadSprite(slot, paletteMask=1, prepareImages=true, discard=false, 0, -1)
        code+=b'\xb2'+u2(field)+load+load+b'\x04\x04\x03\x03\x02'+call('a','a','(IIZZII)Le;')+b'\x53'
    code+=call('g','l','()V')+original+b'\xb1'
    engine.methods.append((10,engine.utf('gf3LevelArt'),engine.utf('()V'),
        [(engine.utf('Code'),pack_code(u2(8)+u2(0),code,u2(0),[]))]))
    patch_code(engine,'y','(I)Z',[(444,original,call('a','gf3LevelArt','()V'))])
