"""Finish the tutorial from a fresh MIDP profile, then reopen the farm in a second JVM."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('jar', 'api', 'out'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--java', default='java')
    args = parser.parse_args()
    game, api, out = args.jar.resolve(), args.api.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = (HERE.parent/'emulator/TouchBench.java').read_text('utf8')
    driver = out/'TouchBench.java'
    driver.write_text(source.replace('case "quit":', 'case "intro": IntroProbe.run(t);break;\n            case "quit":'), encoding='utf8')
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(driver),
                    str(HERE/'IntroProbe.java'),str(HERE/'HarvestScenery.java'),str(HERE.parent/'catalog/SceneCacheProbe.java'),
                    str(HERE.parent/'catalog/MarketProbe.java')], check=True)

    def play(profile, commands):
        log = profile/'run.log'
        with log.open('wb') as stream:
            status = subprocess.run([args.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
                '-Dfile.encoding=ISO_8859_1',f'-Duser.home={profile}',f'-Djava.io.tmpdir={profile}',
                '-cp',os.pathsep.join((str(out),str(api))),'TouchBench',str(game),'480','800','0'],
                cwd=profile,input=(commands+'quit\n').encode('utf8'),stdout=stream,stderr=subprocess.STDOUT,timeout=320)
        output = log.read_text('latin1')
        result = [line for line in output.splitlines() if line.startswith('INTRO_COMPLETE ')]
        if status.returncode or len(result)!=1:
            raise RuntimeError(f'Verifica la partida en {log}')
        return result[0]

    fresh, restored = out/'partida', out/'reapertura'
    fresh.mkdir()
    opening=(HERE.parent/'emulator/verify-harvest.txt').read_text('utf8').split('shot 04-primera-cosecha')[0]
    first,rest=opening.split('\n',1)
    status=play(fresh,first+'\nintro monitor\n'+rest+'shot primer-trigo\nintro play\nintro finish\nclose\nwait 850\n')
    # Validate the immutable LCD saved before the later camera/cache diagnostic runs.
    scenery=subprocess.run([args.java,'-Djava.awt.headless=true','-cp',str(out),'HarvestScenery',
        str(fresh/'primer-trigo.png'),str(HERE/'art-reference'),str(fresh/'03-trigo.png')],capture_output=True,text=True)
    (out/'harvest-scenery.log').write_text(scenery.stdout+scenery.stderr,encoding='utf8')
    if scenery.returncode:
        raise RuntimeError(scenery.stdout+scenery.stderr)
    restored.mkdir()
    shutil.copytree(fresh/'rms',restored/'rms')
    # The restored MIDlet starts asynchronously. Wait for its HUD and farm before reading the journal.
    ready=(HERE.parent/'emulator/verify-reload.txt').read_text('utf8').splitlines()[0]
    if play(restored,ready+'\nintro finish\n')!=status:
        raise RuntimeError('El saldo o la misión cambió después de reiniciar.')
    with (fresh/'transitions.csv').open() as stream:
        rows=[{k:int(v) for k,v in row.items()} for row in csv.DictReader(stream)]
    phases=list(dict.fromkeys(r['tutorial'] for r in rows))
    if phases!=[i for i in range(1,60) if i not in (4,55)]+[-1]:
        raise RuntimeError(f'Recorrido incompleto en transitions.csv: {phases}')
    reward=[r for r in rows if r['tutorial']==36 and r['screen']==26]
    level=[r for r in rows if r['tutorial']==36 and r['screen']==13]
    if not reward or not level or not any((r['level'],r['coins'],r['experience'])==(1,1840,12) for r in reward) or not any(
            (r['level'],r['coins'],r['experience'])==(2,1865,3) for r in level):
        raise RuntimeError('No se verificó el premio de cuatro XP y 25 monedas.')
    report={'jarSha256':hashlib.sha256(game.read_bytes()).hexdigest(),'emulatorSha256':hashlib.sha256(api.read_bytes()).hexdigest(),
            'tutorialStages':phases,'durationFromLetterMs':rows[-1]['elapsed_ms'],
            'firstQuest':9001,'rewardCoins':25,'rewardXP':4,'result':status,'restoredInSecondJVM':True,
            'firstHarvestScenery':scenery.stdout.splitlines()}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(status)


if __name__=='__main__':
    main()
