"""Route the reference edition's five outgoing platform calls to its offline paths."""
from .timing.classfile import ClassFile, code_parts, instruction_offsets, pack_code, u2


def preserve_rms_version(game, version):
    # The original MIDlet used its marketing version as the binary save format.
    # Keep reading and writing that format after changing the installer's version.
    cf = ClassFile(game)
    for _, name, desc, attributes in cf.methods:
        if (cf.string(name),cf.string(desc)) != ('u','()I'):
            continue
        for index,(tag,body) in enumerate(attributes):
            if cf.string(tag) != 'Code':
                continue
            header,code,exceptions,extras = code_parts(body)
            if code[0]!=0xb2 or code[3]!=0x12 or code[5]!=0xb6 or code[8]!=0x4b:
                raise ValueError('Unexpected RecordStore version reader')
            key=cf.pool[code[4]]
            if key[0]!=8 or cf.string(int.from_bytes(key[1:],'big'))!='MIDlet-Version':
                raise ValueError('Unknown RecordStore version property')
            word=cf.intern(b'\x08'+u2(cf.utf(version)))
            code=b'\x13'+u2(word)+bytes(5)+code[8:]
            attributes[index]=tag,pack_code(header,code,exceptions,extras)
            return cf.bytes()
    raise ValueError('Missing RecordStore format reader')


def disconnect(jar, classes):
    replacements = {}
    for filename in ('a.class','c.class','d.class','g.class','m.class'):
        data = classes[filename] if filename in classes else jar.read(filename)
        cf = ClassFile(data)
        changed = 0
        external = filename not in ('c.class','d.class')
        if external:
            owner, method = 'javax/microedition/midlet/MIDlet','platformRequest'
            descriptor = '(Ljava/lang/String;)Z'
            offline_desc = '(Ljavax/microedition/midlet/MIDlet;Ljava/lang/String;)Z'
            arg_count = 2
        else:
            owner, method = 'javax/microedition/io/Connector','open'
            arg_count = 1 if filename=='c.class' else 2
            descriptor = '(Ljava/lang/String;'+('I' if arg_count==2 else '')+')Ljavax/microedition/io/Connection;'
            offline_desc = descriptor
        original = bytes([0xb6 if external else 0xb8])+u2(cf.ref(owner,method,descriptor))
        local = b'\xb8'+u2(cf.ref(filename[:-6],'gf3Offline',offline_desc))
        for _,_,_,attrs in cf.methods:
            for i,(tag,body) in enumerate(attrs):
                if cf.string(tag)!='Code':
                    continue
                header,raw,exc,extra = code_parts(body)
                code=bytearray(raw)
                for pc in instruction_offsets(raw):
                    if raw[pc:pc+3]==original:
                        code[pc:pc+3]=local
                        changed+=1
                attrs[i]=tag,pack_code(header,code,exc,extra)
        if changed!=1:
            raise ValueError(f'Unexpected external connection in {filename}')
        # Each original caller already handles a platform that cannot open
        # this URL. Purchases and invitations retain their failure results.
        failed='javax/microedition/io/ConnectionNotFoundException'
        body=b'\xbb'+u2(cf.cls(failed))+b'\x59\xb7'+u2(cf.ref(failed,'<init>','()V'))+b'\xbf'
        cf.methods.append((10,cf.utf('gf3Offline'),cf.utf(offline_desc),[(cf.utf('Code'),
            pack_code(u2(2)+u2(arg_count),body,u2(0),[]))]))
        replacements[filename]=cf.bytes()
    name='META-INF/MANIFEST.MF'
    fields=jar.read(name).decode('utf8').splitlines()
    fields=[line for line in fields if line and not line.startswith(
        ('MIDlet-Permissions:','MIDlet-Delete-Confirm:','MIDlet-Info-URL:','SiteURL:'))]
    version=next(line for line in fields if line.startswith('MIDlet-Version: '))
    replacements['a.class']=preserve_rms_version(replacements['a.class'],version.split(': ',1)[1])
    fields[fields.index(version)]='MIDlet-Version: 4.4.4'
    fields.append('MIDlet-Description: Green Farm 3 para Java ME sin conexión (es-MX).')
    replacements[name]=('\r\n'.join(fields)+'\r\n\r\n').encode('utf8')
    return replacements


def verify_offline(jar):
    blocked = 0
    for name in jar.namelist():
        if not name.endswith('.class'):
            continue
        cf=ClassFile(jar.read(name))
        outbound=set()
        for i,ref in enumerate(cf.pool):
            if not ref or ref[0] not in (10,11):
                continue
            owner=cf.pool[int.from_bytes(ref[1:3],'big')]
            signature=cf.pool[int.from_bytes(ref[3:],'big')]
            classname=cf.string(int.from_bytes(owner[1:],'big'))
            method=cf.string(int.from_bytes(signature[1:3],'big'))
            if classname=='javax/microedition/io/Connector' or method=='platformRequest':
                outbound.add(i)
        for _,n,_,attrs in cf.methods:
            if cf.string(n)=='gf3Offline':
                blocked+=1
            for tag,body in attrs:
                if cf.string(tag)!='Code':
                    continue
                code=code_parts(body)[1]
                for pc in instruction_offsets(code):
                    if 0xb6<=code[pc]<=0xb9 and int.from_bytes(code[pc+1:pc+3],'big') in outbound:
                        raise ValueError(f'External platform call in {name}')
    if blocked!=5 or b'MIDlet-Permissions:' in jar.read('META-INF/MANIFEST.MF'):
        raise ValueError('Incorrect offline platform configuration')
