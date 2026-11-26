"""Use the iPhone simulator touchscreen to harvest, pan, visit the shop and open the manor."""
import argparse
from hashlib import sha256
import gzip
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from threading import Thread

from core import CORE_COMMIT, prepare_core

HERE = Path(__file__).resolve().parent


def simctl(*args, **kwargs):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True, **kwargs).strip()


def select_iphone(project):
    # macOS runners can contain simulator runtimes for several Xcodes.
    # Only boot a destination that the selected Xcode can actually test.
    destinations = subprocess.check_output(
        ["xcodebuild", "-project", str(project), "-scheme", "Farm", "-showdestinations"],
        text=True, stderr=subprocess.STDOUT, timeout=90)
    eligible = destinations.split("Ineligible destinations", 1)[0]
    udids = {match.lower() for match in re.findall(r"\bid:\s*([0-9a-fA-F-]{36})\b", eligible)}
    available = json.loads(simctl("list", "devices", "available", "-j"))["devices"]
    candidates = [(tuple(int(v) for v in runtime.split(".iOS-")[1].split("-")), d["name"], runtime, d)
                  for runtime, devices in available.items() if ".iOS-" in runtime
                  for d in devices if d["isAvailable"] and d["udid"].lower() in udids and d["name"].startswith("iPhone")]
    if not candidates:
        raise RuntimeError("No bootable iPhone destination for the Farm scheme.\n" + destinations)
    _, _, runtime, device = max(candidates, key=lambda x: (x[0], x[1]))
    return runtime, device


def run(jar, out):
    core = prepare_core()
    out.mkdir(exist_ok=True, parents=True)
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        site = scratch/"site"
        shutil.copytree(core, site)
        shutil.copy2(jar, site/"game.jar")
        (site/"level3.json").write_bytes(gzip.decompress((HERE/"level3-rms.json.gz").read_bytes()))
        project = scratch/"test"
        shutil.copytree(HERE/"ios", project)
        shutil.copy2(HERE/"scenes.json", site/"scenes.json")
        shutil.copy2(HERE/"scenes.js", project/"App/scenes.js")
        shutil.copytree(HERE/"screens", site/"screens")
        stages = {"letter","inheritance","wheat","harvested","farm","pan","journal","walt","mision",
                  "aviso","cerrar-aviso","blueprint","kitchen"}
        steps = json.loads((site/"scenes.json").read_bytes())
        stages.update("menu-"+s["name"] for s in steps[:next(i for i,s in enumerate(steps) if s["name"]=="diario")])
        allowed = {s+".png" for s in stages} | {"pan.json"}

        class EvidenceServer(SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=str(site), **kwargs)

            def do_POST(self):
                name = self.path.removeprefix("/evidence/")
                size = int(self.headers.get("Content-Length", "0"))
                if self.path != "/evidence/"+name or name not in allowed or not 0 < size <= 8*1024*1024:
                    self.send_error(400)
                    return
                (out/name).write_bytes(self.rfile.read(size))
                self.send_response(204)
                self.end_headers()

        http = ThreadingHTTPServer(("127.0.0.1", 0), EvidenceServer)
        Thread(target=http.serve_forever, daemon=True).start()
        try:
            (project/"App/endpoint.txt").write_text(f"http://127.0.0.1:{http.server_port}/index.html",encoding="ascii")
            subprocess.run(["xcodegen","generate"], cwd=project, check=True)
            xcode_project = project/"ManicFarmTest.xcodeproj"
            # A hosted macOS image may contain runtimes for another installed Xcode.
            # Probe each toolchain, keep the first with a real eligible iPhone,
            # and use that same Xcode for simctl and the complete test run.
            selected = os.environ.get("DEVELOPER_DIR")
            candidates = [selected] if selected else [None]
            candidates.extend(str(p/"Contents/Developer") for p in sorted(Path("/Applications").glob("Xcode*.app"),reverse=True))
            failures=[]
            for developer in dict.fromkeys(candidates):
                if developer:
                    os.environ["DEVELOPER_DIR"]=developer
                else:
                    os.environ.pop("DEVELOPER_DIR",None)
                try:
                    runtime, device = select_iphone(xcode_project)
                    print("Selected iPhone toolchain:", developer or "system default",runtime,device["name"])
                    break
                except (RuntimeError, subprocess.SubprocessError) as error:
                    failures.append(str(developer)+": "+str(error))
            else:
                raise RuntimeError("No installed Xcode can test an iPhone:\n"+"\n".join(failures))
            udid = device["udid"]
            if device["state"] != "Booted":
                simctl("boot", udid)
            simctl("bootstatus", udid, "-b", timeout=300)
            with (out/"xctest.log").open("w", encoding="utf8") as log:
                result = subprocess.run(["xcodebuild", "-project", str(xcode_project),
                                         "-scheme", "Farm", "-destination", "id="+udid, "-parallel-testing-enabled", "NO",
                                         "-derivedDataPath", str(scratch/"derived"), "test"], cwd=project,
                                        stdout=log,stderr=subprocess.STDOUT,timeout=720)
            subprocess.run(["xcrun","simctl","io",udid,"screenshot",str(out/"iphone.png")], check=False)
            bundle = subprocess.run(["xcrun","simctl","get_app_container",udid,"org.local.greenfarm.ManicTest","data"],
                                    capture_output=True,text=True)
            if bundle.returncode == 0:
                docs = Path(bundle.stdout.strip())/"Documents"
                for shot in [*docs.glob("*.png"), *docs.glob("pan.json")]:
                    shutil.copy2(shot, out/shot.name)
            if result.returncode:
                print((out/"xctest.log").read_text("utf8")[-6500:])
                raise RuntimeError("The iPhone simulator did not complete its touch tests")
            for name in sorted(stages):
                if not (out/(name+".png")).is_file():
                    raise RuntimeError("Missing LCD evidence for "+name)
            pan = json.loads((out/"pan.json").read_bytes())
            report = {"core":CORE_COMMIT,"device":device["name"],"runtime":runtime,"panFps":pan["presentedFps"],
                      "jarSha256":sha256(jar.read_bytes()).hexdigest(),"firstHarvest":True,"mansionInterior":True,"stages":sorted(stages)}
            (out/"iphone.json").write_text(json.dumps(report,indent=2),encoding="utf8")
            print(report)
        finally:
            http.shutdown()
            http.server_close()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("jar",type=Path)
    p.add_argument("out",type=Path)
    args = p.parse_args()
    run(args.jar.resolve(strict=True),args.out.resolve())
