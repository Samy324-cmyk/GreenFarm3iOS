"""Exercise a seeded level-ten quest through the native local-neighbor loading screen."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('game','api','out'):
        p.add_argument(name,type=Path)
    p.add_argument('--java',default='java')
    p.add_argument('--commands',type=Path,default=HERE/'encounter.txt')
    modes=p.add_mutually_exclusive_group()
    modes.add_argument('--home',action='store_true')
    modes.add_argument('--adoption',action='store_true')
    modes.add_argument('--chicken',action='store_true')
    modes.add_argument('--raid-save',action='store_true')
    modes.add_argument('--wolf',action='store_true')
    modes.add_argument('--raid-reload',type=Path,metavar='PROFILE')
    modes.add_argument('--home-save',action='store_true')
    modes.add_argument('--home-reload',type=Path,metavar='PROFILE')
    args=p.parse_args()
    out,api=args.out.resolve(),args.api.resolve()
    out.mkdir(parents=True,exist_ok=False)
    seed=args.home_reload or args.raid_reload or HERE.parent/'emulator/fixtures/level3'
    shutil.copytree(seed/'rms',out/'rms')
    harness=(HERE.parent/'emulator/TouchBench.java').read_text('utf8')
    harness=harness.replace('case "quit":','case "home": HomeProbe.run(t[1]); break;\n'
                           '            case "neighbor": NeighborProbe.run(t[1]); break;\n            case "quit":')
    (out/'TouchBench.java').write_text(harness,encoding='utf8')
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(out/'TouchBench.java'),
                    str(HERE/'NeighborProbe.java'),str(HERE/'HomeProbe.java'),str(HERE.parent/'catalog/MarketProbe.java'),
                    str(HERE.parent/'catalog/SceneCacheProbe.java')],check=True)
    ready=(HERE.parent/'emulator/verify-reload.txt').read_text().splitlines()[0]
    home_commands='home seed\nhome intro\nshot zorro\nhome fox\nshot resultado\n'
    if args.chicken:
        commands=ready+'\nhome empty\nhome chicken\nshot granja-con-pollito\nquit\n'
        markers=['HOME_CHICKEN_PLACED']
    elif args.wolf:
        commands=ready+'\nhome wolf\nshot lobo\nhome wolf-attack\nquit\n'
        markers=['HOME_WOLF_READY','HOME_WOLF_WIN']
    elif args.raid_save:
        commands=ready+'\nhome raid\nshot depredador\nclose\nwait 700\nquit\n'
        markers=['HOME_RAID_READY','close']
    elif args.raid_reload:
        commands='wait 6500\nhome raid-reload\nhome raid-win\nhome quota\nquit\n'
        markers=['HOME_RAID_READY','HOME_RAID_WIN','HOME_DAILY_QUOTA']
    elif args.adoption:
        commands=ready+'\nhome adopt\nhome shelf\nwait 400\nshot adopcion\nhome select\nshot colocacion\n'
        commands+='home place\nshot cachorro\n'
        full_adoption=args.commands==HERE/'encounter.txt'
        commands+=(HERE/'adoption.txt' if full_adoption else args.commands).read_text()
        markers=['HOME_ADOPTION_OFFER','HOME_ADOPTED']
        if full_adoption: markers+=['HOME_PUPPY_GROWN','HOME_OK','HOME_REWARD_CLAIMED']
    elif args.home_reload:
        commands='wait 6500\nhome restore\nshot regreso\nhome done\nwait 900\nshot premio\nhome claim\nquit\n'
        markers=['HOME_RELOAD_OK','HOME_OK','HOME_REWARD_CLAIMED']
    elif args.home_save:
        commands=ready+'\n'+home_commands+'close\nwait 700\nquit\n'
        markers=['HOME step=9 menu=19','close']
    elif args.home:
        commands=ready+'\n'+home_commands+'home done\nquit\n'
        markers=['HOME_OK']
    else:
        commands=ready+'\n'+args.commands.read_text()
        markers=['NEIGHBOR_OK']
        if args.commands==HERE/'encounter.txt': markers.append('NEIGHBOR_REWARD_OK')
    with (out/'run.log').open('wb') as stream:
        completed=subprocess.run([args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
            '-Dfile.encoding=ISO_8859_1',f'-Duser.home={out}',f'-Djava.io.tmpdir={out}',
            '-cp',os.pathsep.join([str(out),str(api)]),'TouchBench',str(args.game.resolve()),'480','800','0'],
            cwd=out,input=commands.encode(),stdout=stream,stderr=subprocess.STDOUT,
            timeout=240 if args.adoption else 140)
    log=(out/'run.log').read_text('latin1')
    print('\n'.join(line for line in log.splitlines() if line.startswith(('NEIGHBOR','HOME'))))
    if completed.returncode or any(marker not in log for marker in markers):
        raise SystemExit(f'Encounter test incomplete. Inspect {out/"run.log"}')


if __name__=='__main__':
    main()
