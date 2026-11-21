"""Map Android's pause panels onto the touch menu dispatcher and local text resources."""
import json
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory

from .expansion.neighbor import expose
from .expansion.hives import patch_code
from .hud_art import PAUSE_ALIAS
from .mexican_spanish import adapt
from .timing.classfile import ClassFile,code_parts,convert_helper,pack_code,u2
from .world import entries,labels,pack


def rows(data,android):
    sizes={201:17,202:18,203:22,204:26,205:31,206:20,207:21,208:9,209:15}
    result=[];pos=1
    while pos<len(data):
        kind=data[pos]
        size=sizes[kind]+int(android and kind in (204,205))
        result.append(data[pos:pos+size]);pos+=size
    if pos!=len(data):raise ValueError('Incomplete menu controls')
    return result


def control(data):
    row=bytearray(data)
    if row[0]==204:
        del row[-1];row[7]=13
    elif row[0]==205:
        sheet=row[8];frame=struct.unpack_from('<H',row,9)[0]
        if sheet==20:
            if frame in PAUSE_ALIAS:frame=PAUSE_ALIAS[frame]
            elif frame not in (122,147):raise ValueError(f'Unmapped pause frame {frame}')
        if frame>255:raise ValueError('Control frame exceeds MIDP limits')
        del row[10];row[9]=frame
    return row


def panel(data,android):
    menus=entries(data);source=entries(android)
    old=rows(menus[15],False);pause=rows(source[15],True);language=rows(source[26],True)
    if len(old)!=151 or len(pause)!=166 or len(language)!=47:raise ValueError('Unknown pause release')
    by={int.from_bytes(row[1:3],'little'):i for i,row in enumerate(old)}
    for i in (*range(64),162,163,164,165):
        row=pause[i]
        index=by.get(int.from_bytes(row[1:3],'little'))
        if i==43:index=39  # Sound heading has a new editor ID.
        if index is not None:old[index]=control(row)
    old[3][-1]=1  # Wrap the long Mexican customer care label in its source rectangle.
    # Keep MIDP control indices stable for its native event switch.
    # Cookies and Terms, then the installed Latin American language choice.
    for row in (pause[12],pause[11],pause[13],pause[14],
                language[1],language[38],language[39],language[40],language[45],language[46],
                pause[64],pause[65]):
        old.append(control(row))
    # Keep the original center of the 123px button and fit "CONTACTOS"
    # into its full face with the MIDP bitmap font.
    struct.pack_into('<h',old[162],3,636)
    struct.pack_into('<h',old[162],8,122)
    old[162][-1]=0
    menus[15]=menus[15][:1]+b''.join(old)
    return pack(menus)


def wrap(game,name,desc,alias,target):
    for i,(flags,n,d,attrs) in enumerate(game.methods):
        if (game.string(n),game.string(d))!=(name,desc):continue
        game.methods[i]=flags&~2,game.utf(alias),d,attrs
        args=b'\x1a' if '(I)' in desc else b''
        ret=b'\xac' if desc.endswith('Z') else b'\xb1'
        code=args+b'\xb8'+u2(game.ref('GF3Pause',target,desc))+ret
        game.methods.append((flags,n,d,[(game.utf('Code'),pack_code(u2(1)+u2(len(args)),code,u2(0),[]))]))
        return
    raise ValueError(f'Missing pause entry {name}{desc}')


def credits(game,words):
    lines=[]
    for i in range(11264,11264+295):
        if i==11538:lines.extend(words[j] for j in range(11563,11563+184))
        lines.append(words[i]+(' 4.4.4' if i==11265 else ''))
    text='\n'.join(lines)+'\n'
    if '\0' in text or any(ord(c)>65535 for c in text):raise ValueError('Unknown credits character')
    s=game.intern(b'\x08'+u2(game.utf(text)))
    for _,n,d,attrs in game.methods:
        if (game.string(n),game.string(d))!=('dG','()V'):continue
        for i,(tag,body) in enumerate(attrs):
            if game.string(tag)!='Code':continue
            header,raw,exceptions,extras=code_parts(body)
            if raw[24]!=179 or raw[30:33]!=b'\x11\x01\x16' or raw[219]!=178:
                raise ValueError('Unsupported scrolling credits')
            # Preserve the native line measurements and credit-scroll limits.
            setup=b'\x13'+u2(s)+raw[24:27]+raw[219:222]+b'\xb0'
            game.methods.append((10,game.utf('gf3PauseCredits'),game.utf('()[[[S'),
                [(game.utf('Code'),pack_code(u2(1)+u2(0),setup,u2(0),[]))]))
            raw=raw[:30]+b'\x11\0\0'+raw[33:219]+b'\xb8'+u2(game.ref('a','gf3PauseCredits','()[[[S'))+raw[222:]
            attrs[i]=tag,pack_code(header,raw,exceptions,extras)
            return
    raise ValueError('Missing credits screen')


def patch_pause(classes,apk,api):
    game=ClassFile(classes['a.class'])
    # ASprite.M1 uses the Android device profile's 3000-entry layout buffer
    # for the full scrolling credits, including the studio attribution list.
    sprite=ClassFile(classes['e.class'])
    patch_code(sprite,'a','(Ljava/lang/String;IZ)[S',[(6,b'\x11\x04\x4c',b'\x11\x0b\xb8')])
    # The MIDlet's flattened button cache has one slot per frame in sheet
    # 20, including the Android buttons appended beyond the original 199.
    limit=max(PAUSE_ALIAS.values())+1
    for method,offsets in [('fC',(40,49)),('v',(73,))]:
        patch_code(game,method,'()V',[(i,b'\x11\x00\xc8',b'\x11'+u2(limit)) for i in offsets])
    expose(game,game.fields,{('a','[[Ljava/lang/String;'),('J','Z'),('N','Z'),('L','Z'),('et','I')})
    expose(game,game.methods,{('a','(IIZ)V'),('b','(IIZ)V'),('H','(I)V'),
                              ('gf','()V'),('l','(Z)V'),('gE','()V')})
    for name,desc,alias,target in [('eH','()V','gf3PauseOpen','open'),
            ('eI','()V','gf3PauseLeave','leave'),('eK','()V','gf3PauseOptions','options'),
            ('eL','()V','gf3PauseCloseOptions','closeOptions'),('I','(I)V','gf3PauseInput','input'),
            ('z','(I)Z','gf3PausePhase','phase')]:
        wrap(game,name,desc,alias,target)
    word=b'\xb8'+u2(game.ref('g','c','(I)Ljava/lang/String;'))
    for method,desc,refs in [('gf3PausePhase','(I)Z',[(849,'heading'),(999,'body')]),
                              ('gE','()V',[(24,'body')])]:
        patch_code(game,method,desc,[(p,word,b'\xb8'+u2(game.ref('GF3Pause',fn,'(I)Ljava/lang/String;'))) for p,fn in refs])
    lib=Path(__file__).resolve().parents[1]/'src/catalog/GF3Pause.java'
    words=labels(apk.read('assets/800x480/LATAM'))
    credits(game,words)
    with TemporaryDirectory() as scratch:
        p=Path(scratch);stub=p/'a.java'
        stub.write_text('''class a {static boolean J,N,L;static int et;static String[][] captions;
          static void a(int p,int i,boolean v){} static void b(int p,int i,boolean v){}
          static void H(int p){} static void gf(){} static void l(boolean v){}static void gE(){}
          static void gf3PauseOpen(){} static void gf3PauseLeave(){} static void gf3PauseOptions(){}
          static void gf3PauseCloseOptions(){} static void gf3PauseInput(int i){}
          static boolean gf3PausePhase(int p){return false;}}
          class g {static javax.microedition.lcdui.Graphics screen;}
          class GF3FarmAudio {static void original(int cue){}}
          class GF3Zoom {static boolean onePointer(){return true;}static String choice(){return "";}
          static void toggle(){}}''',encoding='ascii')
        textsrc=p/'GF3PauseWords.java'
        # cGame.Gs/Es/Bq use this ordering. The restricted offline profile
        # skips Parties and substitutes the original local age-neutral pages.
        topic=[n for n in range(10240,10278,2) if n!=10252]+[12364,12366,12401]
        bodies=[adapt(words[{10244:12412,10270:12468}.get(n,n+1)]).replace('%1','') for n in topic]
        tables=''.join('static final String[] '+key+'={'+','.join(json.dumps(line,ensure_ascii=True) for line in seq)+'};'
                       for key,seq in [('headings',[adapt(words[n]) for n in topic]),('pages',bodies)])
        textsrc.write_text('class GF3PauseWords {'+tables+''.join(
            'static final String '+key+'='+json.dumps(words[idx],ensure_ascii=True)+';'
            for key,idx in [('support',65),('cookies',861),('terms',868),('contact',12533),
                            ('language',77),('back',45),('offline',1008)])+'}',encoding='ascii')
        subprocess.run(['javac','--release','8','-cp',str(api),'-g:none','-d',str(p),str(stub),str(textsrc),str(lib)],check=True)
        helper=ClassFile((p/'GF3Pause.class').read_bytes())
        helper.pool[helper.utf('captions')]=helper.pool[helper.utf('a')]
        helper.pool[helper.utf('screen')]=helper.pool[helper.utf('a')]
        return {'a.class':game.bytes(),'e.class':sprite.bytes(),'GF3Pause.class':convert_helper(helper.bytes()),
                'GF3PauseWords.class':convert_helper((p/'GF3PauseWords.class').read_bytes()),
                '6':panel(classes['6'],apk.read('assets/800x480/10'))}
