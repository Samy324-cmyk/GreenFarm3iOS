"""Translate verified DEX instructions into Dart AOT methods.

This is a register-preserving source translation, not an APK execution engine.
All external operations require explicit runtime bindings. Unknown opcodes fail
generation; unresolved platform methods fail execution rather than return stubs.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def q(value):return json.dumps(value,ensure_ascii=True).replace('$','\\$')
def signed(value,bits):return (value & ((1<<bits)-1))-(1<<bits) if value & (1<<(bits-1)) else value
def field_key(field):return field['owner']+'->'+field['name']+':'+field['type']
def joined(words):return sum(word<<(16*i) for i,word in enumerate(words))
def arguments(item):
    words=item['words'];count=words[0]>>12
    if item['format']=='3rc':return list(range(words[2],words[2]+(words[0]>>8)))
    return [(words[2]>>(4*i))&15 for i in range(4)][:min(count,4)]+([words[0]>>8&15] if count==5 else [])
def literal(value):
    if value is None:return 'null'
    if isinstance(value,int):return str(value)
    if isinstance(value,str):return 'vm.intern('+q(value)+')'
    if 'float_bits' in value:return str(signed(value['float_bits'],32))
    if 'double_bits' in value:return str(signed(value['double_bits'],64))
    if 'class' in value:return 'vm.typeObject('+q(value['class'])+')'
    raise ValueError(f'Unsupported static encoded value {value}')

def emit_method(method,name):
    code=method['code'];words=code['words'];lines=[]
    def emit(line):lines.append(line)
    emit(f'Object? {name}(DalvikRuntime vm, List<Object?> args) {{')
    emit(f'const methodKey = {q(method["key"])};')
    emit(f'final r = List<Object?>.filled({code["registers"]}, 0);')
    emit(f'if (args.length != {code["inputs"]}) throw StateError("Register argument count mismatch");')
    emit(f'r.setRange({code["registers"]-code["inputs"]}, {code["registers"]}, args);')
    emit('Object? result; DalvikObject? exception; int pc = 0;')
    emit('Object? run([DalvikCompletion? completion]) {')
    if any(i['op'] in (0x1d,0x22) or 0x60<=i['op']<=0x78 for i in code['instructions']):
        emit('Object? consume() { final value = completion!; completion = null; return value.unwrap(); }')
    emit('while (true) { try { switch (pc) {')
    for item in code['instructions']:
        if item['format']=='payload':continue
        op=item['op'];w=item['words'];pc=item['pc'];nxt=pc+len(w);a=w[0]>>8;b=a>>4;aa=a&15
        emit(f'case {pc}: {{')
        emit(f'vm.tick(methodKey, {pc});')
        statement=None;terminal=False
        if op==0:statement=''
        elif op in (1,4,7,2,5,8,3,6,9):
            dst,src=(aa,b) if op in (1,4,7) else (a,w[1]) if op in (2,5,8) else (w[1],w[2])
            statement=f'JBits.setWide(r, {dst}, JBits.wide(r, {src}));' if op in (4,5,6) else f'r[{dst}] = r[{src}];'
        elif op in (0xa,0xb,0xc):statement=f'JBits.setWide(r, {a}, result as int);' if op==0xb else f'r[{a}] = result;'
        elif op==0xd:statement=f'r[{a}] = exception;'
        elif op in (0xe,0xf,0x10,0x11):
            statement='return null;' if op==0xe else f'return JBits.wide(r, {a});' if op==0x10 else f'return r[{a}];'
            terminal=True
        elif 0x12<=op<=0x19:
            dst=aa if op==0x12 else a
            value={0x12:signed(b,4),0x13:signed(joined(w[1:]),16),0x14:signed(joined(w[1:]),32),0x15:signed(joined(w[1:])<<16,32),0x16:signed(joined(w[1:]),16),0x17:signed(joined(w[1:]),32),0x18:signed(joined(w[1:]),64),0x19:signed(joined(w[1:])<<48,64)}[op]
            statement=f'JBits.setWide(r, {dst}, {value});' if op>=0x16 else f'r[{dst}] = {value};'
        elif op in (0x1a,0x1b):statement=f'r[{a}] = vm.intern({q(item["string"])});'
        elif op==0x1c:statement=f'r[{a}] = vm.typeObject({q(item["type"])});'
        elif op in (0x1d,0x1e):statement=f'vm.{"monitorEnter" if op==0x1d else "monitorExit"}(r[{a}]);'
        elif op==0x1f:statement=f'vm.checkCast(r[{a}], {q(item["type"])});'
        elif op==0x20:statement=f'r[{aa}] = vm.instanceOf(r[{b}], {q(item["type"])}) ? 1 : 0;'
        elif op==0x21:statement=f'r[{aa}] = vm.asArray(r[{b}]).values.length;'
        elif op==0x22:statement=f'r[{a}] = vm.allocate({q(item["type"])});'
        elif op==0x23:statement=f'r[{aa}] = vm.array({q(item["type"])}, r[{b}] as int);'
        elif op in (0x24,0x25):
            regs=arguments(item);statement=f'final array = vm.array({q(item["type"])}, {len(regs)});'
            statement+=''.join(f'vm.arrayPut(array, {i}, r[{reg}]);' for i,reg in enumerate(regs))+'result = array;'
        elif op==0x26:
            payload=pc+signed(joined(w[1:]),32);width=words[payload+1];count=joined(words[payload+2:payload+4]);raw=b''.join(word.to_bytes(2,'little') for word in words[payload+4:])
            values=[signed(int.from_bytes(raw[i*width:(i+1)*width],'little'),width*8) for i in range(count)]
            statement=f'const data = <int>[{",".join(map(str,values))}]; for (int i=0; i<data.length; i++) {{ vm.arrayPut(r[{a}], i, data[i]); }}'
        elif op==0x27:statement=f'throw DalvikThrown(vm.object(r[{a}]));';terminal=True
        elif op in (0x28,0x29,0x2a):
            delta=signed(a,8) if op==0x28 else signed(joined(w[1:]),16 if op==0x29 else 32)
            statement=f'pc = {pc+delta}; continue;';terminal=True
        elif op in (0x2b,0x2c):
            payload=pc+signed(joined(w[1:]),32);count=words[payload+1]
            if op==0x2b:
                first=signed(joined(words[payload+2:payload+4]),32);keys=list(range(first,first+count));target=payload+4
            else:
                keys=[signed(joined(words[payload+2+i*2:payload+4+i*2]),32) for i in range(count)];target=payload+2+count*2
            pairs=[(key,pc+signed(joined(words[target+2*i:target+2*i+2]),32)) for i,key in enumerate(keys)]
            statement=f'pc = switch (r[{a}] as int) {{'+','.join(f'{key} => {dest}' for key,dest in pairs)+f', _ => {nxt}'+'}; continue;';terminal=True
        elif 0x2d<=op<=0x31:statement=f'r[{a}] = JBits.compare({op}, r, {w[1]&255}, {w[1]>>8});'
        elif 0x32<=op<=0x3d:
            if op<=0x37:left,right,condition=aa,b,op-0x32;rhs=f'r[{right}]'
            else:left,condition=a,op-0x38;rhs='0'
            expr=f'vm.registerEquals(r[{left}], {rhs})' if condition<2 else f'(r[{left}] as int) '+['<','>=','>','<='][condition-2]+f' ({rhs} as int)'
            if condition==1:expr='!'+expr
            statement=f'pc = {expr} ? {pc+signed(w[1],16)} : {nxt}; continue;';terminal=True
        elif 0x44<=op<=0x51:
            array,index=w[1]&255,w[1]>>8;wide=op in (0x45,0x4c)
            if op<=0x4a:
                value=f'vm.arrayGet(r[{array}], r[{index}] as int)'
                statement=f'JBits.setWide(r, {a}, {value} as int);' if wide else f'r[{a}] = {value};'
            else:
                value=f'JBits.wide(r, {a})' if wide else f'r[{a}]'
                statement=f'vm.arrayPut(r[{array}], r[{index}] as int, {value});'
        elif 0x52<=op<=0x6d:
            field=item['field'];key=q(field_key(field));owner=q(field['owner']);wide=op in (0x53,0x5a,0x61,0x68)
            if op<=0x58 or 0x60<=op<=0x66:
                dst=aa if op<=0x58 else a
                value=f'vm.getField(r[{b}], {key})' if op<=0x58 else f'vm.getStatic({owner}, {key})'
                statement=f'JBits.setWide(r, {dst}, {value} as int);' if wide else f'r[{dst}] = {value};'
            else:
                src=aa if op<=0x5f else a
                value=f'JBits.wide(r, {src})' if wide else f'r[{src}]'
                if field['type'] in ('B','S','C','Z'):
                    value=f'({value} as int)'+{'B':'.toSigned(8)','S':'.toSigned(16)','C':'.toUnsigned(16)','Z':' & 1'}[field['type']]
                statement=f'vm.putField(r[{b}], {key}, {value});' if op<=0x5f else f'vm.putStatic({owner}, {key}, {value});'
        elif 0x6e<=op<=0x72 or 0x74<=op<=0x78:
            kind=['virtual','super','direct','static','interface'][op-(0x6e if op<=0x72 else 0x74)]
            values=','.join(f'r[{reg}]' for reg in arguments(item))
            statement=f'result = vm.call({q(item["method"]["key"])}, [{values}], kind: {q(kind)}, caller: {q(method["owner"])});'
        elif 0x7b<=op<=0x8f:statement=f'JBits.unary({op}, r, {aa}, {b});'
        elif 0x90<=op<=0xaf:statement=f'JBits.binary({op}, r, {a}, {w[1]&255}, {w[1]>>8});'
        elif 0xb0<=op<=0xcf:statement=f'JBits.binary({op-0x20}, r, {aa}, {aa}, {b});'
        elif 0xd0<=op<=0xe2:
            dst,src,number=(aa,b,signed(w[1],16)) if op<=0xd7 else (a,w[1]&255,signed(w[1]>>8,8))
            which=op-(0xd0 if op<=0xd7 else 0xd8);canonical=0x90+which
            statement=f'final operands = <Object?>[r[{src}], {number}];'
            if which==1:statement+='JBits.binary(145, operands, 0, 1, 0);'
            else:statement+=f'JBits.binary({canonical}, operands, 0, 0, 1);'
            statement+=f'r[{dst}] = operands[0];'
        else:raise ValueError(f'Unsupported opcode {op:02x} in {method["key"]}:{pc}')
        # Only the completed VM operation is skipped on resume. Registers and
        # side effects before this instruction remain in the captured closure.
        if op==0x1d or 0x67<=op<=0x6d:
            statement='if (completion == null) { '+statement+' } else { consume(); }'
        elif op==0x22:
            expression=f'vm.allocate({q(item["type"])})'
            statement=statement.replace(expression,f'(completion == null ? {expression} : consume())')
        elif 0x60<=op<=0x66:
            expression=f'vm.getStatic({q(item["field"]["owner"])}, {q(field_key(item["field"]))})'
            statement=statement.replace(expression,f'(completion == null ? {expression} : consume())')
        elif 0x6e<=op<=0x72 or 0x74<=op<=0x78:
            statement=statement.replace('result = vm.call(', 'result = completion != null ? consume() : vm.call(')
        emit(statement)
        if not terminal:emit(f'pc = {nxt}; continue;')
        emit('}')
    emit('default: throw StateError("Invalid instruction address: $pc");')
    emit('} } catch (error) {')
    emit('if (error is DalvikPause) { final savedCallStack = List<String>.of(vm.callStack); error.addFrame(DalvikResumeFrame(methodKey: methodKey, pc: pc, resume: (value) => vm.withCallFrame(methodKey, () => run(value), restoredStack: savedCallStack))); rethrow; }')
    emit('final caught = vm.javaException(error); if (caught == null) rethrow;')
    for region in code['tries']:
        emit(f'if (pc >= {region["start"]} && pc < {region["end"]}) {{')
        for handler in region['handlers']:
            condition='true' if handler['type'] is None else f'vm.instanceOf(caught.object, {q(handler["type"])})'
            emit(f'if ({condition}) {{ exception = caught.object; pc = {handler["target"]}; continue; }}')
        emit('}')
    emit('throw caught; } } }')
    emit('return run(); }')
    return '\n'.join(lines)

def generate(program,output):
    output.mkdir(parents=True,exist_ok=True);registrations=[];files=[];method_count=0
    for index,cls in enumerate(program['classes']):
        filename=f'c{index:04d}.dart';files.append(filename)
        lines=['// Generated from original DEX. Do not edit by hand.','// ignore_for_file: unused_local_variable, unnecessary_cast, unused_import, dead_code, curly_braces_in_flow_control_structures, prefer_final_locals, prefer_is_empty',"import '../engine/dalvik/runtime.dart';","import '../engine/dalvik/numbers.dart';","import '../engine/dalvik/cooperative.dart';"]
        register=[f'void registerClass{index}(DalvikRuntime vm) {{',f'vm.registerClass(DalvikClass({q(cls["name"])}, access: {cls["access"]}, superclass: {q(cls["super"])}, interfaces: {q(cls["interfaces"])}, staticFields: {{']
        for field in cls['static_fields']:
            value=field.get('value',None if field['type'].startswith(('L','[')) else 0)
            register.append(f'{q(field_key(field))}: {literal(value)},')
        register.append('}, instanceFields: {')
        register.extend(f'{q(field_key(field))}: {q(field["type"])},' for field in cls['instance_fields'])
        register.append('}));')
        for m,method in enumerate(cls['methods']):
            name=f'_m{m}' if method['code'] is not None else 'null'
            register.append(f'vm.registerMethod(DalvikMethod({q(method["key"])}, {method["access"]}, {name}));')
            if method['code'] is not None:lines.append(emit_method(method,name));method_count+=1
        register.append('}');lines.extend(register)
        (output/filename).write_text('\n'.join(lines)+'\n',encoding='utf-8')
        registrations.append(f'  registerClass{index}(vm);')
    known='vm.availableClassNames.addAll('+q(program.get('available_classes',[c['name'] for c in program['classes']]))+');'
    (output/'program.dart').write_text('\n'.join(["import '../engine/dalvik/runtime.dart';"]+[f"import '{name}';" for name in files]+['void registerOriginalProgram(DalvikRuntime vm) {',known]+registrations+['}'])+'\n',encoding='utf-8')
    report={'source_apk_sha256':program['apk_sha256'],'classes':len(files),'translated_methods':method_count,'unsupported_opcodes':0,'status':'generated; platform bridges and integration verification required'}
    (output/'generation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('program',type=Path);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    generate(json.loads(args.program.read_text(encoding='utf-8')),args.output)

if __name__=='__main__':main()
