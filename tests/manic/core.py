"""Fetch and verify the exact J2meJS distribution bundled with the tested iOS release."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
import json
import os
from pathlib import Path
import tempfile
from urllib.request import urlopen

HERE = Path(__file__).resolve().parent
CORE_COMMIT = "5840a80d333753c22038420da5c111a7fa9103a4"
REPOSITORY = "Manic-EMU/ManicEMU"


def prepare_core():
    configured = os.environ.get("MANIC_CORE_DIR")
    root = Path(configured) if configured else Path(tempfile.gettempdir()) / "gf3-manic" / CORE_COMMIT
    hashes = json.loads((HERE / "core-sha256.json").read_bytes())

    def obtain(entry):
        name, expected = entry
        target = root / name
        if target.is_file() and sha256(target.read_bytes()).hexdigest() == expected:
            return
        if configured:
            raise ValueError(f"Unverified Manic EMU core file at {target}")
        host = "https://media.githubusercontent.com/media" if name == "java/classes.jar" else "https://raw.githubusercontent.com"
        url = f"{host}/{REPOSITORY}/{CORE_COMMIT}/System.core/j2mejs/{name}"
        with urlopen(url, timeout=60) as response:
            data = response.read()
        if sha256(data).hexdigest() != expected:
            raise ValueError(f"Unexpected Manic EMU resource at {url}")
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temporary:
            temporary.write(data)
        os.replace(temporary.name, target)

    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(obtain, hashes.items()))
    return root
