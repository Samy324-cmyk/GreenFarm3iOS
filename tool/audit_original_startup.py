"""Reproduce the original startup side-effect inventory from recovered Java.
Usage: python tool/audit_original_startup.py RECOVERED_GAME_JAVA OUTPUT_JSON
The recovered source is read as data and is never compiled/executed.
"""
import hashlib,json,re,sys
from pathlib import Path
root=Path(sys.argv[1]);out=Path(sys.argv[2])
start='com/gameloft/android/ANMP/GloftGF2F/Start.java'
midlet='javax/microedition/midlet/MIDlet.java'
rows=[]
def add(phase,source,needle,effect,requirement,status='original code retained; host bridge coverage incomplete'):
 text=(root/source).read_text(encoding='utf-8')
 pos=text.find(needle)
 if pos<0:raise ValueError(f'Missing evidence {source}: {needle}')
 rows.append(dict(phase=phase,source=source,line=text[:pos].count('\n')+1,evidence=needle,effect=effect,port_requirement=requirement,status=status))

add('launcher',start,'f7654e = this;','Sets launcher and MIDlet start-activity references.','Execute original Start.onCreate before game MIDlet creation.')
add('launcher',start,'f.V(1.0f, 1.0f);','Sets canvas scale, keycodes, input and screen defaults.','Preserve static writes and original Canvas calls; full assignment inventory follows.')
add('launcher',start,'MIDlet.N = true;','Enables IAP and Google Play billing mode; configures SDK flags.','Do not turn these flags off to bypass unavailable purchases; provide an explicit host adapter.')
add('launcher',start,'MIDlet.K = true;','Selects encrypted MIDlet properties, rather than resource-string fallback.','Run original Utils.g/DefReader decoding or a verified equivalent over exact content.bin.')
add('launcher',start,'MIDlet.H = "44425";','Establishes package channel/version and wrapper configuration.','Preserve constants, including values whose names are obfuscated.')
add('launcher',start,'if (m.B(this, ""))','Checks actual free disk space against MIDlet.F0 (5 MiB), with localized low-space dialog if insufficient.','Provide real StatFs allocation counts; do not force a successful memory check.')
add('launcher',start,'h.a(this);','LowProfileListener configures immersive system-UI visibility and registers its visibility callback.','Retain original listener/delayed work; map actual requested window chrome to Flutter.')
add('launcher',start,'this.z.post(new b());','Measures attached host view, then chooses screen/asset variant and launches game activity.','View.post must run after a real layout. Zero-sized placeholder views cannot produce faithful startup.')
add('launcher',start,'Pt.f().init();','Starts delayed archive-integrity worker.','Retain original worker/sleep and archive entry sizes; no disabled checks.')
add('launcher','com/gameloft/android/ANMP/GloftGF2F/Pt.java','b.b().e(new String(Pt.this.f7590e))','Checks total size of all original .dex ZIP entries against REVISION-2408 XOR 0x226bc.','Supplied APK passes: 20,299,048 bytes. Preserve actual source archive provenance.')
add('screen','c/c/a/b/i.java','MIDlet.t0 = aVar.f1158d;','Sets physical/virtual dimensions, screen inches, canvas translation/scaling and asset directory.','Preserve original selector and screen math; adapt only host display facts.')
add('screen','c/c/a/b/i.java','intent.putExtra("SCREEN_ORIENTATION", 11);','Carries orientation, push launch, demo and recording intent state to game activity.','Keep original Intent data and activity handoff.')
add('base activity','javax/microedition/midlet/BaseActivity.java','public void onCreate(Bundle bundle)','Registers finish-action broadcast receiver; destroy unregisters it.','Host receiver registry must preserve delivery/unregistration.')
add('MIDlet.onCreate',midlet,'m.a2(this);','Sets global active context and initializes utility environment.','Retain original method; this is already called only in isolated engine-entry probe.')
add('MIDlet.onCreate',midlet,'m.h2("Screen_Width"','Persists actual display width/height on Android facade SDK>=24.','Persist preferences through real storage using supplied display metrics.')
add('MIDlet.onCreate',midlet,'m.g();','Decrypts and parses 41 original MIDlet properties.','Exact encrypted resource has been recovered; implementation must not use K=false fallback.')
add('MIDlet.onCreate',midlet,'editorEdit.putString("is_multiplejar"','Persists multi-jar startup state and redirects invalid entries back to Start.','Preserve preference and asset-directory preconditions.')
add('MIDlet.onCreate',midlet,'getIntent().hasExtra("IS_DEMO")','Consumes demo/record-block flags; demo can clear record stores.','Preserve actual supplied Intent and original branching.')
add('MIDlet.onCreate',midlet,'getWindow().setFlags(1664, 1664);','Sets fullscreen/window behavior, audio volume stream, orientation, configuration defaults.','Use actual Flutter window/orientation/audio bindings; retain configuration state.')
add('MIDlet.onCreate',midlet,'getResources().getDrawable','Requires the real launcher drawable resource.','Decode original resource bytes; no dummy drawable or unconditional non-null sentinel.')
add('MIDlet.onCreate',midlet,'k(this);','Deletes temporary .snddmp sound files from private storage.','Execute original cleanup against actual host storage.')
add('MIDlet.onCreate',midlet,'getStringExtra("LANGUAGE")','Persists explicit launch language; optional demo timer can be scheduled.','Preserve original record-store and timer logic.')
add('MIDlet.onCreate',midlet,'getSystemService("power")','Uses keyguard/power state and optionally acquires a wake lock.','Require real host lifecycle/power adapter; preserve acquisition/release semantics.')
add('MIDlet.onCreate',midlet,'System.setProperty("microedition.sensor.version"','Creates runtime properties for device, OS, IDs, carrier, root probe, audio, signature and virtual dimensions.','Do not invent hardware identities; Utils.g0 intentionally returns empty AndroidID in original code.')
add('MIDlet.onCreate',midlet,'d.b.c.b.c(bundle);','Push-notification wrapper initializes backend using Has-Push-Notification=1.','Keep original configuration; real platform notification adapter and backend compatibility remain required.')
add('MIDlet.onCreate',midlet,'d.b.c.m.c(bundle);','Zoro wrapper has empty onCreate; later lifecycle callbacks perform account/SDK work.','An empty original onCreate does not authorize skipping later callbacks.')
add('MIDlet.onCreate',midlet,'l.c(bundle);','Splash wrapper sets original game code/version.','Preserve original initializer.')
add('MIDlet.onCreate',midlet,'d.b.c.k.c(bundle);','Install-referrer wrapper reads QA config and initializes referrer.','Provide truthful host install-source/referrer behavior or explicit unsupported bridge.')
add('MIDlet.onCreate',midlet,'j.c(bundle);','SoftKeyboard child onCreate invokes LowProfileListener immersive-UI setup; later callbacks also hide active soft input.','Preserve both actual immersive-window state and keyboard behavior.')
add('MIDlet.onCreate',midlet,'h.c0(bundle);','Facebook wrapper initializes SDK, callbacks, signature and events.','Preserve account/social integration; external platform configuration remains required.')
add('MIDlet.onCreate',midlet,'f.c(bundle);','IAP wrapper initializes Google billing and starts its worker because MIDlet.N=true.','Original Google billing cannot be treated as an iOS purchase provider; explicit platform adapter is required.')
add('MIDlet.onCreate',midlet,'d.b.c.d.c(bundle);','Utility tracker/referrer initialization executes.','Retain original call flow; do not report successful telemetry without actual delivery.')
add('MIDlet.onCreate',midlet,'d.b.c.c.c(bundle);','Ads wrapper initializes AdsManager and Activity/parent state.','Retain ads state and callbacks; backend/platform support must be implemented explicitly.')
add('MIDlet.onCreate',midlet,'System.setProperty("injectedserialkey"','Reads injected serial-key/IGP resources, and conditionally migrates old files.','Preserve resource absence semantics and actual private-file migration.')
add('MIDlet.onStart',midlet,'System.setProperty("microedition.locale.country"','Establishes locale, SIM country and user country properties; dispatches SDK start callbacks.','Use host locale/telephony availability and preserve original fallbacks.')
add('MIDlet.onResume',midlet,'public void onResume()','Resumes surface/audio, invokes G() once, then dispatches child SDK/account/IAP/IGP lifecycle callbacks.','Calling G() directly is an engine probe, not complete startup.')
add('MIDlet.lifecycle',midlet,'public void onPause()','Pause/stop/destroy dispatch SDK cleanup, audio/surface state and power/receiver lifecycle.','Wire actual app lifecycle events through original methods.')

text=(root/start).read_text(encoding='utf-8');lines=text.splitlines()
begin=next(i for i,l in enumerate(lines) if 'public void onCreate(Bundle bundle)' in l)
end=next(i for i in range(begin+1,len(lines)) if 'public void onDestroy()' in lines[i])
assignments=[]
for number in range(begin,end):
 match=re.match(r'\s*((?:MIDlet|d|m|f)\.\w+)\s*=\s*(.*);\s*$',lines[number])
 if match:assignments.append(dict(source=start,line=number+1,target=match[1],expression=match[2]))
sources=sorted({r['source'] for r in rows})
result=dict(scope='Evidence inventory, not a claim of complete startup or full port.',source_format='JADX Java; generated DEX remains execution authority.',source_sha256={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources},effects=rows,start_static_assignments=assignments)
out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(rows)} lifecycle effects; {len(assignments)} explicit Start static assignments -> {out}')
