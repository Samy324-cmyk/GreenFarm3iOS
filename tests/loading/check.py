"""Start a new game and compare the native loading screen with the 4.4.4 Android capture."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('jar','api','profile'):
        parser.add_argument(key,type=Path)
    args=parser.parse_args()
    game,api=args.jar.resolve(strict=True),args.api.resolve(strict=True)
    root=args.profile.resolve()
    root.mkdir(parents=True,exist_ok=False)
    ref=(HERE/'android-4.4.4.png').resolve(strict=True)
    original_hash=hashlib.sha256(ref.read_bytes()).hexdigest()
    if original_hash!='497b71cd5d0d162706e7a95a3e49e0e6912d8232c8ff79948dbcaf6bf71db0a8':
        raise ValueError('Unexpected Android 4.4.4 reference screenshot')
    bench=(HERE.parent/'emulator/TouchBench.java').read_text('utf8')
    painter='platform.setPainter(TouchBench::present);'
    if bench.count(painter)!=1:
        raise ValueError('The emulator paint entry changed')
    bench=bench.replace(painter,'LoadingProbe.prepare(System.getProperty("gf3.loadingReference"), args[0]);\n'
        '        platform.setPainter(() -> {LoadingProbe.observe(platform);present();});')
    bench=bench.replace('case "quit":','case "loading": LoadingProbe.await();break;\n            case "quit":')
    driver=root/'TouchBench.java'
    driver.write_text(bench,'utf8')
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(root),str(driver),
                    str(HERE/'LoadingProbe.java')],check=True)
    with (root/'run.log').open('wb') as stream:
        command=['java','-Djava.awt.headless=true','-Djava.security.manager=allow','-Dfile.encoding=ISO_8859_1',
                 f'-Dgf3.loadingReference={ref}',f'-Duser.home={root}',f'-Djava.io.tmpdir={root}',
                 '-cp',os.pathsep.join(map(str,(root,api))),'TouchBench',str(game),'480','800','0']
        subprocess.run(command,cwd=root,input=b'loading\nquit\n',stdout=stream,stderr=subprocess.STDOUT,
                       check=True,timeout=75)
    marker=next(line for line in (root/'run.log').read_text('latin1').splitlines() if line.startswith('LOADING_OK'))
    print(marker,'originalScreenshotSha256='+original_hash)


if __name__=='__main__':
    main()
