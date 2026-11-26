"""Measure actual WebView LCD updates during the same drag on the level-three farm."""
import argparse
import asyncio
import base64
from hashlib import sha256
import json
from pathlib import Path
import statistics
import zlib

from core import CORE_COMMIT
from farm import restore_level_three
from runtime import session

HERE = Path(__file__).resolve().parent
# The 25×30 pause-button ink mask also used by tests/emulator/verify-pan.txt.
PAUSE_INK = zlib.decompress(base64.b64decode("eJxjYBhowIgF4JfAJkOmDmpK0AMMqAfpIUFbAADMXwFH"))


def hud_samples(w, h):
    factor = min(w / 480, h / 800)
    width, height = int(480*factor), int(800*factor)
    left, top = (w-width)//2, (h-height)//2
    result = []
    for y in range(top+742*height//800, top+772*height//800+1):
        sy = (y-top)*800//height
        for x in range(left+428*width//480, left+453*width//480+1):
            sx = (x-left)*480//width
            if 428 <= sx < 453 and 742 <= sy < 772:
                result.append((x, y, bool(PAUSE_INK[(sy-742)*25+sx-428])))
    return result


async def save_canvas(page, path):
    png = await page.eval_on_selector("#canvas", "c => c.toDataURL('image/png').split(',')[1]")
    path.write_bytes(base64.b64decode(png))


def summarize(name, run, out):
    frames = run["frames"]
    intervals = [b-a for a, b in zip(frames, frames[1:])]
    if len(intervals) < 2:
        raise AssertionError(f"{name}: no series of WebView LCD presentations")
    span = frames[-1]-frames[0]
    cameras = run["camera"]
    distance = sum(abs(b[0]-a[0])+abs(b[1]-a[1]) for a,b in zip(cameras,cameras[1:]))
    run.update(fps=1000*len(intervals)/span, p50ms=statistics.median(intervals),
               p95ms=sorted(intervals)[int((len(intervals)-1)*.95)], maxGapMs=max(intervals),
               cameraPixels=distance, logicTicks=cameras[-1][2]-cameras[0][2],
               maxObservedQueuedEvents=max(run["queues"], default=0))
    if name=="timed" and run["fps"]<45:
        raise AssertionError(f"Presentation throughput regressed: {run['fps']:.2f} FPS")
    if name=="still" and distance:
        raise AssertionError(f"The camera moved {distance} pixels before the pointer gesture")
    if name!="still" and (distance < 200 or run["logicTicks"] < 2):
        raise AssertionError(f"{name}: the screen refreshed without the farm following the finger")
    hashes = run["frameHashes"]
    if hashes:
        changed = sum(a!=b for a,b in zip(hashes,hashes[1:]))
        run["visiblyChangedFps"] = 1000*changed/span
        if changed < 3:
            raise AssertionError("The farm camera moved but the WebView canvas remained still")
        if name=="visible" and run["visiblyChangedFps"]<25:
            raise AssertionError(f"Only {run['visiblyChangedFps']:.2f} distinct visual frames per second during drag")
        for idx, (time, png, score) in enumerate(run["samples"]):
            path = out / f"pose-{idx:03}.png"
            path.write_bytes(base64.b64decode(png))
            run["samples"][idx] = [time,path.name,score]
        # A pair of adjacent samples covers at least 220 ms, independent of host FPS.
        scores = [s[2] for s in run["samples"]]
        if len(scores) < 3 or any(max(a,b)<.65 for a,b in zip(scores,scores[1:])):
            raise AssertionError(f"Persistent missing or misplaced manor/stand during the drag: {scores}")


async def run(args):
    jar, out = args.jar.resolve(strict=True), args.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    width,height = map(int,args.size.split("x"))

    async def prepare(page):
        await restore_level_three(page)
        await page.evaluate((HERE/"pan.js").read_text("utf8"))

    async with session(jar,engine=args.engine,size=args.size,before_open=prepare,
                       observe_console=False) as (page, logs):
        report={"jarSha256":sha256(jar.read_bytes()).hexdigest(),"coreCommit":CORE_COMMIT,
                "engine":args.engine,"width":width,"height":height,"runs":{}}
        try:
            await page.wait_for_function("""tests => {
                const c=document.querySelector('#canvas'),g=c.getContext('2d');
                const a=g.getImageData(0,0,c.width,c.height).data;
                let good=0,ink=0,expected=0;
                for(const [x,y,set] of tests) {
                    const i=(y*c.width+x)*4;
                    const match=a[i]===245 && a[i+1]===248 && a[i+2]===252;
                    if(match===set)good++; if(match)ink++; if(set)expected++;
                }
                return good/tests.length>.99 && ink>=expected*.9;
            }""",arg=hud_samples(width,height),polling=800,timeout=420000)
            await page.evaluate("attachScreen()")
            await save_canvas(page,out/"farm.png")
            report["userAgent"]=await page.evaluate("navigator.userAgent")
            await page.wait_for_timeout(1300)
            # The timed pass only timestamps the actual device canvas. A separate
            # pass reads and hashes pixels and validates the visible landmarks.
            for name,duration,visual,pan in (("still",2800,False,False),("timed",6800,False,True),("visible",6800,True,True)):
                data=await page.evaluate("opts=>measurePan(opts)",dict(duration=duration,visual=visual,pan=pan))
                report["runs"][name]=data
                summarize(name,data,out)
                print(f"{name}: {len(data['frames'])} LCD frames, {data['fps']:.2f} FPS, "
                      f"p95 {data['p95ms']:.1f} ms, camera {data['cameraPixels']} px",flush=True)
                await page.wait_for_timeout(550)
            await save_canvas(page,out/"after.png")
        finally:
            await save_canvas(page,out/"last.png")
            (out/"report.json").write_text(json.dumps(report,indent=2)+"\n","utf8")
            (out/"runtime.log").write_text("\n".join(logs),"utf8")


if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("jar",type=Path)
    cli.add_argument("output",type=Path)
    cli.add_argument("--size",choices=("480x800","240x320"),default="480x800")
    cli.add_argument("--engine",choices=("webkit","chromium","edge"),default="webkit")
    asyncio.run(run(cli.parse_args()))
