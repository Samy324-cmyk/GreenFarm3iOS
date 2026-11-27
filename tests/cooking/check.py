"""Exercise all recipe categories and starred inventory awards with the actual MIDlet loaded."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for arg in ('game','api','profile'):
        ap.add_argument(arg,type=Path)
    ap.add_argument('--java', default='java')
    args=ap.parse_args()
    profile=args.profile.resolve()
    profile.mkdir(parents=True,exist_ok=False)
    harness=(HERE.parent/'emulator/TouchBench.java').read_text('utf-8')
    harness=harness.replace('case "quit":','case "kitchen": CookingProbe.run(Mobile.getPlatform().loader); break;\n            case "quit":')
    code=profile/'TouchBench.java'
    code.write_text(harness,encoding='utf-8')
    api=args.api.resolve()
    subprocess.run(['javac','--release','17','-classpath',str(api),'-d',str(profile),
                    str(code),str(HERE/'CookingProbe.java')],check=True)
    shutil.copytree(HERE.parent/'emulator/fixtures/level3/rms',profile/'rms')
    cmds=(HERE.parent/'emulator/verify-reload.txt').read_text().split('shot ')[0]+'kitchen\nquit\n'
    with (profile/'run.log').open('wb') as out:
        subprocess.run([args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
                        '-Dfile.encoding=ISO_8859_1',f'-Duser.home={profile}',f'-Djava.io.tmpdir={profile}',
                        '-cp',str(profile)+os.pathsep+str(api),'TouchBench',str(args.game.resolve()),
                        '480','800','0'],cwd=profile,input=cmds.encode(),stdout=out,stderr=subprocess.STDOUT,
                       timeout=120,check=True)
    text=(profile/'run.log').read_text('latin1')
    if 'KITCHEN starred outputs verified' not in text:
        raise ValueError('Missing native recipe verification')
    print('\n'.join(line for line in text.splitlines() if line.startswith('KITCHEN ')))

if __name__=='__main__':
    main()
