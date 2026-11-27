"""Run a MIDlet through the WebView entry point shipped in Manic EMU 2.0.2."""
import asyncio
from contextlib import asynccontextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import tempfile
from threading import Thread
from zipfile import ZipFile

from playwright.async_api import async_playwright

from core import prepare_core


def manifest_size(jar):
    """Use the resolution precedence of J2MEManifest.screenSize in the iOS app."""
    with ZipFile(jar) as archive:
        text = archive.read("META-INF/MANIFEST.MF").decode("utf8")
    fields = dict(line.split(": ", 1) for line in text.splitlines() if ": " in line)
    for key in ("Nokia-MIDlet-Canvas-Size", "MIDlet-ScreenSize", "Nokia-MIDlet-Original-Display-Size", "MIDlet-Display-Size"):
        if key in fields:
            parts = re.split("[x,*]", fields[key])
            if len(parts) == 2 and all(p.strip().isdigit() and int(p) > 0 for p in parts):
                return f"{int(parts[0])}x{int(parts[1])}"
            break
    match = re.search(r"(\d{3})x(\d{3})", Path(jar).name, re.IGNORECASE)
    return match.group(0).lower() if match else "240x320"


@asynccontextmanager
async def session(jar, engine="webkit", size=None, rotate=False, port=0, before_open=None,
                  init_script=None, viewport=(390, 844), observe_console=True):
    jar = Path(jar).resolve(strict=True)
    size = size or manifest_size(jar)
    core = await asyncio.to_thread(prepare_core)

    class Handler(SimpleHTTPRequestHandler):
        def translate_path(self, path):
            if path.split("?", 1)[0] == "/game.jar":
                return str(jar)
            return super().translate_path(path)

        def log_message(self, *args):
            pass

    http = ThreadingHTTPServer(("127.0.0.1", port), partial(Handler, directory=str(core)))
    Thread(target=http.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="gf3-manic-profile-") as profile:
            async with async_playwright() as pw:
                settings = dict(headless=True, viewport=dict(width=viewport[0], height=viewport[1]),
                                has_touch=True, is_mobile=True, device_scale_factor=1, locale="es-MX")
                if engine == "webkit":
                    ctx = await pw.webkit.launch_persistent_context(profile, **settings)
                elif engine == "edge":
                    ctx = await pw.chromium.launch_persistent_context(profile, channel="msedge", **settings)
                elif engine == "chromium":
                    ctx = await pw.chromium.launch_persistent_context(profile, **settings)
                else:
                    raise ValueError(f"Unknown browser {engine}")
                try:
                    if init_script:
                        await ctx.add_init_script(init_script)
                    page = await ctx.new_page()
                    logs = []
                    if observe_console:
                        page.on("console", lambda msg: logs.append(msg.type + " " + msg.text[:1200]))
                    page.on("pageerror", lambda err: logs.append("ERROR " + str(err)[:2000]))
                    await page.goto(f"http://127.0.0.1:{http.server_port}/index.html", wait_until="load", timeout=90000)
                    await page.wait_for_function("""typeof CLASSES !== 'undefined' && CLASSES.java_lang_Object &&
                        typeof JARStore !== 'undefined' && typeof MIDP !== 'undefined' && typeof jvm !== 'undefined'""",
                                                 timeout=90000)
                    if before_open:
                        await before_open(page)
                    # The native Swift view passes this byte array, filename, logical screen and rotation.
                    await page.evaluate("""async ([name, size, rotate]) => {
                        const response = await fetch('/game.jar');
                        if (!response.ok) throw new Error('Game JAR download failed');
                        const bytes = new Uint8Array(await response.arrayBuffer());
                        window.j2me.openJar(bytes, name, size, rotate);
                    }""", [jar.name, size, rotate])
                    yield page, logs
                finally:
                    await ctx.close()
    finally:
        http.shutdown()
        http.server_close()
