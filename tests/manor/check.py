"""Exercise all nine manor renovations and reopen their saved state in FreeJ2ME."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from tools.world import entries, table

BUILDINGS = (2, 0, 3, 1, 4, 5, 6, 7, 8)
QUESTS = (0, 4, 5, 6, 7, 8, 9, 10, 11)
SCENARIOS = ('first', 'estate', 'attic', 'reopened')


def write_rows(path, rows):
    path.write_text(''.join(' '.join(map(str, row)) + '\n' for row in rows), encoding='ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('jar', 'api', 'apk', 'out', 'profile'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--java', default='java')
    parser.add_argument('--only', choices=SCENARIOS, help='Run a single scenario with its matching saved farm')
    args = parser.parse_args()
    out, api, game = args.out.resolve(), args.api.resolve(), args.jar.resolve()
    out.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(args.apk) as apk:
        tables = entries(apk.read('assets/800x480/13'))
    buildings, journal, prices = (table(tables[i])[1] for i in (3, 6, 32))
    rooms = [[buildings[i][c] for c in (1, 7, 13, 20, 33)] for i in BUILDINGS]
    quests = [[journal[i][c] for c in (1, 13, 14, 15, 8, 9)] for i in QUESTS]
    speeds = [[r[2], r[1]] for r in prices]

    bench = (HERE.parent/'emulator/TouchBench.java').read_text('utf8')
    entry = 'case "manor": ManorProbe.run(t[1]);break;\n            case "quit":'
    driver = out/'TouchBench.java'
    driver.write_text(bench.replace('case "quit":', entry), encoding='utf8')
    subprocess.run(['javac', '--release', '17', '-cp', str(api), '-d', str(out), str(driver),
                    str(HERE/'ManorProbe.java'), str(HERE.parent/'catalog/MarketProbe.java')], check=True)

    def play(name, previous):
        folder = out/name
        folder.mkdir()
        shutil.copytree(previous/'rms', folder/'rms')
        write_rows(folder/'rooms.txt', rooms)
        write_rows(folder/'quests.txt', quests)
        write_rows(folder/'speeds.txt', speeds)
        log = folder/'run.log'
        with log.open('wb') as stream:
            process = subprocess.run([
                args.java, '-Xmx384m', '-Djava.security.manager=allow', '-Djava.awt.headless=true',
                '-Dfile.encoding=ISO_8859_1', f'-Duser.home={folder}', f'-Djava.io.tmpdir={folder}',
                '-cp', os.pathsep.join((str(out), str(api))), 'TouchBench', str(game), '480', '800', '0'
            ], cwd=folder, input=f'wait 500\nmanor ready\nmanor {name}\nclose\nwait 700\nquit\n'.encode(),
                stdout=stream, stderr=subprocess.STDOUT, timeout=300)
        if process.returncode:
            raise RuntimeError(f'Revisa {log}')
        return folder

    if args.only:
        play(args.only, args.profile)
        return
    previous = args.profile
    logs = {}
    for name in SCENARIOS:
        previous = play(name, previous)
        logs[name] = (previous/'run.log').read_text('latin1').splitlines()

    def result(which, key):
        return next(line[len(key)+1:] for line in logs[which] if line.startswith(key+' '))

    started = result('estate', 'MANOR_CLOCK_STARTED')
    if started != result('attic', 'MANOR_CLOCK_LOADED'):
        raise AssertionError('El reloj o la compra del ático cambió al reiniciar.')
    finished = result('attic', 'MANOR_FINAL')
    if finished != result('reopened', 'MANOR_FINAL'):
        raise AssertionError('Cambió el saldo al reabrir la mansión terminada.')
    purchases = [line for mode in ('first', 'estate') for line in logs[mode] if line.startswith('MANOR_PURCHASE ')]
    if len(purchases) != 9:
        raise AssertionError('Faltan habitaciones.')
    report = {
        'jarSha256': hashlib.sha256(game.read_bytes()).hexdigest(),
        'rooms': [{'building': r[0], 'priceCoins': r[1], 'buildingXP': r[2], 'seconds': r[3]*60,
                   'deedIndex': r[4], 'quest': q[0], 'questXP': q[4], 'questCoins': q[5]}
                  for r, q in zip(rooms, quests)],
        'savedAtticStartSecondsDurationCoinsBills': list(map(int, started.split())),
        'finalRoomsCoinsBillsExperience': list(map(int, finished.split())),
        'reopenedInFourthJVM': True,
        'setup': 'La cocina usa la granja ganada en el tutorial. Después se otorgan nivel, fondos, terrenos y misiones ajenas a la mansión.',
        'source': 'Android 4.4.4, tablas 3 (edificios), 6 (misiones) y 32 (costo de acelerar).',
    }
    (out/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print('MANOR_OK', len(purchases), finished)


if __name__ == '__main__':
    main()
