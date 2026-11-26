"""Run the real MIDlet with FreeJ2ME sound enabled and capture Java Sound PCM."""
import argparse
from hashlib import sha256
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import wave
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "tools"))
from media import read_audio_bank


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("game", type=Path)
    args.add_argument("--bench", type=Path, required=True, help="directory containing TouchBench.java")
    args.add_argument("--script", type=Path, help="touch script for this edition of the game")
    args.add_argument("--pets", action="store_true", help="exercise Android pet, extractor and hive audio, including repeat playback")
    args.add_argument("--emulator", type=Path, required=True)
    args.add_argument("--profile", type=Path, required=True)
    args.add_argument("--java", default="java")
    args.add_argument("--javac", default="javac")
    a = args.parse_args()
    profile = a.profile.resolve()
    profile.mkdir(parents=True, exist_ok=False)
    source = (a.bench / "TouchBench.java").read_text(encoding="utf-8")
    anchor = 'Mobile.config.sysSettings.put("sound", "off");'
    if source.count(anchor) != 1:
        raise ValueError("Cannot locate emulator audio setting in test harness")
    source = source.replace("ImageIO.setUseCache(false);", "CaptureAudio.install(); ImageIO.setUseCache(false);")
    source = source.replace(anchor, anchor.replace('"off"', '"on"'))
    # After observing normal gameplay, explicitly exercise one verified effect
    # through the game's own pack loader and playback queue.
    source = source.replace('case "quit":', '''case "quietAudio":
      Class<?> farmAudio=Class.forName("a",true,Mobile.getPlatform().loader);
      for(java.lang.reflect.Field field:farmAudio.getDeclaredFields()) {
        if(field.getType()==Boolean.TYPE && (field.getName().equals("S") || field.getName().equals("T"))) {
          field.setAccessible(true);field.setBoolean(null,false);
        }
      }
      java.lang.reflect.Method stop=farmAudio.getDeclaredMethod("fE");
      stop.setAccessible(true);stop.invoke(null);
      break;
    case "farmMix":
      Class<?> farmLayers=Class.forName("GF3FarmAudio",true,Mobile.getPlatform().loader);
      java.lang.reflect.Method farmSong=farmLayers.getDeclaredMethod("music",int.class,boolean.class);
      farmSong.setAccessible(true);farmSong.invoke(null,0,false);
      java.lang.reflect.Method farmUpdate=farmLayers.getDeclaredMethod("update");
      farmUpdate.setAccessible(true);farmUpdate.invoke(null);
      break;
    case "pet":
      System.out.println("PET_CUE "+t[1]);
      Class<?> animalGame=Class.forName("a",true,Mobile.getPlatform().loader);
      java.lang.reflect.Field fx=null;
      for(java.lang.reflect.Field field:animalGame.getDeclaredFields())
        if(field.getType()==Boolean.TYPE && field.getName().equals("S")) fx=field;
      fx.setAccessible(true);fx.setBoolean(null,true);
      for(java.lang.reflect.Method func:animalGame.getDeclaredMethods())
        if(func.getName().equals("c") && func.getReturnType()==Void.TYPE &&
           java.util.Arrays.equals(func.getParameterTypes(),new Class[]{int.class})) {
            func.setAccessible(true);func.invoke(null,Integer.parseInt(t[1]));
        }
      fx.setBoolean(null,false);
      for(java.lang.reflect.Field field:animalGame.getDeclaredFields())
        if(field.getType()==Integer.TYPE && field.getName().equals("aw")) {
            field.setAccessible(true);System.out.println("PET_BANK "+field.getInt(null));
        }
      break;
    case "original":
      System.out.println("ANDROID_CUE "+t[1]);
      Class<?> originalGame=Class.forName("a",true,Mobile.getPlatform().loader);
      Class<?> originalPlayer=Class.forName("GF3FarmAudio",true,Mobile.getPlatform().loader);
      for(java.lang.reflect.Field field:originalGame.getDeclaredFields())
        if(field.getType()==Boolean.TYPE && (field.getName().equals("S") || field.getName().equals("T"))) {
          field.setAccessible(true);field.setBoolean(null,true);
        }
      java.lang.reflect.Method originalCue=originalPlayer.getDeclaredMethod("original",int.class);
      originalCue.setAccessible(true);originalCue.invoke(null,Integer.parseInt(t[1]));
      for(java.lang.reflect.Field field:originalGame.getDeclaredFields())
        if(field.getType()==Boolean.TYPE && (field.getName().equals("S") || field.getName().equals("T"))) {
          field.setAccessible(true);field.setBoolean(null,false);
        }
      break;
    case "cue":
      System.out.println("DIRECT_CUE_BEGIN");
      Class<?> snd = Class.forName("k",true,Mobile.getPlatform().loader);
      java.lang.reflect.Method load = snd.getDeclaredMethod("a",String.class,int.class,boolean.class);
      load.setAccessible(true);load.invoke(null,"/3",Integer.parseInt(t[1]),false);
      java.lang.reflect.Method play = snd.getDeclaredMethod("a",int.class,int.class,int.class,int.class,int.class);
      play.setAccessible(true);play.invoke(null,0,Integer.parseInt(t[1]),1,100,0);break;
    case "quit":''')
    source = source.replace('case "quit":', '''case "quit":
      System.out.println("HEAP_SAMPLE "+CaptureAudio.sampledHeap);
      for(java.lang.management.MemoryPoolMXBean p:java.lang.management.ManagementFactory.getMemoryPoolMXBeans())
        if(p.getType()==java.lang.management.MemoryType.HEAP)
          System.out.println("HEAP_POOL "+p.getName()+" "+p.getPeakUsage().getUsed());
      ''')
    (profile / "TouchBench.java").write_text(source, encoding="utf-8")
    service = profile / "META-INF/services/javax.sound.sampled.spi.MixerProvider"
    service.parent.mkdir(parents=True)
    service.write_text("CaptureAudio\n", encoding="ascii")
    emulator = a.emulator.resolve()
    game = a.game.resolve()
    subprocess.run([a.javac, "--release", "8", "-Xlint:-options", "-cp", str(emulator), "-d",
                    str(profile), str(HERE / "CaptureAudio.java"), str(profile / "TouchBench.java")], check=True)
    cmd = [a.java, "-Xmx256m", "-Djava.security.manager=allow", "-Djava.awt.headless=true",
           "-Dfile.encoding=ISO_8859_1", f"-Duser.home={profile}", f"-Djava.io.tmpdir={profile}",
           "-cp", os.pathsep.join([str(profile), str(emulator)]), "TouchBench", str(game), "480", "800", "0"]
    with (profile / "run.log").open("wb") as log:
        script = a.script or a.bench / "verify-harvest.txt"
        commands = script.read_text().splitlines()
        if "quit" not in commands:
            raise ValueError("The touch script must end the emulator")
        # Exercise the native loader while the MIDlet is still running.
        before = commands.index("close") if "close" in commands else commands.index("quit")
        commands[before:before] = ["wait 23000","touch 245 365","wait 1000","farmMix","wait 650","cue 22","wait 4500"]
        if a.pets:
            before = commands.index("close") if "close" in commands else commands.index("quit")
            checks = ["quietAudio","wait 1500"]
            for slot in (119,119,120,121,122,123,124,125,126,135,135):
                # The six-second fox fight retains the single MIDP effect
                # channel. Let it finish before measuring the extractor.
                checks.extend([f"pet {slot}", "wait 6700" if slot==124 else "wait 3600"])
            for source_id in (79,11,67):
                checks.extend([f"original {source_id}", "wait 3500"])
            commands[before:before] = checks
        inputs = "\n".join(commands) + "\n"
        p = subprocess.run(cmd, cwd=profile, input=inputs.encode(),
                           stdout=log, stderr=subprocess.STDOUT, timeout=180)
    log = (profile / "run.log").read_text(encoding="latin-1")
    if p.returncode or "AUDIO_CAPTURE selected" not in log or "Cannot set Media Time" in log:
        raise RuntimeError("Capture sink or emulator failed. Inspect run.log.")
    hashes = {}
    with zipfile.ZipFile(game) as jar:
        for index, cue in enumerate(read_audio_bank(jar)):
            if cue[1:5] != b"RIFF":
                continue
            with wave.open(io.BytesIO(cue[1:])) as wav:
                if wav.getframerate() == 32000 and wav.getsampwidth() == 2:
                    pcm = wav.readframes(wav.getnframes())
                    hashes.setdefault(sha256(pcm).hexdigest(), []).append(index)
    opens = {}
    for h, rate, bits, channels, frames, nonzero in re.findall(
            r"^PCM_OPEN (\w+) (\d+) (\d+) (\d+) (\d+) (\d+)", log, re.M):
        opens[h] = {"slots": hashes.get(h, []), "rate": int(rate), "bits": int(bits),
                    "channels": int(channels), "frames": int(frames), "nonzeroBytes": int(nonzero)}
    observed,marker,explicit = log.partition("DIRECT_CUE_BEGIN")
    if not marker:
        raise ValueError("Native cue test did not run")
    def started(part):
        starts = re.findall(r"^PCM_START (\w+) ", part, re.M)
        return [opens[h] for h in starts if h in opens and opens[h]["nonzeroBytes"]]
    played = started(observed)
    report = {"jarSha256": sha256(game.read_bytes()).hexdigest(),
              "emulatorSha256": sha256(emulator.read_bytes()).hexdigest(),
              "heapMaxBytes": 256 * 1024 * 1024,
              "sampledPeakHeapBytes": int(re.search(r"HEAP_SAMPLE (\d+)", log).group(1)),
              "peakHeapPools": dict(re.findall(r"^HEAP_POOL ([^\r\n]+) (\d+)", log, re.M)),
              "gameplayClipStarts": played, "directCueStarts": started(explicit),
              "uniqueClipsOpened": len(opens)}
    (profile / "audio.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if not any(any(i < 15 for i in item["slots"]) for item in played):
        raise ValueError("Gameplay did not start an identifiable APK music clip")
    if not any(any(i >= 15 for i in item["slots"]) for item in played):
        raise ValueError("Gameplay did not start an identifiable APK sound effect")
    if not any(22 in item["slots"] for item in started(explicit)):
        raise ValueError("Explicit MMAPI playback of the source sound failed")
    for mix in re.findall(r"^PCM_MIX ([^\r\n]+)",log,re.M):
        slots=[opens[h]["slots"] for h in mix.split() if h in opens]
        if (any(25 in group for group in slots) and any(any(i<15 for i in group) for group in slots)
                and any(22 in group for group in slots)):
            report["simultaneousFarmAudio"]=slots
            break
    if "simultaneousFarmAudio" not in report:
        raise ValueError("Music, farm ambience and the test effect did not play simultaneously")
    (profile / "audio.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if a.pets:
        pet_log,android_marker,other_log=explicit.partition("ANDROID_CUE ")
        chunks = re.split(r"^PET_CUE (\d+)\s*$",pet_log,flags=re.M)
        observed_pets = []
        banks=[]
        for slot,part in zip(chunks[1::2],chunks[2::2]):
            target = int(slot)
            banks.append(int(re.search(r"PET_BANK (\d+)",part).group(1)))
            channels=1 if target==135 else 2
            if not any(target in item["slots"] and item["channels"]==channels for item in started(part)):
                raise ValueError(f"Missing in-game MMAPI start for pet event {target}")
            observed_pets.append(target)
        if observed_pets != [119,119,120,121,122,123,124,125,126,135,135]:
            raise ValueError("Incomplete pet event run")
        if banks != [119,127,120,121,122,123,124,125,126,135,136]:
            raise ValueError(f"Unexpected native effect bank sequence {banks}")
        report['petEventIds'] = observed_pets
        report['petPlaybackSlots'] = banks
        chunks = re.split(r"^ANDROID_CUE (\d+)\s*$",android_marker+other_log,flags=re.M)
        expected_slots={79:149,11:11,67:142}
        triggered=[]
        for source_id,part in zip(chunks[1::2],chunks[2::2]):
            source_id=int(source_id)
            if not any(expected_slots[source_id] in item["slots"] for item in started(part)):
                raise ValueError(f"Missing playback for Android source {source_id}")
            triggered.append(source_id)
        if triggered!=list(expected_slots):
            raise ValueError("Incomplete Android dispatcher test")
        report["originalSourceEvents"]=triggered
        (profile / "audio.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(profile / "audio.json")


if __name__ == "__main__":
    main()
