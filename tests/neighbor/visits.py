"""Touch-test the offline neighbors unlocked through level 42."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('game','api','out'):
        p.add_argument(key,type=Path)
    p.add_argument('--first',type=int,default=1)
    p.add_argument('--last',type=int,default=9)
    p.add_argument('--java',default='java')
    scenarios=p.add_mutually_exclusive_group()
    scenarios.add_argument('--predator',choices=('fox','wolf','reload'))
    scenarios.add_argument('--mailbox',action='store_true')
    p.add_argument('--rms-from',type=Path)
    args=p.parse_args()
    if not 0 <= args.first <= args.last <= 9:
        p.error('Choose a neighbor row between 0 and 9')
    out,api=args.out.resolve(),args.api.resolve()
    out.mkdir(parents=True,exist_ok=False)
    em=HERE.parent/'emulator'
    shutil.copytree((args.rms_from or em/'fixtures/level3')/'rms',out/'rms')
    source=(em/'TouchBench.java').read_text(encoding='utf8')
    source=source.replace('case "quit":','case "mailbox": MailboxProbe.run(); break;\n            case "restored": VisitsProbe.restored(); break;\n            case "predators": VisitsProbe.predators("wolf".equals(t[1])); break;\n            case "visits": VisitsProbe.run(Integer.parseInt(t[1]),Integer.parseInt(t[2])); break;\n            case "quit":')
    (out/'TouchBench.java').write_text(source,encoding='utf8')
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(out/'TouchBench.java'),
                    str(HERE/'VisitsProbe.java'),str(HERE/'MailboxProbe.java'),str(HERE.parent/'catalog/MarketProbe.java')],check=True)
    ready=(em/'verify-reload.txt').read_text().splitlines()[0]
    procedure=f'predators {args.predator}' if args.predator else f'visits {args.first} {args.last}'
    if args.predator=='reload':
        procedure='restored'
    if args.mailbox:procedure='mailbox'
    commands=f'{ready}\n{procedure}\nquit\n'
    with (out/'run.log').open('wb') as stream:
        run=subprocess.run([args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
            '-Dfile.encoding=ISO_8859_1',f'-Duser.home={out}',f'-Djava.io.tmpdir={out}',
            '-cp',os.pathsep.join([str(out),str(api)]),'TouchBench',str(args.game.resolve()),'480','800','0'],
            cwd=out,input=commands.encode(),stdout=stream,stderr=subprocess.STDOUT,timeout=240)
    log=(out/'run.log').read_text('latin1')
    prefix={'fox':'PREDATOR_VISIT_OK ','wolf':'PREDATOR_VISIT_OK ','reload':'PREDATOR_RELOAD_OK '}.get(args.predator,'VISITA_OK ')
    if args.mailbox:prefix='MAILBOX_OK '
    result=[line for line in log.splitlines() if line.startswith(prefix)]
    print('\n'.join(result))
    if run.returncode or len(result) != (1 if args.predator or args.mailbox else args.last-args.first+1):
        raise SystemExit(f'Incomplete neighbor visits; see {out/"run.log"}')


if __name__=='__main__':
    main()
