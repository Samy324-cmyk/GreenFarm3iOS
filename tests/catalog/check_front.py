"""Open the twelve localized Android category cards, compare live SKUs, and buy a toy."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
from zipfile import ZipFile

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]))
from tools.world import entries,table


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for field in ('jar','api','apk','out'):p.add_argument(field,type=Path)
    p.add_argument('--java',default='java')
    mode=p.add_mutually_exclusive_group()
    mode.add_argument('--doghouse',action='store_true',help='Open the guided doghouse shelf in quest 9299')
    mode.add_argument('--first-plot',action='store_true',help='Harvest in a fresh farm and exercise the guided crop purchase')
    a=p.parse_args()
    out=a.out.resolve();out.mkdir(exist_ok=False,parents=True)
    if not a.first_plot:shutil.copytree(HERE.parent/'emulator/fixtures/level15/rms',out/'rms')
    with ZipFile(a.apk) as apk:
        data=entries(apk.read('assets/800x480/13'))
        sets=[]
        for limit,table_id,group_col,order_col,tab in (
            (range(6),0,10,6,1),([6],0,10,6,4),([7],3,34,6,4),([8],4,22,5,4),
            (range(9,12),2,31,5,0),([12],3,34,6,2),([13],4,22,5,3)):
            for cat in limit:
                rows=sorted((row for row in table(data[table_id])[1] if row[group_col]==(0 if cat>=12 else cat)
                             and row[order_col]>=0),key=lambda r:r[order_col])
                pos=cat if cat<6 else cat-6 if cat<9 else cat-9 if cat<12 else -1
                sets.append(' '.join(map(str,[tab,pos,*[r[1] for r in rows]])))
    (out/'shelves.txt').write_text('\n'.join(sets)+'\n',encoding='ascii')
    bench=(HERE.parent/'emulator/TouchBench.java').read_text('utf8')
    (out/'TouchBench.java').write_text(bench.replace('case "quit":','case "shop": MarketFrontProbe.run(t[1]);break;\n'
                                    '            case "quit":'),encoding='utf8')
    api=a.api.resolve()
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(out/'TouchBench.java'),
                    str(HERE/'MarketProbe.java'),str(HERE/'MarketFrontProbe.java')],check=True)
    start=(HERE.parent/'emulator/verify-extractor.txt').read_text().splitlines()[0]
    if a.first_plot:
        first=(HERE.parent/'emulator/verify-harvest.txt').read_text().split('shot 04-primera-cosecha')[0]
        commands=[*first.splitlines(),'shot primera-cosecha','shop seed-plot','shop open-plot','shot familia',
                  'shop select-plot','shot parcela','shop buy-plot','shot colocar','shop place-plot',
                  'shop finish-plot','shot tomates','quit']
        markers=('FIRST_PLOT_CATEGORIES','FIRST_PLOT_SHELF','FIRST_PLOT_OK','FIRST_PLOT_PLACED','FIRST_PLOT_COMPLETE')
    elif a.doghouse:
        commands=[start,'shop seed-house','touch 44 745','shop doghouse','shot casetas','quit']
        markers=('SHOP_TRAINING_OK',)
    else:
        commands=[start,'touch 44 745','wait 850','shot mercado']
        for i in (9,10,11,0,1,2,3,4,5,6,7,12,13,8):
            commands.append(f'shop {i}')
            if i in (0,6,7,8,11):commands.append(f'shot categoria-{i}')
        commands+=['shop buy','shop offers','shot ofertas','quit']
        markers=('SHOP_BUY_OK','SHOP_OFFLINE_OFFERS_OK')
    with (out/'run.log').open('wb') as log:
        proc=subprocess.run([a.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
                 '-Dfile.encoding=ISO_8859_1',f'-Duser.home={out}',f'-Djava.io.tmpdir={out}',
                 '-cp',os.pathsep.join([str(api),str(out)]),'TouchBench',str(a.jar.resolve()),'480','800','0'],
                 cwd=out,input=('\n'.join(commands)+'\n').encode(),stdout=log,stderr=subprocess.STDOUT,timeout=145)
    output=(out/'run.log').read_text('latin1')
    print('\n'.join(l for l in output.splitlines() if l.startswith(('SHOP','FIRST_PLOT'))))
    if proc.returncode or any(marker not in output for marker in markers):
        raise SystemExit(f'Incomplete shop test: {out/"run.log"}')


if __name__=='__main__':main()
