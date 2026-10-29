"""Reproduce nativeU provenance, decoded JNI names and semantic evidence.
Usage: python tool/audit_native_utils.py assets/provenance/original.apk game_source/native_utils_semantics.json
Read-only parsing; does not load or execute any APK binary.
"""
import hashlib,json,struct,sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as archive:
 data=archive.read('lib/x86_64/libnativeU.so')
 expected='8374e2ff13ef26ec27ce3272e27fd6bf6f2a1e987ed72b4774f4b04beb052a81'
 if hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Native semantics have only been audited for this exact original library')
 phoff=struct.unpack_from('<Q',data,32)[0];entsize,count=struct.unpack_from('<HH',data,54)
 segments=[struct.unpack_from('<IIQQQQQQ',data,phoff+i*entsize) for i in range(count)]
 def read(address,length):
  segment=next(s for s in segments if s[0]==1 and s[3]<=address<s[3]+s[5])
  offset=segment[2]+address-segment[3];return data[offset:offset+length]
 encoded=[(0x3140,31),(0x3020,2),(0x3030,16),(0x3023,5),(0x3066,2),(0x3050,21),(0x3125,2),(0x3110,20),(0x30f6,11),(0x30e0,21),(0x30d6,6),(0x30c0,21),(0x30ad,8),(0x3080,44),(0x3069,7)]
 strings=[dict(address=hex(address),length=length,text=bytes((b+i%10+1)%256 for i,b in enumerate(read(address,length))).decode('ascii').rstrip('\0')) for address,length in encoded]
 libs=[dict(entry=name,sha256=hashlib.sha256(archive.read(name)).hexdigest(),size=archive.getinfo(name).file_size) for name in ['lib/x86_64/libnativeU.so','lib/arm64-v8a/libnativeU.so']]
 dex=[dict(entry=i.filename,size=i.file_size) for i in archive.infolist() if i.filename.endswith('.dex')]
 functions=[
  dict(name='CheckRoot()Z',x86_64='0x1240 -> IsDeviceRooted 0x11c0',arm64='0x1368 -> IsDeviceRooted 0x12ec',semantics="if fopen('/system/app/Superuser.apk','rb') != NULL: fclose and true; else if stat('/system/bin/su') != -1: true; else stat('/system/xbin/su') != -1",host='Exact libc file probes; no broader jailbreak or user-ID inference.'),
  dict(name='getClock()F',x86_64='0x1110',arm64='0x1240',semantics='float32(float32(clock()) / float32(1000000))',host='Real process CPU clock; first conversion rounds directly from signed int64.'),
  dict(name='getClockMillis()J',x86_64='0x1130',arm64='0x1268',semantics='clock_gettime(CLOCK_MONOTONIC=1): seconds*1000 + nanoseconds/1000000 (integer truncation)',host='Equivalent monotonic source excluding suspended time; not wall-clock time.'),
  dict(name='getClockNano()J',x86_64='0x1190',arm64='0x12b8',semantics='clock_gettime(CLOCK_MONOTONIC=1): seconds*1000000000 + nanoseconds'),
  dict(name='tm()J',x86_64='0x1180',arm64='0x12b4',semantics='Tail call getClockMillis.'),
  dict(name='sp(J)V',x86_64='0xc40',arm64='0xcd4',semantics='JNI FindClass com/gameloft/android/wrapper/Jb; call static sp(J)V.',java_delegate='Jb.sp -> c/c/a/b/m.K -> Thread.sleep, with original Java exception handling.'),
  dict(name='sd()J',x86_64='0xe70',arm64='0xf40',semantics="Jb.kz() returns original sourceDir; new java.util.zip.ZipFile(path).getEntry('classes.dex').getSize(). Original JNI does not close the ZipFile.",java_delegate='Jb.kz -> c/c/a/b/m.j0 -> ApplicationInfo.sourceDir'),
  dict(name='checkPlatformService(J)Z',x86_64='0x10f0',arm64='0x120c',semantics='sd() == (argument XOR 0x226bc)')
 ]
 result=dict(scope='Recovered native semantics, independently inspected in x86_64 and ARM64 disassembly. No APK binaries executed.',libraries=libs,encoded_names=strings,clock_float_divisor=struct.unpack('<f',read(0x1334,4))[0],functions=functions,unused_exports={'ts':'java/lang/Thread.sleep(J)V; not declared in supplied NativeUtils Java class','da':'attempts Jb.py(Ljava/lang/String;)V; method absent from supplied Jb, and export absent from NativeUtils Java declarations'},integrity=dict(dex_entries=dex,dex_size_total=sum(e['size'] for e in dex),revision_property='20421524',xor_mask='0x226bc',expected_size=20421524^0x226bc),verification=dict(cpu_clock_oracle='test/oracles/NativeClockOracle.java; 1012 vectors',tests='test/dalvik/native_utils_test.dart',disassembly='native_disassembly_x86_64.txt and native_disassembly_arm64.txt',disassembler_dependencies=['capstone==5.0.6','pyelftools==0.32']))
 out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print(f'Recovered {len(functions)} JNI functions; original DEX total {result["integrity"]["dex_size_total"]} bytes -> {out}')
