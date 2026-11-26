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
        if len(pointers)!=3: raise ValueError("Missing physical touch inputs")
        cf.methods.extend(pointers)
    if entry in ("f.class","a.class") and not recognized:
        raise ValueError("Missing native farm drawing entry point in "+entry)
    return cf.bytes() if changed else data


def build(source, output, api, javac="javac"):
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        stub = temp / "g.java"
        stub.write_text("abstract class g extends javax.microedition.lcdui.Canvas {static boolean o; static int M;"
                        "public abstract void gf3OriginalPaint(javax.microedition.lcdui.Graphics graphics);}"
                        "abstract class a extends g {static int a(){return 0;}void gf3PointerPressed(int x,int y){} "
                        "void gf3PointerReleased(int x,int y){} void gf3PointerDragged(int x,int y){}} "
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
