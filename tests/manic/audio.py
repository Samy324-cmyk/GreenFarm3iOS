"""Exercise the original Manic J2meJS sound provider through real tutorial touches."""
import argparse
import asyncio
from collections import Counter
import json
from pathlib import Path

from runtime import session


# Observe each source before it reaches the speaker. The analyser receives the
# game's signal and the test's final gain silences outward playback.
MONITOR = """async hashes => {
    if (typeof AudioBufferSourceNode === 'undefined') throw Error('This browser has no Web Audio output');
    window.played = [];
    const format = PlayerContainer.prototype;
    const render = format._playDecodedWav;
    format._playDecodedWav = function() {
        if (!this.wavBuffer.gf3Recording) {
            const bytes = this.data.subarray(0, this.contentSize);
            this.wavBuffer.gf3Recording = crypto.subtle.digest('SHA-256', bytes).then(digest => {
                const hash = [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2,'0')).join('');
                if (!(hash in hashes)) throw Error('Unrecognized PCM recording '+hash);
                return hashes[hash];
            });
        }
        return render.apply(this, arguments);
    };
    const connect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function(target) {
        if (this instanceof AudioBufferSourceNode && target === this.context.destination && this.buffer?.gf3Recording) {
            const analyser = this.context.createAnalyser();
            analyser.fftSize = 1024;
            const mute = this.context.createGain();
            mute.gain.value = 0;
            analyser.connect(mute);
            mute.connect(target);
            this.gf3Analyser = analyser;
            return connect.call(this, analyser);
        }
        return connect.apply(this, arguments);
    };
    const start = AudioBufferSourceNode.prototype.start;
    AudioBufferSourceNode.prototype.start = function() {
        if (this.gf3Analyser) {
            const event = {id:null, start:this.context.currentTime, duration:this.buffer.duration,
                           peak:0, finished:false};
            played.push(event);
            this.buffer.gf3Recording.then(id => {event.id = id;});
            const samples = new Float32Array(1024);
            const timer = setInterval(() => {
                this.gf3Analyser.getFloatTimeDomainData(samples);
                for (const sample of samples) event.peak = Math.max(event.peak, Math.abs(sample));
            }, 12);
            this.addEventListener('ended', () => {
                clearInterval(timer);
                event.finished = true;
            });
        }
        return start.apply(this, arguments);
    };
}"""


async def check(jar, out, engine, report):
    hashes = {r['wavSha256']: r['apk'] for r in json.loads(report.read_text('utf8'))['media']['apkAudio']}
    out.mkdir(parents=True, exist_ok=True)

    async def monitor(page):
        await page.evaluate(MONITOR, hashes)
        # The first input unlocks the output in browsers with autoplay rules.
        await page.touchscreen.tap(1, 1)

    async with session(jar, engine=engine, size='480x800', before_open=monitor) as (page, logs):
        async def tap(x, y):
            box = await page.locator('#canvas').bounding_box()
            await page.touchscreen.tap(box['x']+box['width']*x/480, box['y']+box['height']*y/800)

        async def heard(cue, minimum=1, timeout=12000):
            await page.wait_for_function('([id,minimum]) => played.filter(p => p.id===id && p.peak>0.001).length >= minimum',
                                         arg=[cue,minimum], timeout=timeout)

        try:
            await heard(59, timeout=90000)
            for confirmation in (1, 2):
                await page.wait_for_timeout(1250)
                await tap(92, 604)
                await heard(60, confirmation)
            await page.wait_for_timeout(1250)
            await tap(92, 604)
            await heard(53)
            await page.wait_for_timeout(1250)
            await tap(78, 605)
            await heard(60, 3)
            await page.wait_for_timeout(700)
            await tap(264, 414)
            await heard(39)
            await heard(37)
            await tap(265, 414)
            await heard(39, 2)
            await page.wait_for_timeout(200)
            await tap(265, 414)
            await heard(39, 3)
            await heard(24, 2, timeout=25000)
        finally:
            events = await page.evaluate('played')
            audible = [p for p in events if p['id'] is not None and p['peak']>0.001]
            (out/'audio.json').write_text(json.dumps({'browser':engine,'counts':Counter(p['id'] for p in audible),
                                                     'webAudio':events},indent=2),'utf8')
            await page.screenshot(path=out/'cosecha.png')
            (out/'run.log').write_text('\n'.join(logs),'utf8')
        if any(p['id'] is None for p in events):
            raise AssertionError('A WAV without verified Android provenance played')
        starts = [p['start'] for p in audible if p['id']==39]
        if not any(0<b-a<1 for a,b in zip(starts,starts[1:])):
            raise AssertionError('No audible harvest repeat within one second')
        refs = {p['id'] for p in audible}
        if not {12,24,37,39,53,59,60} <= refs:
            raise AssertionError(f'Tutorial sounds missing: {refs}')
        print(f'{len(audible)} audible Web Audio starts, including a repeated harvest and the ambient loop.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jar',type=Path)
    parser.add_argument('out',type=Path)
    parser.add_argument('--engine',choices=('chromium','edge','webkit'),default='chromium')
    parser.add_argument('--report',type=Path)
    args = parser.parse_args()
    asyncio.run(check(args.jar,args.out,args.engine,args.report or args.jar.with_name('build.json')))
