"""Install Android 4.4.4 objective matching in the MIDP event dispatcher.

No Android-only quests are enabled here. Their actors, art, inventory and
script events are separate dependencies of making them available in-game.
"""
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.timing.classfile import ClassFile, code_parts, convert_helper, pack_code, u2

DESCRIPTOR = "(ZIIIIZ)I"
ORIGINAL_SHA = "95c33bb73015841ba18db38512dd75de7a1f84bfec50e60256dfc575bdd11e90"


def build_rules(jar, apk):
    from tools.world import entries, table
    catalog = entries(apk.read("assets/800x480/13"))
    animals = table(catalog[0])[1]
    crops = table(catalog[2])[1]
    if ([r[1] for r in animals[64:76]] != list(range(2064, 2076)) or
            [r[1] for r in crops[22:24]] != [3022, 3023]):
        raise ValueError("The Android expansion item IDs differ from this release")

    cf = ClassFile(jar.read("a.class"))
    match, = [(i, m) for i, m in enumerate(cf.methods)
              if cf.string(m[1]) == "a" and cf.string(m[2]) == DESCRIPTOR]
    index, (flags, name, descriptor, attrs) = match
    body, = [code_parts(b)[1] for k, b in attrs if cf.string(k) == "Code"]
    if flags != 10 or hashlib.sha256(body).hexdigest() != ORIGINAL_SHA:
        raise ValueError("Unsupported original mission dispatcher")

    # A new straight-line wrapper delegates all original return semantics,
    # including 2 and 3, to the game's existing preverified method.
    original = cf.ref("a", "gf3LegacyObjective", DESCRIPTOR)
    extended = cf.ref("GF3ExpansionRules", "progress", "(IZIIII)I")
    code = (bytes.fromhex("1a1b1c1d15041505b8") + u2(original)
            + bytes.fromhex("1a1b1c1d1504b8") + u2(extended) + bytes([0xac]))
    cf.methods[index] = flags, cf.utf("gf3LegacyObjective"), descriptor, attrs
    cf.methods.append((flags, name, descriptor, [(cf.utf("Code"),
                      pack_code(u2(6) + u2(6), code, u2(0), []))]))
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["javac", "--release", "8", "-g:none", "-d", tmp,
                        str(ROOT / "src/expansion/GF3ExpansionRules.java")], check=True)
        helper = convert_helper((Path(tmp) / "GF3ExpansionRules.class").read_bytes())
    return {"a.class": cf.bytes(), "GF3ExpansionRules.class": helper}
