"""Rebuild Android resource metadata from JADX --no-src output of original APK.

No application code is executed. Android identifiers are preserved verbatim.
"""
import argparse, json, re, xml.etree.ElementTree as ET
from pathlib import Path

def android_text(value):
    if len(value)>=2 and value[0]==value[-1]=='"': value=value[1:-1]
    def unescape(m):
        c=m.group(1)
        return chr(int(c[1:],16)) if c.startswith('u') else {'n':'\n','r':'\r','t':'\t'}.get(c,c)
    return re.sub(r'\\(u[0-9a-fA-F]{4}|.)',unescape,value)

def extract(root):
    manifest=ET.parse(root/'AndroidManifest.xml').getroot()
    ns='{http://schemas.android.com/apk/res/android}'
    sdk=manifest.find('uses-sdk'); app=manifest.find('application')
    data={'package':manifest.attrib['package'],'versionName':manifest.attrib[ns+'versionName'],'versionCode':int(manifest.attrib[ns+'versionCode']),
          'minSdk':int(sdk.attrib[ns+'minSdkVersion']),'targetSdk':int(sdk.attrib[ns+'targetSdkVersion']),
          'applicationMetadata':[{k.replace(ns,''):v for k,v in e.attrib.items()} for e in app.findall('meta-data')],
          'applicationAttributes':{k.replace(ns,''):v for k,v in app.attrib.items()},
          'requestedPermissions':[e.attrib[ns+'name'] for e in manifest.findall('uses-permission')],
          'activities':[{k.replace(ns,''):v for k,v in e.attrib.items()} for e in app.findall('activity')],
          'resources':[]}
    resources={}
    for entry in ET.parse(root/'res/values/public.xml').getroot():
        key=(entry.attrib['type'],entry.attrib['name'])
        resources[key]={'id':int(entry.attrib['id'],16),'type':key[0],'name':key[1],'values':{}}
    for directory in sorted((root/'res').glob('values*')):
        qualifier=directory.name[6:].lstrip('-')
        for filename,kind in [('strings.xml','string'),('integers.xml','integer'),('bools.xml','bool')]:
            path=directory/filename
            if path.exists():
                for entry in ET.parse(path).getroot():
                    if entry.tag!=kind:continue
                    key=(kind,entry.attrib['name']);value=android_text(''.join(entry.itertext()))
                    if kind=='integer':value=int(value,0)
                    if kind=='bool':value=value=='true'
                    if key in resources:resources[key]['values'][qualifier]=value
    for directory in sorted((root/'res').iterdir()):
        if not directory.is_dir() or directory.name.startswith('values'):continue
        parts=directory.name.split('-',1);kind=parts[0];qualifier=parts[1] if len(parts)>1 else ''
        for path in directory.iterdir():
            key=(kind,path.name.split('.')[0])
            if key in resources:resources[key].setdefault('paths',{})[qualifier]=path.relative_to(root).as_posix()
    data['resources']=sorted(resources.values(),key=lambda r:r['id'])
    return data

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('decoded_directory');p.add_argument('output');args=p.parse_args()
    data=extract(Path(args.decoded_directory));dest=Path(args.output);dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(data,ensure_ascii=True,indent=2),encoding='utf-8')
    print(f"{data['package']} {data['versionName']}: {len(data['resources'])} original resource identifiers")
