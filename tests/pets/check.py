"""Buy a collar, enter a name on the touch keyboard and verify it after a cold restart."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('game',type=Path)
    parser.add_argument('emulator',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--java',default='java')
    parser.add_argument('--javac',default='javac')
    parser.add_argument('--lesson',action='store_true',help='Play quest 9299 and claim its reward')
    parser.add_argument('--lesson-from',type=Path,metavar='PROFILE',help='Resume the saved toy lesson')
    args=parser.parse_args()
    here=Path(__file__).resolve().parent
    bench=here.parent/'emulator'
    output=args.output.resolve()
    output.mkdir(parents=True,exist_ok=False)
    source=(bench/'TouchBench.java').read_text(encoding='utf-8')
    anchor='case "quit":'
    if source.count(anchor)!=1: raise ValueError('Unexpected emulator command loop')
    commands='''case "lesson":LessonProbe.run(t[1]);break;
            case "petscreen":PetProbe.ready(platform.loader,Integer.parseInt(t[1]));break;
            case "petcollar":PetProbe.collar(platform.loader);break;
            case "petcheck":PetProbe.check(platform.loader);break;
            '''
    driver=output/'TouchBench.java'
    driver.write_text(source.replace(anchor,commands+anchor),encoding='utf-8')
    emulator=args.emulator.resolve(strict=True)
    subprocess.run([args.javac,'--release','8','-Xlint:-options','-cp',str(emulator),
                    '-d',str(output),str(driver),str(here/'PetProbe.java'),str(here/'LessonProbe.java'),
                    str(here.parent/'catalog/MarketProbe.java')],check=True)
    # Delete the default name, type Sol with Shift and accept both dialogs.
    presses=[(135,705)]*5+[(138,88),(214,160),(138,88),(294,660),(214,711)]
    edit=''.join(f'touch {x} {y}\nwait 200\n' for x,y in presses)
    ready=(bench/'verify-reload.txt').read_text(encoding='utf-8').splitlines()[0]+'\n'
    first=(ready+'petscreen 17\npetcollar\npetscreen 49\n'+edit+
           'shot nombre\ntouch 60 661\npetscreen 19\nshot confirmado\n'
           'touch 68 598\npetscreen 17\npetcheck\nquit\n')
    previous=bench/'fixtures/level3'
    stages=[('edit',first),('reload',ready+'petscreen 17\npetcheck\nshot granja\nquit\n')]
    if args.lesson or args.lesson_from:
        stages=[('gifts',ready+'petscreen 17\nlesson seed\nlesson house\nshot caseta\nlesson ball\n'
                       'shot pelota\nclose\nwait 550\nquit\n'),
                ('play','wait 7000\npetscreen 17\nlesson play\nshot premio\nquit\n')]
        if args.lesson_from:
            previous=args.lesson_from
            stages=stages[1:]
    for stage,script in stages:
        profile=output/stage
        profile.mkdir()
        shutil.copytree(previous/'rms',profile/'rms')
        command=[args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
                 '-Dfile.encoding=ISO_8859_1',f'-Duser.home={profile}',f'-Djava.io.tmpdir={profile}',
                 '-cp',os.pathsep.join((str(output),str(emulator))),'TouchBench',
                 str(args.game.resolve(strict=True)),'480','800','0']
        log=profile/'run.log'
        with log.open('wb') as stream:
            status=subprocess.run(command,cwd=profile,input=script.encode('ascii'),
                                  stdout=stream,stderr=subprocess.STDOUT,timeout=120)
        marker={'gifts':'LESSON_BALL_OK','play':'LESSON_REWARD_OK'}.get(stage,'PET_NAME_OK')
        if status.returncode or marker not in log.read_text(encoding='latin1'):
            raise RuntimeError(f'Pet test failed in {stage}, see {log}')
        previous=profile
    print('Misión 9299 verificada en FreeJ2ME.' if args.lesson or args.lesson_from else
          'Mascota y nombre verificados en dos sesiones de FreeJ2ME.')


if __name__=='__main__':
    main()
