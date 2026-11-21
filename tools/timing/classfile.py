"""Read CLDC class files without renumbering their existing constant pool."""
import struct


def u2(n):
    return struct.pack(">H", n)


def u4(n):
    return struct.pack(">I", n)


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, count):
        value = self.data[self.pos:self.pos + count]
        if len(value) != count:
            raise ValueError("truncated class file")
        self.pos += count
        return value

    def u1(self):
        return self.take(1)[0]

    def u2(self):
        return int.from_bytes(self.take(2), "big")

    def u4(self):
        return int.from_bytes(self.take(4), "big")

    def attrs(self):
        return [(self.u2(), self.take(self.u4())) for _ in range(self.u2())]

    def members(self):
        return [(self.u2(), self.u2(), self.u2(), self.attrs()) for _ in range(self.u2())]


def attrs(entries):
    return u2(len(entries)) + b"".join(u2(i) + u4(len(b)) + b for i, b in entries)


def members(entries):
    return u2(len(entries)) + b"".join(u2(a) + u2(n) + u2(d) + attrs(x) for a, n, d, x in entries)


class ClassFile:
    def __init__(self, data):
        r = Reader(data)
        self.header = r.take(8)
        if self.header[:4] != bytes.fromhex("cafebabe"):
            raise ValueError("not a Java class")
        self.pool = [None]
        count = r.u2()
        while len(self.pool) < count:
            start = r.pos
            tag = r.u1()
            if tag == 1:
                r.take(r.u2())
            else:
                r.take({3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4}[tag])
            self.pool.append(data[start:r.pos])
            if tag in (5, 6):
                self.pool.append(None)
        start = r.pos
        r.take(6)
        r.take(2 * r.u2())
        self.declaration = data[start:r.pos]
        self.fields = r.members()
        self.methods = r.members()
        self.attributes = r.attrs()
        if r.pos != len(data):
            raise ValueError("unexpected trailing class bytes")

    def intern(self, entry):
        try:
            return self.pool.index(entry)
        except ValueError:
            self.pool.append(entry)
            return len(self.pool) - 1

    def string(self, i):
        return self.pool[i][3:].decode("utf8", "replace")

    def utf(self, value):
        b = value.encode("utf8")
        return self.intern(b"\x01" + u2(len(b)) + b)

    def cls(self, value):
        return self.intern(b"\x07" + u2(self.utf(value)))

    def ref(self, owner, name, desc):
        cls = self.cls(owner)
        typ = self.intern(b"\x0c" + u2(self.utf(name)) + u2(self.utf(desc)))
        return self.intern(b"\x0a" + u2(cls) + u2(typ))

    def bytes(self):
        return self.header + u2(len(self.pool)) + b"".join(x for x in self.pool if x) + self.declaration + members(self.fields) + members(self.methods) + attrs(self.attributes)


def instruction_offsets(code):
    p = 0
    while p < len(code):
        yield p
        op = code[p]
        if op == 0xaa or op == 0xab:
            q = (p + 4) & ~3
            if op == 0xaa:
                low, high = struct.unpack_from(">ii", code, q + 4)
                p = q + 12 + 4 * (high - low + 1)
            else:
                p = q + 8 + 8 * struct.unpack_from(">i", code, q + 4)[0]
        elif op == 0xc4:
            p += 6 if code[p+1] == 0x84 else 4
        elif op in (0xb9, 0xba, 0xc8, 0xc9):
            p += 5
        elif op == 0xc5:
            p += 4
        elif op in (0x11, 0x13, 0x14, 0x84, 0xbb, 0xbd, 0xc0, 0xc1, 0xc6, 0xc7) or 0x99 <= op <= 0xa8 or 0xb2 <= op <= 0xb8:
            p += 3
        elif op in (0x10, 0x12, 0xa9, 0xbc) or 0x15 <= op <= 0x19 or 0x36 <= op <= 0x3a:
            p += 2
        else:
            p += 1
    if p != len(code):
        raise ValueError("invalid instruction boundary")


def code_parts(data):
    r = Reader(data)
    header = r.take(4)
    instructions = r.take(r.u4())
    n = r.u2()
    exceptions = u2(n) + r.take(n * 8)
    extra = r.attrs()
    return header, instructions, exceptions, extra


def pack_code(header, code, exceptions, extra):
    return header + u4(len(code)) + code + exceptions + attrs(extra)


def cldc_frames(cf, flags, name, desc, table):
    """Expand JVMS StackMapTable deltas into CLDC StackMap full frames."""
    locals_ = []
    if not flags & 8:
        locals_.append(b"\x06" if name == "<init>" else b"\x07" + cf.declaration[2:4])
    p = 1
    while desc[p] != ")":
        s = p
        while desc[p] == "[":
            p += 1
        tag = desc[p]
        p = desc.index(";", p) + 1 if tag == "L" else p + 1
        arg = desc[s:p]
        if arg[0] in "[L":
            locals_.append(b"\x07" + u2(cf.cls(arg[1:-1] if arg[0] == "L" else arg)))
        else:
            locals_.append(bytes([{"J": 4, "D": 3, "F": 2}.get(tag, 1)]))
    r = Reader(table)
    def value():
        tag = r.u1()
        return bytes([tag]) + (r.take(2) if tag in (7, 8) else b"")
    n = r.u2()
    result, pc = bytearray(u2(n)), -1
    for _ in range(n):
        mode = r.u1()
        stack = []
        if mode <= 63:
            delta = mode
        elif mode <= 127:
            delta, stack = mode - 64, [value()]
        elif mode == 247:
            delta, stack = r.u2(), [value()]
        elif 248 <= mode <= 250:
            delta = r.u2()
            del locals_[-(251-mode):]
        elif 251 <= mode <= 254:
            delta = r.u2()
            locals_.extend(value() for _ in range(mode-251))
        elif mode == 255:
            delta = r.u2()
            locals_ = [value() for _ in range(r.u2())]
            stack = [value() for _ in range(r.u2())]
        else:
            raise ValueError("invalid frame type")
        pc += delta + 1
        result.extend(u2(pc) + u2(len(locals_)) + b"".join(locals_) + u2(len(stack)) + b"".join(stack))
    if r.pos != len(table):
        raise ValueError("unconsumed stack map bytes")
    return bytes(result)


def convert_helper(data):
    cf = ClassFile(data)
    cf.header = cf.header[:4] + u2(3) + u2(45)
    # javac --release 8 emits StringBuilder for source string concatenation.
    # CLDC 1.1 provides the same append operations on StringBuffer. Rewrite
    # both the owning class and method descriptors before constructing frames.
    for i, entry in enumerate(cf.pool):
        if entry and entry[0]==1 and b'java/lang/StringBuilder' in entry[3:]:
            value=entry[3:].replace(b'java/lang/StringBuilder', b'java/lang/StringBuffer')
            cf.pool[i]=b'\x01'+u2(len(value))+value
    for flags, name, desc, attributes in cf.methods:
        for i, (attribute, body) in enumerate(attributes):
            if cf.string(attribute) != "Code":
                continue
            header, code, exceptions, extra = code_parts(body)
            extra = [(cf.utf("StackMap"), cldc_frames(cf, flags, cf.string(name), cf.string(desc), data)) if cf.string(k) == "StackMapTable" else (k, data) for k, data in extra]
            attributes[i] = attribute, pack_code(header, code, exceptions, extra)
    return cf.bytes()
