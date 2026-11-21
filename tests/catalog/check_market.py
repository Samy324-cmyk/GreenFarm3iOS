"""Run the expanded farm through the native actor factory and shop UI."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('game','emulator','profile'):
        p.add_argument(name,type=Path)
    p.add_argument('--pan',action='store_true',help='Measure the level 3 zoom probe at 75 percent')
    p.add_argument('--rms-from',type=Path)
    p.add_argument('--java',default='java')
    p.add_argument('--javac',default='javac')
    p.add_argument('--probe',choices=('market','acres','flock','campaign','zoom','horizon','scenery','motion','orders','orders-reload','pond','pond-reload','plane','pause','mill','mill-reload','edits','edits-reload'),default='market')
    p.add_argument('--deed',type=int,choices=(6,12),default=12)
    args = p.parse_args()
    root = args.profile.resolve()
    root.mkdir(parents=True,exist_ok=False)
    if args.rms_from:
        shutil.copytree(args.rms_from/'rms',root/'rms')
        if args.probe=='pond-reload':
            shutil.copy2(args.rms_from/'pond-deadline.txt',root/'pond-deadline.txt')
        if args.probe=='mill-reload':
            shutil.copy2(args.rms_from/'mill-wallet.bin',root/'mill-wallet.bin')
    here=Path(__file__).resolve().parent
    bench=(here.parent/'emulator/TouchBench.java').read_text(encoding='utf-8')
    anchor='case "quit":'
    if bench.count(anchor)!=1:
        raise ValueError('TouchBench command anchor changed')
    test=root/'TouchBench.java'
    probe = {'market':'MarketProbe','acres':'AcreProbe','flock':'FlockProbe','campaign':'CampaignProbe','zoom':'ZoomProbe','horizon':'HorizonProbe','scenery':'SceneCacheProbe','motion':'SceneMotionProbe',
             'orders':'OrderProbe','orders-reload':'OrderProbe','pond':'PondProbe','pond-reload':'PondProbe','plane':'PlaneProbe','pause':'PauseProbe',
             'mill':'MillProbe','mill-reload':'MillProbe','edits':'FarmEditsProbe','edits-reload':'FarmEditsProbe'}[args.probe]
    argument = f', {args.deed}' if args.probe == 'acres' else ''
    if probe=='OrderProbe':argument=', '+str(args.probe=='orders-reload').lower()
    if probe=='PondProbe':argument=', '+str(args.probe=='pond-reload').lower()
    if probe=='MillProbe':argument=', '+str(args.probe=='mill-reload').lower()
    if probe=='FarmEditsProbe':argument=', '+str(args.probe=='edits-reload').lower()
    action='edges' if args.probe=='scenery' else 'check'
    test.write_text(bench.replace(anchor,f'case "{args.probe}": {probe}.{action}(Mobile.getPlatform().loader{argument});break;\n'+anchor),encoding='utf-8')
    emulator=args.emulator.resolve()
    probes = [here/'MarketProbe.java']
    if args.probe != 'market':
        probes.append(here/(probe+'.java'))
    if args.probe=='horizon':
        probes.append(here/'ZoomProbe.java')
    subprocess.run([args.javac,'--release','8','-Xlint:-options','-cp',str(emulator),
                    '-d',str(root),str(test),*map(str,probes)],check=True)
    cmd=[args.java,'-Xmx384m','-Djava.security.manager=allow','-Djava.awt.headless=true',
         f'-Duser.home={root}',f'-Djava.io.tmpdir={root}','-Dfile.encoding=ISO_8859_1',
         '-cp',os.pathsep.join([str(root),str(emulator)]),'TouchBench',str(args.game.resolve()),'480','800','0']
    ready = (here.parent/'emulator/verify-reload.txt').read_text().splitlines()[0] if args.rms_from else 'wait 13000'
    if args.probe=='orders-reload':ready='wait 7500'
    if args.probe=='pond-reload':ready='wait 9000'
    finish='shot puesto\nclose\nwait 600\n' if probe=='OrderProbe' else ''
    if args.probe=='zoom':
        shutil.copy2(here/'zoom-ground.rgb',root/'zoom-ground.rgb')
        if args.pan:
            finish='wait 1600\nmeasure static\nwait 3500\nreport\nmeasure pan\npan 100 580 200 470 8 850\nreport\n'
    if args.probe=='pond':finish='close\nwait 600\n'
    if args.probe=='mill':finish='shot molino\nclose\nwait 600\n'
    if args.probe=='edits':finish='shot edicion\nclose\nwait 600\n'
    with (root/'run.log').open('wb') as stream:
        r=subprocess.run(cmd,cwd=root,input=f'{ready}\n{args.probe}\n{finish}quit\n'.encode('ascii'),stdout=stream,
                         stderr=subprocess.STDOUT,timeout=180 if probe=='PondProbe' else 100 if probe=='OrderProbe' else 75)
    log=(root/'run.log').read_text(encoding='latin1')
    if r.returncode or args.probe.upper()+'_OK' not in log or 'Cannot set Media Time' in log:
        raise RuntimeError(f'{args.probe} probe failed. Inspect {root / "run.log"}')
    print(root/'run.log')


if __name__=='__main__':
    main()
