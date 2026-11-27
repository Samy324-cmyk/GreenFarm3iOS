"""Play quest 9304 through the actual touch controls in FreeJ2ME."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

HERE=Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('jar','api','out'):p.add_argument(name,type=Path)
    p.add_argument('--java',default='java')
    mode=p.add_mutually_exclusive_group()
    mode.add_argument('--save',action='store_true')
    mode.add_argument('--reload-from',type=Path)
    p.add_argument('--predator',action='store_true')
    args=p.parse_args()
    api,out=args.api.resolve(),args.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    shutil.copytree((args.reload_from or HERE.parent/'emulator/fixtures/level15')/'rms',out/'rms')
    source=(HERE.parent/'emulator/TouchBench.java').read_text('utf8')
    (out/'TouchBench.java').write_text(source.replace('case "quit":','case "honey": HoneyProbe.run(t[1]);break;\n'
                                                     '            case "home": HomeProbe.run(t[1]);break;\n'
                                                     '            case "quit":'),encoding='utf8')
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(out/'TouchBench.java'),
                    str(HERE/'HoneyProbe.java'),str(HERE/'HomeProbe.java'),str(HERE.parent/'catalog/MarketProbe.java'),
                    str(HERE.parent/'catalog/SceneCacheProbe.java')],check=True)
    ready=(HERE.parent/'emulator/verify-extractor.txt').read_text().splitlines()[0]
    commands=ready+'\n'
    if args.predator: commands+='home raid\n'
    if args.reload_from: commands+='honey restored\n'
    else: commands+='honey seed\nwait 900\nshot apicultor\nhoney intro\nshot colmena\nhoney harvest\n'
    if args.save: commands+='shot colmena-limpia\nhoney checkpoint\nclose\nwait 700\n'
    else: commands+='shot extractor\nhoney press\nshot miel\n'
    commands+='quit\n'
    with (out/'run.log').open('wb') as log:
        r=subprocess.run([args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
                          '-Dfile.encoding=ISO_8859_1',
                          f'-Duser.home={out}',f'-Djava.io.tmpdir={out}','-cp',os.pathsep.join([str(out),str(api)]),
                          'TouchBench',str(args.jar.resolve()),'480','800','0'],cwd=out,input=commands.encode(),
                         stdout=log,stderr=subprocess.STDOUT,timeout=160)
    lines=(out/'run.log').read_text('latin1').splitlines()
    print('\n'.join(line for line in lines if line.startswith('HONEY')))
    markers=['HONEY_SAVE_OK' if args.save else 'HONEY_OK']
    if args.predator:markers.append('HONEY_PREDATOR_OK')
    if args.reload_from: markers.append('HONEY_RELOAD_OK')
    if r.returncode or not all(any(line.startswith(m) for line in lines) for m in markers):
        raise SystemExit(f'Incomplete beekeeping lesson: {out/"run.log"}')


if __name__=='__main__': main()
