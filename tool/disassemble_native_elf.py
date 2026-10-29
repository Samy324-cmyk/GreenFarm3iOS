"""Read-only ELF inventory/disassembly. Never loads or executes the APK library.
Dependencies: capstone==5.0.6, pyelftools==0.32 installed in python-libs/.
"""
import sys,json,hashlib,re
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'python-libs'))
from elftools.elf.elffile import ELFFile
from capstone import Cs,CS_ARCH_X86,CS_MODE_64,CS_MODE_32,CS_ARCH_ARM64,CS_ARCH_ARM,CS_MODE_ARM,CS_MODE_THUMB

path=Path(sys.argv[1]);output=Path(sys.argv[2]);data=path.read_bytes()
with path.open('rb') as stream:
 elf=ELFFile(stream);sections=list(elf.iter_sections())
 symbols={}
 for section in sections:
  if section['sh_type'] in ['SHT_DYNSYM','SHT_SYMTAB']:
   for sym in section.iter_symbols():
    if sym.name:symbols[sym.name]={'address':sym['st_value'],'size':sym['st_size'],'type':sym['st_info']['type'],'section':sym['st_shndx']}
 exports={name:info for name,info in symbols.items() if info['type']=='STT_FUNC' and isinstance(info['section'],int)}
 relocs={}
 for section in sections:
  if section['sh_type'] in ['SHT_RELA','SHT_REL']:
   table=elf.get_section(section['sh_link'])
   for rel in section.iter_relocations():
    symbol=table.get_symbol(rel['r_info_sym']);relocs[rel['r_offset']]=symbol.name
 machine=elf['e_machine'];arch,mode={'EM_X86_64':(CS_ARCH_X86,CS_MODE_64),'EM_386':(CS_ARCH_X86,CS_MODE_32),'EM_AARCH64':(CS_ARCH_ARM64,0),'EM_ARM':(CS_ARCH_ARM,CS_MODE_ARM)}[machine]
 strings={}
 for section in sections:
  if section['sh_type']=='SHT_PROGBITS' and section['sh_flags']&2 and not section['sh_flags']&4:
   for match in re.finditer(rb'[ -~]{3,}',section.data()):strings[section['sh_addr']+match.start()]=match.group().decode('ascii')
 md=Cs(arch,mode);md.detail=True
 addresses={info['address']:name for name,info in exports.items()}
 lines=[f'File: {path}',f'SHA256: {hashlib.sha256(data).hexdigest()}',f'Machine: {machine}','RELOCATIONS',json.dumps({hex(k):v for k,v in relocs.items()},indent=2),'STRINGS',json.dumps({hex(k):v for k,v in strings.items()},indent=2)]
 for name,info in sorted(exports.items(),key=lambda kv:kv[1]['address']):
  if not info['size']:continue
  addr=info['address'];section=sections[info['section']];start=(addr&~1 if machine=='EM_ARM' else addr)-section['sh_addr'];raw=section.data()[start:start+info['size']]
  if machine=='EM_ARM':md=Cs(CS_ARCH_ARM,CS_MODE_THUMB if addr&1 else CS_MODE_ARM)
  lines.append(f'\n{name} address={hex(addr)} size={info["size"]}')
  for ins in md.disasm(raw,addr&~1 if machine=='EM_ARM' else addr):
   annotation=[]
   if ins.mnemonic.startswith('call') or ins.mnemonic=='jmp':
    try:
     target=int(ins.op_str,16)
     if target in addresses:annotation.append(addresses[target])
    except ValueError:pass
   if arch==CS_ARCH_X86:
    for operand in ins.operands:
     if operand.type==3 and ins.reg_name(operand.mem.base)=='rip':
      target=ins.address+ins.size+operand.mem.disp
      annotation.append(hex(target))
      if target in strings:annotation.append(repr(strings[target]))
      if target in relocs:annotation.append(relocs[target])
   lines.append(f'{ins.address:08x} {ins.bytes.hex():24} {ins.mnemonic:9} {ins.op_str}'+(' ; '+' '.join(annotation) if annotation else ''))
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text('\n'.join(lines),encoding='utf-8')
 output.with_suffix('.json').write_text(json.dumps({'path':str(path),'sha256':hashlib.sha256(data).hexdigest(),'machine':machine,'symbols':symbols,'relocations':{hex(k):v for k,v in relocs.items()},'strings':{hex(k):v for k,v in strings.items()}},indent=2),encoding='utf-8')
print('\n'.join(f'{name}: {hex(info["address"])} {info["size"]} bytes' for name,info in exports.items()))
