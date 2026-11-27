"""Verify catalog stock against a real legacy profile and a second MIDlet launch."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

BENCH = Path(__file__).resolve().parents[1] / 'emulator/TouchBench.java'
COUNTER_ZERO = (-1413816336) & 0xffffffff


def decoded(data, at, n):
    values = []
    for raw, in struct.iter_unpack('<I',data[at:at+4*n]):
        rotated = raw ^ COUNTER_ZERO
        values.append(((rotated >> 9) | (rotated << 23)) & 0xffffffff)
    return values


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('game','emulator','legacy_profile','out'):
        p.add_argument(name,type=Path)
    p.add_argument('--java',default='java')
    p.add_argument('--javac',default='javac')
    a = p.parse_args()
    root = a.out.resolve()
    root.mkdir(parents=True,exist_ok=False)
    shutil.copytree(a.legacy_profile/'rms',root/'rms')
    record, = [p for p in (root/'rms').rglob('*.1') if p.stat().st_size == 51200]
    legacy = record.read_bytes()
    # Native four quest slots, 297 flags, 40 player stat bytes, then silo
    # stock, the five barn groups and the next saved farm subsystem.
    start = 111 + 4*297 + 40
    expected = {}
    for name,size in zip(('silo','p','b','d','a','t'),(6,117,20,63,64,10)):
        expected[name] = decoded(legacy,start,size)
        start += 4*size
    source = BENCH.read_text(encoding='utf-8')
    anchor = 'case "quit":'
    if source.count(anchor)!=1:
        raise ValueError('TouchBench command anchor changed')
    source = source.replace(anchor,'''case "catalog":
            Class<?> engine=Class.forName("a",true,Mobile.getPlatform().loader);
            String[] names={"j","G"};
            for(int slotType=0;slotType<names.length;slotType++) {
                for(java.lang.reflect.Field f:engine.getDeclaredFields()) {
                    if(!f.getName().equals(names[slotType]) || f.getType()!=(slotType==0?int[][].class:int[].class)) continue;
                    f.setAccessible(true);
                    int[][] v=slotType==0?(int[][])f.get(null):new int[][]{(int[])f.get(null)};
                    for(int z=0;z<v.length;z++) {
                        System.out.print("CATALOG "+(slotType==0?new String[]{"p","b","d","a","t"}[z]:"silo"));
                        for(int item:v[z]) System.out.print(" "+Integer.rotateRight(item ^ -1413816336,9));
                        System.out.println();
                    }
                }
            }
            break;
        case "stock":
            Class<?> gameClass=Class.forName("a",true,Mobile.getPlatform().loader);
            for(java.lang.reflect.Method m:gameClass.getDeclaredMethods()) {
                if(m.getReturnType()!=Void.TYPE) continue;
                Class<?>[] types=m.getParameterTypes();
                if(m.getName().equals("d") && java.util.Arrays.equals(types,new Class[]{int.class,int.class,int.class})) {
                    m.setAccessible(true);m.invoke(null,0,117,9);
                }
                if(m.getName().equals("p") && java.util.Arrays.equals(types,new Class[]{int.class,int.class})) {
                    m.setAccessible(true);m.invoke(null,6,5);
                }
            }
            Class<?> presentation=Class.forName("GF3Presentation",true,Mobile.getPlatform().loader);
            java.lang.reflect.Field last=presentation.getDeclaredField("lastSave");last.setAccessible(true);
            long previous=last.getLong(null),deadline=System.currentTimeMillis()+24000L;
            while(last.getLong(null)<=previous && System.currentTimeMillis()<deadline)Thread.sleep(100);
            if(last.getLong(null)<=previous)throw new AssertionError("No 15-second autosave after stock change");
            System.out.println("AUTOSAVE_OK");
            break;
        case "quit":''')
    test = root/'TouchBench.java'
    test.write_text(source,encoding='utf-8')
    emulator = a.emulator.resolve()
    subprocess.run([a.javac,'--release','8','-Xlint:-options','-cp',str(emulator),
                    '-d',str(root),str(test)],check=True)
    cmd = [a.java,'-Djava.security.manager=allow','-Djava.awt.headless=true',
           f'-Duser.home={root}',f'-Djava.io.tmpdir={root}','-Dfile.encoding=ISO_8859_1',
           '-cp',os.pathsep.join([str(root),str(emulator)]),'TouchBench',str(a.game.resolve()),'480','800','0']
    report = []
    for run in (1,2):
        ready = (Path(__file__).resolve().parents[1]/'emulator/verify-reload.txt').read_text().splitlines()[0]
        script = ready + '\ncatalog\n' + ('stock\n' if run==1 else '') + 'quit\n'
        log = root/f'run{run}.log'
        with log.open('wb') as stream:
            subprocess.run(cmd,cwd=root,input=script.encode(),stdout=stream,
                           stderr=subprocess.STDOUT,timeout=105,check=True)
        got = {}
        for line in log.read_text(encoding='latin1').splitlines():
            if line.startswith('CATALOG '):
                _,name,*values = line.split()
                got[name] = list(map(int,values))
        if set(expected)!=set(got):
            raise AssertionError('Missing running-game inventory output')
        for name,old in expected.items():
            if got[name][:len(old)]!=old:
                raise AssertionError(f'Legacy {name} stock changed on launch {run}')
        if (got['p'][117],got['silo'][6]) != ((0,0) if run==1 else (9,5)):
            raise AssertionError('Expanded barn/silo stock was not restored')
        data=record.read_bytes()
        if data[51200:51204]!=b'GFC\1':
            raise AssertionError('Catalog record did not reach the RMS writer')
        report.append({'launch':run,'counts':{k:len(v) for k,v in got.items()},
                       'legacyCountsVerified':sum(map(len,expected.values())),
                       'newBarn':got['p'][117],'newSilo':got['silo'][6]})
    (root/'catalog.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(root/'catalog.json')


if __name__=='__main__':
    main()
