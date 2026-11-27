"""Install the presentation layer into the verified Green Farm 3 touch engine."""
import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile
from classfile import ClassFile, code_parts, convert_helper, instruction_offsets, pack_code, u2

HERE = Path(__file__).resolve().parent
GRAPHICS = "javax/microedition/lcdui/Graphics"
SIGNATURE = "(Ljavax/microedition/lcdui/Graphics;)V"
DRAW = {"drawImage", "drawRegion", "drawRGB", "drawString", "fillRect", "drawRect", "drawArc", "fillArc", "drawLine", "fillTriangle"}


def patch(data, entry):
    cf = ClassFile(data)
    refs = {}
    scene_refs = {}
    for i, ref in enumerate(cf.pool[:]):
        if not ref or ref[0] != 10:
            continue
        c, t = struct.unpack(">HH", ref[1:])
        owner = cf.string(int.from_bytes(cf.pool[c][1:], "big"))
        k, d = struct.unpack(">HH", cf.pool[t][1:])
        name, desc = cf.string(k), cf.string(d)
        if owner == "javax/microedition/lcdui/Image" and name == "getGraphics" and desc == "()Ljavax/microedition/lcdui/Graphics;":
            refs[i] = cf.ref("GF3Draw", "getGraphics", "(Ljavax/microedition/lcdui/Image;)Ljavax/microedition/lcdui/Graphics;")
        if owner == GRAPHICS and name in DRAW:
            refs[i] = cf.ref("GF3Draw", name, "(L" + GRAPHICS + ";" + desc[1:])
        if entry=="f.class" and (owner,name,desc)==("k","a","(L"+GRAPHICS+";III)V"):
            scene_refs[i]=cf.ref("GF3Draw","terrain",desc)
        if entry=="a.class" and (owner,name,desc)==("f","b","()V"):
            scene_refs[i]=cf.ref("GF3Draw","world",desc)
    changed = False
    recognized = set()
    if entry=="k.class":
        fields={("a","[[I"),("p","[I")}
        for index,(flags,name,desc,attributes) in enumerate(cf.fields):
            field=cf.string(name),cf.string(desc)
            if field in fields:
                cf.fields[index]=flags&~2,name,desc,attributes
                fields.remove(field)
                changed=True
        if fields: raise ValueError("Missing native terrain extent fields")
    pointers = []
    for n, (flags, k, d, attrs) in enumerate(cf.methods):
        name, desc = cf.string(k), cf.string(d)
        if entry=="a.class" and name in ("pointerPressed","pointerReleased","pointerDragged") and desc=="(II)V":
            phase=("pointerPressed","pointerReleased","pointerDragged").index(name)
            alias="gf3"+name[0].upper()+name[1:]
            cf.methods[n]=flags,cf.utf(alias),d,attrs
            code=b"\x2a\x1b\x1c"+bytes([3+phase])+b"\xb8"+u2(cf.ref("GF3Viewport","pointer","(La;III)V"))+b"\xb1"
            pointers.append((flags,k,d,[(cf.utf("Code"),pack_code(u2(4)+u2(3),code,u2(0),[]))]))
            changed=True
        if entry == "g.class" and name == "paint" and desc == SIGNATURE:
            cf.methods[n] = flags, cf.utf("gf3OriginalPaint"), d, attrs
            recognized.add("paint")
        for i, (attribute, body) in enumerate(attrs):
            if cf.string(attribute) != "Code":
                continue
            header, ins, exceptions, extra = code_parts(body)
            code = bytearray(ins)
            for pc in instruction_offsets(ins):
                if entry=='f.class' and ins[pc]==0xb8:
                    ref=int.from_bytes(ins[pc+1:pc+3],'big')
                    if ref==cf.ref('a','c','(I)V'):
                        if (name,desc) in {('B','()V'),('a','(I)Lf;')} and pc in (7,40):
                            code[pc+1:pc+3]=u2(cf.ref('GF3FarmAudio','wildlife','(I)V'));changed=True
                        elif pc>=2 and ins[pc-2:pc]==b'\x10\x24':
                            code[pc+1:pc+3]=u2(cf.ref('GF3FarmAudio','feeding','(I)V'));changed=True
                if ins[pc]==0xb8:
                    ref=int.from_bytes(ins[pc+1:pc+3],"big")
                    if ref in scene_refs and (entry!="f.class" or (name,desc)==("b","()V")):
                        code[pc+1:pc+3]=u2(scene_refs[ref])
                        changed=True
                        recognized.add("world" if entry=="a.class" else "terrain")
                if ins[pc] == 0xb6:
                    target = int.from_bytes(ins[pc+1:pc+3], "big")
                    if target in refs:
                        code[pc:pc+3] = b"\xb8" + u2(refs[target])
                        changed = True
            if entry == "g.class" and name == "run" and desc == "()V":
                if hashlib.sha256(ins).hexdigest() != RUN_SHA:
                    raise ValueError("unsupported reference game loop")
                code[23:26] = b"\xb8" + u2(cf.ref("GF3Presentation", "requestNative", "(Lg;)V"))
                code[89:92] = b"\xb8" + u2(cf.ref("GF3Presentation", "waitForTick", "(J)V"))
                recognized.add("run")
            attrs[i] = attribute, pack_code(header, code, exceptions, extra)
    if entry == "g.class":
        if recognized != {"run", "paint"}:
            raise ValueError("unsupported Canvas")
        code = bytes.fromhex("2a2bb8") + u2(cf.ref("GF3Presentation", "paint", "(Lg;L" + GRAPHICS + ";)V")) + b"\xb1"
        cf.methods.append((1, cf.utf("paint"), cf.utf(SIGNATURE), [(cf.utf("Code"), pack_code(u2(2)+u2(2),code,u2(0),[]))]))
        changed = True
    if entry=="a.class":
        def field(name,desc):
            typ=cf.intern(b'\x0c'+u2(cf.utf(name))+u2(cf.utf(desc)))
            return u2(cf.intern(b'\x09'+u2(cf.cls('a'))+u2(typ)))
        # Emit short branches against explicit labels rather than hand
        # calculating bytecode offsets. Never serialize a neighbor or tutorial.
        code=bytearray()
        labels={}
        branches=[]
        def emit(data):code.extend(data)
        def mark(label):labels[label]=len(code)
        def branch(op,label):
            branches.append((len(code),label));emit(bytes([op,0,0]))
        emit(b'\xb2'+field('F','I'));branch(0x9a,'no')
        for name in ('d','C'):
            emit(b'\xb2'+field(name,'I')+b'\x02');branch(0xa0,'no')
        emit(b'\xb2'+field('a','I')+b'\x3b')
        mark('loop');emit(b'\x1a');branch(0x9b,'no')
        emit(b'\xb2'+field('a','[I')+b'\x1a\x2e\x10\x11');branch(0x9f,'yes')
        emit(b'\x84\x00\xff');branch(0xa7,'loop')
        mark('yes');emit(b'\x04\xac')
        mark('no');emit(b'\x03\xac')
        for offset,label in branches:struct.pack_into('>h',code,offset+1,labels[label]-offset)
        cf.methods.append((8,cf.utf('gf3SaveReady'),cf.utf('()Z'),[(cf.utf('Code'),pack_code(u2(2)+u2(1),bytes(code),u2(0),[]))]))
        for i,(flags,n,d,attrs) in enumerate(cf.methods):
            if (cf.string(n),cf.string(d))==('c','(Z)V'):
                cf.methods[i]=(flags|0x20,n,d,attrs)
        # Snapshot before pause; the explicit quit action also snapshots before
        # the game's original confirmation / return-to-title sequence.
        for name,desc,alias,load,ret,flagsize in [('h','()V','gf3PauseLifecycle',b'\x2a',b'\xb1',1),('et','()V','gf3QuitNative',b'',b'\xb1',0)]:
            matches=[i for i,(_,n,d,_) in enumerate(cf.methods) if (cf.string(n),cf.string(d))==(name,desc)]
            if len(matches)!=1:raise ValueError('Missing lifecycle '+name)
            i=matches[0];flags,n,d,attrs=cf.methods[i]
            cf.methods[i]=(flags,cf.utf(alias),d,attrs)
            call=b'\xb8'+u2(cf.ref('GF3Presentation','saveNow','()V'))
            call+=load+(b'\xb7' if load else b'\xb8')+u2(cf.ref('a',alias,desc))+ret
            cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(1)+u2(flagsize),call,u2(0),[]))]))
        if len(pointers)!=3: raise ValueError("Missing physical touch inputs")
        cf.methods.extend(pointers)
    if entry=='GloftGF2M.class':
        i,=[i for i,(_,n,d,_) in enumerate(cf.methods) if (cf.string(n),cf.string(d))==('destroyApp','(Z)V')]
        flags,n,d,attrs=cf.methods[i]
        cf.methods[i]=(2,cf.utf('gf3DestroyNative'),d,attrs)
        call=b'\xb8'+u2(cf.ref('GF3Presentation','saveNow','()V'))+b'\x2a\x1b\xb7'+u2(cf.ref('GloftGF2M','gf3DestroyNative','(Z)V'))+b'\xb1'
        cf.methods.append((flags,n,d,[(cf.utf('Code'),pack_code(u2(2)+u2(2),call,u2(0),[]))]))
        changed=True
    if entry in ("f.class","a.class") and not recognized:
        raise ValueError("Missing native farm drawing entry point in "+entry)
    return cf.bytes() if changed else data


def build(source, output, api, javac="javac"):
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        stub = temp / "g.java"
        stub.write_text("abstract class g extends javax.microedition.lcdui.Canvas {static boolean o; static int M;"
                        "public abstract void gf3OriginalPaint(javax.microedition.lcdui.Graphics graphics);}"
                        "abstract class a extends g {static int a(){return 0;}static boolean gf3SaveReady(){return false;}static void c(boolean force){}void gf3PointerPressed(int x,int y){} "
                        "void gf3PointerReleased(int x,int y){} void gf3PointerDragged(int x,int y){}} "
                        "class GF3Wheel {static boolean resourcePointer(int x,int y,int phase){return false;}} "
                        "class f {static void b(){}} class k {static int[][] a; static int[] p;"
                        "static void a(javax.microedition.lcdui.Graphics g,int x,int y,int layer){}}",
                        encoding="ascii")
        subprocess.run([javac, "--release", "8", "-g:none", "-classpath", str(api.resolve()), "-d", str(temp), str(stub), *map(str, sorted(HERE.glob("GF3*.java")))], check=True)
        helpers = {p.name: convert_helper(p.read_bytes()) for p in temp.glob("GF3*.class")}
        if source.resolve() == output.resolve():
            raise ValueError("choose a separate output JAR")
        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(source) as z, zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as out:
            if "g.class" not in z.namelist() or any(k in z.namelist() for k in helpers):
                raise ValueError("not an unmodified supported engine")
            for e in z.infolist():
                data = z.read(e)
                out.writestr(e, patch(data, e.filename) if e.filename.endswith(".class") else data)
            for name, value in sorted(helpers.items()):
                entry = zipfile.ZipInfo(name,(1980,1,1,0,0,0))
                # Preserve the same ZIP metadata on Windows and on the Actions runner.
                entry.create_system = 0
                entry.compress_type = zipfile.ZIP_DEFLATED
                out.writestr(entry, value)

RUN_SHA = "6ada43b08bb13f713f2d23c73dd23caabce812b20c619b9c8c1fe02d49254e84"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("input", "output", "api"):
        parser.add_argument("--" + key, required=True, type=Path)
    args = parser.parse_args()
    build(args.input, args.output, args.api)
