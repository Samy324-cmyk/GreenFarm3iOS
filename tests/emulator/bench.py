"""Run a clean offline 480x800 MIDP test using the verified FreeJ2ME-Plus release.

Requires JDK 17 or 21. Use --java on hosts defaulting to Java 24+.
The release is fetched once by this Python script. The game JVM is offline.
"""
import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
URL = 'https://github.com/TASEmulators/freej2me-plus/releases/download/1.53/freej2me_plus-v1.53.zip'
ZIP_HASH = 'f2c647c3a62a55d904115fc7ec28103ed3bc3f438cac1de8d90e2cfd4c054f25'
LIB_HASH = '77e48d873289e15dc60d35db2f66cf3d2e862e79661cac4c8fb48625615f1ea2'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def emulator():
    jar = ROOT / 'distribution' / 'freej2me_plus-lr.jar'
    if not jar.is_file():
        with urllib.request.urlopen(URL, timeout=45) as response:
            data = response.read()
        if digest(data) != ZIP_HASH:
            raise RuntimeError('Unexpected emulator archive digest')
        with zipfile.ZipFile(io.BytesIO(data)) as distribution:
            name, = [n for n in distribution.namelist() if Path(n).name == jar.name]
            jar.parent.mkdir(exist_ok=True)
            jar.write_bytes(distribution.read(name))
    if digest(jar.read_bytes()) != LIB_HASH:
        raise RuntimeError('Unexpected emulator JAR digest')
    return jar


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('game', type=Path, nargs='?')
    parser.add_argument('profile', type=Path, nargs='?', help='New dedicated test directory')
    parser.add_argument('--prepare', action='store_true', help='Install and verify the portable emulator, then print its API JAR path')
    parser.add_argument('--java', default='java')
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--script', type=Path, default=ROOT/'verify-harvest.txt')
    parser.add_argument('--rms-from', type=Path, help='Copy only MIDP RecordStores from an earlier run')
    parser.add_argument('--audio', action='store_true', help='Enable MMAPI and capture PCM in a silent test mixer')
    parser.add_argument('--size',choices=('480x800','1280x720','1920x1080','720x1280'),default='480x800',
                        help='Physical emulator display dimensions for the pan benchmark')
    args = parser.parse_args()
    if args.prepare:
        print(emulator())
        return
    if args.game is None or args.profile is None:
        parser.error('game and profile are required to run the test')
    game = args.game.resolve(strict=True)
    profile = args.profile.resolve()
    profile.mkdir(parents=True, exist_ok=False)
    if args.rms_from:
        shutil.copytree((args.rms_from/'rms').resolve(strict=True), profile/'rms')
    lib = emulator()
    sources=[str(ROOT/'TouchBench.java')]
    inputs = args.script.read_text(encoding='utf-8')
    scenarios=re.findall(r'^measure (\w+)$',inputs,re.M)
    classpath=os.pathsep.join([str(game),str(lib)])
    if 'pan' in scenarios:
        sources.append(str(ROOT/'TerrainPresentationProbe.java'))
    if args.audio:
        provider=profile/'META-INF/services/javax.sound.sampled.spi.MixerProvider'
        provider.parent.mkdir(parents=True)
        provider.write_text('CaptureAudio\n',encoding='ascii')
        sources.append(str(ROOT.parent/'audio/CaptureAudio.java'))
    subprocess.run([args.javac, '--release', '8', '-Xlint:-options', '-cp', classpath, '-d',
                    str(profile), *sources], check=True)
    terrain_check=''
    if 'pan' in scenarios:
        probe=subprocess.run([args.java,'-Djava.awt.headless=true','-Dfile.encoding=ISO_8859_1',
            '-cp',os.pathsep.join([str(profile),classpath]),'TerrainPresentationProbe'],
            cwd=profile,check=True,capture_output=True,text=True)
        terrain_check=probe.stdout.strip()
        if terrain_check!='TERRAIN_PIXELS_OK poses=204':
            raise RuntimeError('Incomplete wrapped terrain pixel comparison')
    width,height=args.size.split('x')
    command = [args.java, *(['-Xmx256m'] if args.audio or scenarios else []),
               '-Djava.security.manager=allow', '-Djava.awt.headless=true',
               '-Dgf3.bench.audio='+str(args.audio).lower(),
               '-Dgf3.bench.glyphSeconds='+('25' if args.size=='480x800' else '60'),
               '-Dfile.encoding=ISO_8859_1', f'-Duser.home={profile}', f'-Djava.io.tmpdir={profile}',
               '-cp', os.pathsep.join([str(profile), str(lib)]), 'TouchBench',
               str(game), width, height, '0']
    logfile = profile/'run.log'
    with logfile.open('wb') as stream:
        finished = subprocess.run(command, cwd=profile, input=inputs.encode(), stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=150)
    log = logfile.read_text(encoding='latin-1')
    snapshots = {p.name: digest(p.read_bytes()) for p in sorted(profile.glob('*.png'))}
    measures = re.findall(r'^(?:SCENARIO|METRIC|PIXELS|COUNTERS) [^\r\n]+', log, re.MULTILINE)
    report = {'emulator': 'FreeJ2ME-Plus 1.53', 'emulatorJarSha256': LIB_HASH,
              'gameSha256': digest(game.read_bytes()), 'offline': True, 'width':int(width), 'height':int(height),
              'emulatorFrameCap':0, 'emulatorFrameHack':'Default', 'emulatorOutputSound':args.audio,
              'commands':inputs.splitlines(), 'saveRestored':bool(args.rms_from),
              'measurements':measures, 'screenshots':snapshots,
              'exitCode':finished.returncode}
    if terrain_check:
        report['terrainPixelComparison']=terrain_check
    if scenarios:
        rates={}
        for name,moves,pixels,grounds,presents,span,fps,p50,p95,changes,visible,ticks in re.findall(
                r'SCENARIO (\w+) cameraMoves=(\d+) cameraPixels=(\d+) capturedTerrainFrames=(\d+)\s+'
                r'METRIC presents=(\d+) span=([\d.]+) fps=([\d.]+) p50_ms=([\d.]+) p95_ms=([\d.]+)\s+'
                r'PIXELS changed=(\d+) rate=([\d.]+)\s+COUNTERS ticks=(\d+)','\n'.join(measures)):
            rates[name]={'cameraMoves':int(moves),'cameraPixels':int(pixels),'capturedTerrainFrames':int(grounds),
                'presents':int(presents),'elapsedSeconds':float(span),'presentedFps':float(fps),'changedFrames':int(changes),
                'changedFps':float(visible),'simulationTicks':int(ticks),'p50Ms':float(p50),'p95Ms':float(p95)}
        report['scenarios']=rates
    (profile/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('\n'.join(measures), flush=True)
    if finished.returncode or not snapshots or not any(m.startswith('PIXELS ') for m in measures):
        raise SystemExit('Incomplete test, inspect run.log')
    if 'pan' in scenarios:
        pan=report['scenarios'].get('pan',{})
        static=report['scenarios'].get('static',{})
        if (not pan or not static or static['cameraPixels']!=0 or pan['cameraPixels']<400 or
                pan['capturedTerrainFrames']<pan['presents']*.9 or
                pan['changedFrames']<=pan['simulationTicks']*1.5):
            raise SystemExit('Camera motion or intermediate terrain painting was not verified')


if __name__ == '__main__':
    main()
