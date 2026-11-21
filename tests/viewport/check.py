"""Read the first letter and harvest wheat by touching a real high-resolution MIDP display."""
import argparse
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('jar','api','out'):
        parser.add_argument(name,type=Path)
    parser.add_argument('--size',choices=('1280x720','720x1280','1920x1080','800x480'),default='1280x720')
    parser.add_argument('--java',default='java')
    a=parser.parse_args()
    out=a.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    bench=HERE.parent/'emulator'
    source=(bench/'TouchBench.java').read_text('utf8')
    anchor='case "quit":'
    assert source.count(anchor)==1
    driver=out/'TouchBench.java'
    driver.write_text(source.replace(anchor,'case "viewport": ViewportProbe.check();break;\n'+anchor),encoding='utf8')
    api=a.api.resolve()
    subprocess.run(['javac','--release','17','-cp',str(api),'-d',str(out),str(driver),str(HERE/'ViewportProbe.java')],check=True)
    commands=(bench/'verify-harvest.txt').read_text().split('measure')[0].replace('\ntouch ','\ntouchlogical ')
    if a.size!='800x480':
        # Press in a black bar, drag to the letter's button and release there.
        # The next glyph check confirms that this entire gesture was ignored.
        width,height=map(int,a.size.split('x'))
        if width>height:
            dw=height*800//480
            x=(width-dw)//2+(604*dw+799)//800
            y=((479-92)*height+479)//480
        else:
            dh=width*800//480
            x=(92*width+479)//480
            y=(height-dh)//2+(604*dh+799)//800
        first=commands.splitlines()[0]
        commands=commands.replace(first+'\n',first+f'\ndrag 0 0 {x} {y} 8 25\nwait 200\n'+first+'\n',1)
    commands+='viewport\nquit\n'
    with (out/'run.log').open('wb') as log:
        result=subprocess.run([a.java,'-Xmx384m','-Djava.security.manager=allow','-Djava.awt.headless=true',
            '-Dgf3.bench.glyphSeconds=60','-Dfile.encoding=ISO_8859_1',
            '-Duser.home='+str(out),'-Djava.io.tmpdir='+str(out),'-cp',os.pathsep.join([str(out),str(api)]),
            'TouchBench',str(a.jar.resolve()),*a.size.split('x'),'0'],cwd=out,
            input=commands.encode(),stdout=log,stderr=subprocess.STDOUT,timeout=150)
    log=(out/'run.log').read_text('latin1')
    if result.returncode or 'VIEWPORT_OK' not in log or not (out/'04-primera-cosecha.png').is_file():
        raise RuntimeError('Incomplete HD touch or pixel comparison: '+str(out/'run.log'))
    print(next(line for line in log.splitlines() if line.startswith('VIEWPORT_OK')))


if __name__=='__main__':
    main()
