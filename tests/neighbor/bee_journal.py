"""Validate honey missions 9302, 9303 and 9305 in the native FreeJ2ME journal."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

HERE=Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('game','api','out'):
        parser.add_argument(name,type=Path)
    parser.add_argument('--java',default='java')
    parser.add_argument('--route',choices=('market','candy','limits'),default='market')
    args=parser.parse_args()
    out=args.out.resolve()
    out.mkdir(exist_ok=False,parents=True)
    api=args.api.resolve(strict=True)
    root=HERE.parent/'emulator'
    seed='level15' if args.route=='candy' else 'level3'
    shutil.copytree(root/'fixtures'/seed/'rms',out/'rms')
    source=(root/'TouchBench.java').read_text(encoding='utf-8')
    target=out/'TouchBench.java'
    target.write_text(source.replace('case "quit":','case "bee": BeeJournalProbe.run(t[1]);break;\n'
                                     '            case "quit":'),encoding='utf-8')
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(target),
                    str(HERE/'BeeJournalProbe.java'),str(HERE.parent/'catalog/MarketProbe.java')],check=True)
    ready=(root/('verify-reload.txt' if seed=='level3' else 'verify-extractor.txt')).read_text().splitlines()[0]
    if args.route=='market':
        script=ready+'\nbee seed\nbee hive\nshot colmena\nbee reward9302\nbee extractor\nshot extractor\nbee reward9303\nquit\n'
        wanted=['BEE_REWARD_OK id=9302','BEE_REWARD_OK id=9303']
    elif args.route=='limits':
        script=ready+'\nbee limits\nquit\n'
        wanted=['HIVE_LIMITS_OK','GROVE_3999_OK']
    else:
        script=ready+'\nbee candy\n'
        script+='\n'.join((root/'verify-extractor.txt').read_text().split('measure')[0].splitlines()[1:])+'\n'
        script+='bee ripen\nwait 1400\nassertstock 121 1\ntouch 437 751\nwait 800\n'
        script+='shot caramelo\nbee reward9305\nbee sell\nshot venta\nquit\n'
        wanted=['BEE_REWARD_OK id=9305','BEE_SOLD_OK']
    cmd=[args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true','-Dfile.encoding=ISO_8859_1',
         f'-Duser.home={out}',f'-Djava.io.tmpdir={out}','-cp',os.pathsep.join([str(out),str(api)]),
         'TouchBench',str(args.game.resolve(strict=True)),'480','800','0']
    log=out/'run.log'
    with log.open('wb') as stream:
        result=subprocess.run(cmd,cwd=out,input=script.encode('ascii'),stdout=stream,
                              stderr=subprocess.STDOUT,timeout=460)
    transcript=log.read_text(encoding='latin1')
    print('\n'.join(line for line in transcript.splitlines() if line.startswith(('BEE','HIVE'))))
    if result.returncode or not all(token in transcript for token in wanted):
        raise SystemExit(f'Bee journal test incomplete. See {log}')


if __name__=='__main__':main()
