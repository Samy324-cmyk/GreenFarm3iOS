"""Open the store, barn and manor in one session of the original Manic J2meJS core."""
import argparse
import asyncio
import base64
import hashlib
import json
from pathlib import Path

from farm import restore_level_three
from runtime import manifest_size, session


HERE = Path(__file__).resolve().parent


async def capture(page, target):
    png = await page.evaluate("document.getElementById('canvas').toDataURL('image/png').split(',')[1]")
    target.write_bytes(base64.b64decode(png))


async def compare(page, step):
    name = step["name"]
    reference = base64.b64encode((HERE / "screens" / (name + ".png")).read_bytes()).decode("ascii")
    args = [name, step["region"], reference]
    closest = None
    for _ in range(16):
        result = await page.evaluate("args => gf3Scenes.compare(...args)", args)
        if closest is None or result["ratio"] < closest["ratio"]:
            closest = result
        if result["ratio"] <= step.get("maxDifference", .025):
            return result
        await page.wait_for_timeout(400)
    return closest


async def run(jar, out, size, engine):
    out.mkdir(exist_ok=True, parents=True)
    steps = json.loads((HERE / "scenes.json").read_bytes())
    report = {"jarSha256": hashlib.sha256(jar.read_bytes()).hexdigest(),
              "size": size or manifest_size(jar), "engine": engine, "steps": []}
    async with session(jar, engine=engine, size=size, before_open=restore_level_three,
                       init_script=(HERE / "scenes.js").read_text("utf8")) as (page, logs):
        step = {"name": "granja"}
        try:
            await page.wait_for_function("gf3Scenes.matches({screen:17,button:65595})", timeout=180000)
            await page.wait_for_timeout(1200)
            for step in steps:
                await page.evaluate("step => gf3Scenes.press(step)", step)
                await page.wait_for_function("step => gf3Scenes.matches(step)", arg=step, timeout=30000)
                await page.wait_for_timeout(650)
                result = {"name": step["name"], **{k: step[k] for k in ("screen","tab","shelf","room") if k in step}}
                if step["name"]=="ofertas" or step["name"].startswith("regreso-ofertas-"):
                    state=await page.evaluate("gf3Scenes.state()")
                    count=state.get("offerCount",0)
                    ids=state.get("offerIds",[])[:count]
                    if count not in (2,3) or len(ids)!=count or len(set(x for x in ids if x>=0))!=sum(x>=0 for x in ids):
                        raise AssertionError(f"Invalid weekly cards: {state}")
                    # Wait across multiple paints, rather than accepting one
                    # transient screen immediately before a crash.
                    await page.wait_for_timeout(1800)
                    after=await page.evaluate("gf3Scenes.state()")
                    if after.get("screen")!=7 or after.get("tab")!=5 or after.get("offerIds")!=state["offerIds"]:
                        raise AssertionError("Weekly offers changed or exited during rendering")
                    result["offerCount"]=count
                    result["offerIds"]=ids
                if "region" in step:
                    result["pixels"] = await compare(page, step)
                    pixels = result["pixels"]
                    if pixels["ratio"] > step.get("maxDifference", .025):
                        report["mismatch"] = pixels
                        raise AssertionError(f"{step['name']}: {pixels['different']}/{pixels['count']} "
                                             "píxeles difieren de los sprites de referencia")
                await capture(page, out / (step["name"] + ".png"))
                report["steps"].append(result)
                print(json.dumps(result, ensure_ascii=False), flush=True)
        except Exception:
            await capture(page, out / (step["name"] + "-error.png"))
            report["failure"] = {"name": step["name"], "state": await page.evaluate("gf3Scenes.state()")}
            raise
        finally:
            (out / "scenes.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), "utf8")
            (out / "core.log").write_text("\n".join(logs), "utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jar", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--size", choices=("480x800", "240x320"))
    parser.add_argument("--engine", choices=("webkit", "chromium", "edge"), default="webkit")
    args = parser.parse_args()
    asyncio.run(run(args.jar.resolve(strict=True), args.out.resolve(), args.size, args.engine))
