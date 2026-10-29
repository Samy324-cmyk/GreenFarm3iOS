"""Read original DEX instructions for deterministic Dart code generation.

No DEX code is executed. Reference: Android Open Source Project DEX format
and Dalvik bytecode format. Offsets in code items are 16-bit code units.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, struct, zipfile
from pathlib import Path


class Dex:
    def __init__(self, data):
        self.data=data
        if data[:4]!=b'dex\n' or data[7]!=0 or self.u32(36)!=112:
            raise ValueError('Unsupported DEX header')
        if self.u32(32)!=len(data) or self.u32(40)!=0x12345678:
            raise ValueError('DEX size/endian mismatch')
        if hashlib.sha1(data[32:]).digest()!=data[12:32]:
            raise ValueError('DEX signature mismatch')
        self.strings=[]
        count,offset=self.pair(56)
        for i in range(count):
            size,p=self.uleb(self.u32(offset+4*i))
            units=[]
            while data[p]:
                b=data[p];p+=1
                if b<0x80: units.append(b)
                elif b&0xe0==0xc0:
                    units.append(((b&31)<<6)|(data[p]&63));p+=1
                elif b&0xf0==0xe0:
                    units.append(((b&15)<<12)|((data[p]&63)<<6)|(data[p+1]&63));p+=2
                else: raise ValueError('Invalid modified UTF-8')
            if len(units)!=size:raise ValueError('MUTF8 UTF16 size mismatch')
            self.strings.append(struct.pack('<'+'H'*len(units),*units).decode('utf-16-le','surrogatepass'))
        count,offset=self.pair(64)
        self.types=[self.strings[self.u32(offset+4*i)] for i in range(count)]
        count,offset=self.pair(72)
        self.protos=[]
        for i in range(count):
            _,ret,params=struct.unpack_from('<III',data,offset+12*i)
            types=self.type_list(params)
            self.protos.append({'return':self.types[ret],'parameters':types,'descriptor':'('+''.join(types)+')'+self.types[ret]})
        count,offset=self.pair(80)
        self.fields=[]
        for i in range(count):
            owner,kind,name=struct.unpack_from('<HHI',data,offset+8*i)
            self.fields.append({'owner':self.types[owner],'type':self.types[kind],'name':self.strings[name]})
        count,offset=self.pair(88)
        self.methods=[]
        for i in range(count):
            owner,proto,name=struct.unpack_from('<HHI',data,offset+8*i)
            info={'owner':self.types[owner],'name':self.strings[name],**self.protos[proto]}
            info['key']=info['owner']+'->'+info['name']+info['descriptor']
            self.methods.append(info)

    def u32(self,p):return struct.unpack_from('<I',self.data,p)[0]
    def pair(self,p):return struct.unpack_from('<II',self.data,p)
    def uleb(self,p):
        value=0
        for i in range(5):
            b=self.data[p];p+=1;value|=(b&127)<<(7*i)
            if b<128:return value,p
        raise ValueError('Invalid LEB128')
    def sleb(self,p):
        value=0
        for i in range(5):
            b=self.data[p];p+=1;value|=(b&127)<<(7*i)
            if b<128:
                if b&64:value|=-(1<<(7*(i+1)))
                return value,p
        raise ValueError('Invalid signed LEB128')
    def type_list(self,p):
        if p==0:return []
        count=self.u32(p)
        return [self.types[t] for t in struct.unpack_from('<'+'H'*count,self.data,p+4)]
    def encoded(self,p):
        tag=self.data[p];p+=1;kind=tag&31;n=(tag>>5)+1
        if kind==0x1e:return None,p
        if kind==0x1f:return int(tag>>5),p
        if kind==0x1c:
            count,p=self.uleb(p);items=[]
            for _ in range(count):value,p=self.encoded(p);items.append(value)
            return {'array':items},p
        if kind==0x1d:
            typ,p=self.uleb(p);count,p=self.uleb(p);items={}
            for _ in range(count):
                name,p=self.uleb(p);value,p=self.encoded(p);items[self.strings[name]]=value
            return {'annotation':self.types[typ],'values':items},p
        value=int.from_bytes(self.data[p:p+n],'little',signed=kind in (0,2,4,6));p+=n
        if kind in (0,2,3,4,6):return value,p
        if kind==0x10:return {'float_bits':value<<(8*(4-n))},p
        if kind==0x11:return {'double_bits':value<<(8*(8-n))},p
        if kind==0x17:return self.strings[value],p
        if kind==0x18:return {'class':self.types[value]},p
        if kind in (0x19,0x1b):return {'field':self.fields[value]},p
        if kind==0x1a:return {'method':self.methods[value]},p
        if kind==0x15:return {'method_type':self.protos[value]},p
        if kind==0x16:return {'method_handle':value},p
        raise ValueError(f'Unknown encoded value {kind:x}')

    def classes(self):
        count,offset=self.pair(96)
        for i in range(count):
            typ,flags,parent,interfaces,source,annotations,class_data,static_values=struct.unpack_from('<8I',self.data,offset+32*i)
            info={'name':self.types[typ],'access':flags,'super':self.types[parent] if parent!=0xffffffff else None,'interfaces':self.type_list(interfaces),'source':self.strings[source] if source!=0xffffffff else None,'static_fields':[],'instance_fields':[],'methods':[]}
            if class_data:
                p=class_data;counts=[]
                for _ in range(4):n,p=self.uleb(p);counts.append(n)
                for group,n in zip(('static_fields','instance_fields'),counts[:2]):
                    index=0
                    for _ in range(n):
                        delta,p=self.uleb(p);index+=delta;access,p=self.uleb(p)
                        info[group].append({**self.fields[index],'access':access})
                for n in counts[2:]:
                    index=0
                    for _ in range(n):
                        delta,p=self.uleb(p);index+=delta;access,p=self.uleb(p);code,p=self.uleb(p)
                        info['methods'].append({**self.methods[index],'access':access,'code':self.code(code) if code else None})
            if static_values:
                count,p=self.uleb(static_values)
                if count>len(info['static_fields']):raise ValueError('Static field count mismatch')
                for k in range(count):
                    value,p=self.encoded(p);info['static_fields'][k]['value']=value
            yield info

    def code(self,p):
        registers,inputs,outputs,tries,debug,size=struct.unpack_from('<4H2I',self.data,p)
        words=list(struct.unpack_from('<'+'H'*size,self.data,p+16))
        result={'offset':p,'registers':registers,'inputs':inputs,'outputs':outputs,'words':words,'instructions':self.instructions(words),'tries':[]}
        if tries:
            t=p+16+size*2+(2 if size&1 else 0);handlers=t+tries*8
            for i in range(tries):
                start,length,handler=struct.unpack_from('<IHH',self.data,t+8*i)
                n,q=self.sleb(handlers+handler);items=[]
                for _ in range(abs(n)):
                    kind,q=self.uleb(q);address,q=self.uleb(q)
                    items.append({'type':self.types[kind],'target':address})
                if n<=0:
                    address,q=self.uleb(q);items.append({'type':None,'target':address})
                result['tries'].append({'start':start,'end':start+length,'handlers':items})
        return result

    def instructions(self,words):
        result=[];pc=0
        while pc<len(words):
            word=words[pc];op=word&255;form=FORMATS[op]
            if op==0 and word:
                if word==0x100:length=4+words[pc+1]*2
                elif word==0x200:length=2+words[pc+1]*4
                elif word==0x300:length=4+(words[pc+1]*(words[pc+2]|words[pc+3]<<16)+1)//2
                else:raise ValueError(f'Unknown payload {word:x}')
                form='payload'
            else:
                if form is None:raise ValueError(f'Unsupported opcode {op:x}')
                length=int(form[0])
            if pc+length>len(words):raise ValueError('Instruction outside method')
            item={'pc':pc,'op':op,'format':form,'words':words[pc:pc+length]}
            if op in (0x1a,0x1b):
                index=words[pc+1] | (words[pc+2]<<16 if op==0x1b else 0)
                item['string']=self.strings[index]
            elif op in (0x1c,0x1f,0x20,0x22,0x23,0x24,0x25):item['type']=self.types[words[pc+1]]
            elif 0x52<=op<=0x6d:item['field']=self.fields[words[pc+1]]
            elif 0x6e<=op<=0x72 or 0x74<=op<=0x78:item['method']=self.methods[words[pc+1]]
            result.append(item);pc+=length
        return result


FORMATS=[None]*256
def put(ops,form):
    for op in ops:FORMATS[op]=form
put([0,0x0e],'10x')
put([1,4,7,0x21]+list(range(0x7b,0x90))+list(range(0xb0,0xd0)),'12x')
put([2,5,8],'22x');put([3,6,9],'32x')
put(list(range(0xa,0xe))+[0xf,0x10,0x11,0x1d,0x1e,0x27],'11x')
put([0x12],'11n');put([0x13,0x16],'21s');put([0x14,0x17],'31i')
put([0x15,0x19],'21h');put([0x18],'51l')
put([0x1a,0x1c,0x1f,0x22]+list(range(0x60,0x6e)),'21c')
put([0x1b],'31c');put([0x20,0x23]+list(range(0x52,0x60)),'22c')
put([0x24]+list(range(0x6e,0x73)),'35c');put([0x25]+list(range(0x74,0x79)),'3rc')
put([0x26,0x2b,0x2c],'31t');put([0x28],'10t');put([0x29],'20t');put([0x2a],'30t')
put(list(range(0x2d,0x32))+list(range(0x44,0x52))+list(range(0x90,0xb0)),'23x')
put(list(range(0x32,0x38)),'22t');put(list(range(0x38,0x3e)),'21t')
put(list(range(0xd0,0xd8)),'22s');put(list(range(0xd8,0xe3)),'22b')
put([0xfa],'45cc');put([0xfb],'4rcc');put([0xfc],'35c');put([0xfd],'3rc');put([0xfe,0xff],'21c')

PREFIXES=('Lcom/gameloft/android/ANMP/GloftGF2F/S800x480/', 'Lc/c/a/a/a/w/', 'Ld/b/', 'Lc/c/a/b/', 'Lc/c/b/', 'Ljavax/microedition/midlet/')
EXTRA_PREFIXES=('Lcom/gameloft/android/ANMP/GloftGF2F/', 'Lcom/gameloft/android/wrapper/Jb;', 'Lcom/gameloft/android/wrapper/NativeUtils;', 'Landroidx/core/view/ViewConfigurationCompat;', 'Lc/c/a/a/a/')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();classes=[];extra_classes=[];available=[];opcode_count=collections.Counter();external=collections.Counter()
    with zipfile.ZipFile(args.apk) as archive:
        for name in ('classes.dex','classes2.dex'):
            dex=Dex(archive.read(name))
            for cls in dex.classes():
                available.append(cls['name'])
                primary=cls['name'].startswith(PREFIXES)
                if not primary and not cls['name'].startswith(EXTRA_PREFIXES):continue
                cls['dex']=name;(classes if primary else extra_classes).append(cls)
                for method in cls['methods']:
                    if method['code']:
                        for instruction in method['code']['instructions']:
                            if instruction['format']!='payload':opcode_count[f'{instruction["op"]:02x}']+=1
                            ref=instruction.get('method')
                            if ref and not ref['owner'].startswith(PREFIXES+EXTRA_PREFIXES):external[ref['key']]+=1
    # Keep established class numbers stable when adding original launcher code.
    extra_classes.sort(key=lambda cls: next(i for i, prefix in enumerate(EXTRA_PREFIXES) if cls['name'].startswith(prefix)))
    classes.extend(extra_classes)
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'program.json').write_text(json.dumps({'apk_sha256':hashlib.sha256(args.apk.read_bytes()).hexdigest(),'available_classes':available,'classes':classes},separators=(',',':')),encoding='utf-8')
    summary={'classes':len(classes),'methods':sum(len(c['methods']) for c in classes),'code_methods':sum(m['code'] is not None for c in classes for m in c['methods']),'instructions':sum(opcode_count.values()),'opcodes':dict(sorted(opcode_count.items())),'external_invokes':dict(external.most_common())}
    (args.output/'coverage.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k not in ('opcodes','external_invokes')},indent=2))

if __name__=='__main__':main()
