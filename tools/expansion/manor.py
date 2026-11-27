"""Keep a completed campaign's journal accessible until all rewards are collected."""
from .hives import patch_code
from tools.timing.classfile import ClassFile, code_parts, pack_code, u2


def patch_manor(game_bytes):
    game = ClassFile(game_bytes)
    all_complete = b'\xb8' + u2(game.ref('a', 'v', '()Z'))
    active_count = b'\xb8' + u2(game.ref('a', 'F', '()I'))
    # a.v() means all the mission flags have been set. a.F() also counts those
    # still in the journal waiting for the player to accept the reward.
    # return allComplete() && activeCount() == 0;
    name = 'gf3JournalFinished'
    code = all_complete + bytes.fromhex('99000b') + active_count + bytes.fromhex('9a000504ac03ac')
    frame = u2(1) + u2(14) + u2(0) + u2(0)
    body = pack_code(u2(1) + u2(0), code, u2(0), [(game.utf('StackMap'),frame)])
    # Only change the farm HUD condition that hides the journal icon. The
    # award callback still uses the original test to show the ending dialog.
    pattern = all_complete + bytes.fromhex('99001104102c03')
    matches = []
    for _, method, descriptor, attributes in game.methods:
        if game.string(descriptor) == '(I)Z':
            for key, attr in attributes:
                if game.string(key) == 'Code':
                    raw = code_parts(attr)[1]
                    if pattern in raw:
                        matches.append((game.string(method),raw.index(pattern)))
    if len(matches) != 1:
        raise ValueError('Missing the unique native journal visibility check')
    method, offset = matches[0]
    patch_code(game,method,'(I)Z',[(offset,all_complete,b'\xb8'+u2(game.ref('a',name,'()Z')))])
    game.methods.append((0x000a,game.utf(name),game.utf('()Z'),[(game.utf('Code'),body)]))
    return game.bytes()
