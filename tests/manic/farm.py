"""Restore the farm earned by the touch tutorial into an empty Manic browser profile."""
import gzip
from pathlib import Path


async def restore_level_three(page):
    # The independent fixture MIDlet saved these three records through MIDP's
    # RecordStore API. Manic keys the browser records by the imported JAR name.
    fixture = Path(__file__).with_name("level3-rms.json.gz")
    with gzip.open(fixture, "rt", encoding="utf8") as source:
        exported = source.read()
    # The VM may signal readiness before IndexedDB opens the filesystem.
    # /Persistent is created by the core only after that asynchronous work.
    await page.wait_for_function("typeof fs !== 'undefined' && fs.exists('/Persistent')")
    await page.evaluate(
        "(data) => new Promise(done => fs.importStore(new Blob([data]), done))",
        exported,
    )
