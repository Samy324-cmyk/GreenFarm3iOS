"""Import the offline farm and local neighbors' original map records."""
from collections import Counter
from .world import entries, pack, table


def records(blob):
    if blob[:1] != b'\x02':
        raise ValueError('Expected a binary farm layout')
    pos = 1
    while pos < len(blob):
        opcode = blob[pos]
        # An actor has a final editor byte that both mobile readers skip.
        size = {50:13, 54:5, 250:10}[opcode]
        raw = blob[pos:pos+size]
        if len(raw) != size:
            raise ValueError('Truncated farm record')
        yield raw
        pos += size


def build_layout(mobile_map, apk, catalog):
    mobile = entries(mobile_map)
    android = entries(apk.read('assets/800x480/14'))
    sizes = [len(table(block)[1]) for block in catalog]
    # Type 49 has its own empty (-1) convention, type 42 is an NPC.
    table_for_type = {20:4,32:15,48:11,50:3,51:9,52:2,54:0,69:2}
    skipped = Counter()
    report = {}
    for i in range(3,15):
        source = list(records(android[i]))
        target = []
        for raw in source:
            if raw[0] == 50:
                kind, row = raw[8:10]
                key = table_for_type.get(kind)
                if key is not None and row >= sizes[key]:
                    skipped[(kind,row)] += 1
                    continue
                if key is None and kind not in {13,42,49}:
                    raise ValueError(f'Unsupported map actor type {kind}')
            target.append(raw)
        mobile[i] = b'\x02'+b''.join(target)
        report[i] = {'androidActors':sum(r[0]==50 for r in source),
                     'portedActors':sum(r[0]==50 for r in target)}
    # The opening cutscene changes the Y coordinate of two opcode-111
    # movements. Object identifiers, actions and timing are byte-identical.
    if mobile[16:] != android[16:] or len(mobile[15]) != len(android[15]):
        raise ValueError('Unknown offline cutscene format')
    differences = [i for i,(a,b) in enumerate(zip(mobile[15],android[15])) if a != b]
    if differences != [127,161] or any(android[15][i-3] != 111 for i in differences):
        raise ValueError('Unknown opening scene movement')
    mobile[15:] = android[15:]
    return pack(mobile), {'farmLayouts':report, 'pendingActorTypes':[
        {'type':k,'row':v,'count':n} for (k,v),n in sorted(skipped.items())]}
