"""Build the Java ME package from the two supplied Green Farm 3 releases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import struct
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from tools.media import build_media
from tools.mexican_spanish import regionalize
from tools.farm_layout import build_layout
from tools.farm_art import build_farm_art, patch_farm_zoom, patch_farm_decode_buffer
from tools.hud_art import build_hud_art, farm_hud_panel, FARM_CONTROLS, HUD_SLOTS
from tools.pause_menu import patch_pause
from tools.ground_art import ground_tiles, patch_horizon
from tools.loading_screen import restore_loading_screen
from tools.farm_hud_text import patch_farm_hud_text
from tools.zoom_input import build_zoom
from tools.farm_audio import patch_farm_audio, patch_audio_boot
from tools.sprites import build_sprites
from tools.sprite_runtime import patch_renderer
from tools.offline import disconnect, verify_offline
from tools.expansion.rules import build_rules
from tools.expansion.mill import append_recipe, patch_mill
from tools.expansion.cooking import build_recipes, patch_cooking
from tools.expansion.kitchen_queue import patch_kitchen_queue
from tools.expansion.journal import patch_journal
from tools.expansion.hives import patch_hives
from tools.expansion.dogs import patch_dogs
from tools.expansion.dog_toys import patch_toys
from tools.expansion.neighbor import patch_neighbor
from tools.expansion.home import link_home_save, patch_home
from tools.expansion.manor import patch_manor
from tools.expansion.dog_tutorial import patch_dog_tutorial
from tools.expansion.visit_predators import patch_visit_predators
from tools.expansion.extractor_ui import patch_extractor_ui
from tools.expansion.honey_tutorial import patch_honey_tutorial
from tools.expansion.market_front import patch_marketfront
from tools.expansion.farm_edits import patch_farm_edits
from tools.expansion.customer_orders import patch_customer_orders
from tools.expansion.crop_duster import patch_crop_duster
from tools.expansion.pond import patch_pond
from tools.expansion.mailbox import patch_mailbox
from tools.expansion.doghouse import patch_house
from tools.expansion.unlocks import build_unlocks, patch_unlocks
from tools.animal_market import patch_decor_factory, patch_market
from tools.acre_campaign import build_achievements, build_deeds, patch_flock
from tools.catalog_ext import build_catalog, patch_catalog_class, catalog_save_helper
from tools.world import build_world, entries, pack, table

ROOT = Path(__file__).resolve().parent
JAR_DIGEST = 'e4e8634fe47986211da9646c04b88b0bb9cc6917bada5c10fca567909a779617'
APK_DIGEST = '3081eded66775b99790b35e2980057a9ac559afa08bba6daa94bc21fa325092d'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rebuild(jar, updates, output):
    with ZipFile(output, 'w') as target:
        for name in [*jar.namelist(), *sorted(set(updates) - set(jar.namelist()))]:
            info = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (0o40755 if name.endswith('/') else 0o100644) << 16
            data = updates[name] if name in updates else jar.read(name)
            target.writestr(info, data, ZIP_DEFLATED, compresslevel=9)


def resource_index(jar, changes):
    data = bytearray(jar.read('999'))
    cursor = 4
    counts = {}
    for _ in range(struct.unpack_from('<I', data)[0]):
        size, = struct.unpack_from('<I', data, cursor)
        cursor += 4
        label = data[cursor:cursor + size].decode('ascii')
        cursor += size
        group = label.split('.')[0]
        sequence = counts.get(group, 0)
        name = f'{group}.{sequence}' if sequence else group
        counts[group] = sequence + 1
        old_size, = struct.unpack_from('<I', data, cursor)
        if jar.getinfo(name).file_size != old_size:
            raise ValueError(f'Invalid original size for {name}')
        if name in changes:
            struct.pack_into('<I', data, cursor, len(changes[name]))
        cursor += 4
    if cursor != len(data):
        raise ValueError('Unexpected resource index trailer')
    # Keep newly introduced native audio shards in the resource-size index.
    extra = [name for name in changes if name.startswith('3.') and name not in jar.namelist()]
    for name in sorted(extra, key=lambda n: int(n.split('.')[1])):
        label = name.encode('ascii')
        data.extend(struct.pack('<I',len(label))+label+struct.pack('<I',len(changes[name])))
    struct.pack_into('<I',data,0,struct.unpack_from('<I',data)[0]+len(extra))
    return bytes(data)


def build(args):
    directory = args.out.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    if digest(args.jar) != JAR_DIGEST or digest(args.apk) != APK_DIGEST:
        raise ValueError('Usa el JAR táctil 1.0.6 y el APK 4.4.4 correspondientes a este proyecto.')
    api=args.api
    if api is None:
        prepared=subprocess.check_output([sys.executable,str(ROOT/'tests/emulator/bench.py'),'--prepare'],
                                         text=True,encoding='utf-8').strip()
        api=Path(prepared)
    api=api.resolve(strict=True)
    filename = 'GreenFarm3-MX.jar'
    target = directory / filename
    if target == args.jar.resolve() or target == args.apk.resolve():
        raise ValueError('La salida debe ser distinta de los originales.')
    with TemporaryDirectory(dir=directory) as scratch:
        temp = Path(scratch)
        with ZipFile(args.jar) as jar, ZipFile(args.apk) as apk:
            media, media_report = build_media(jar, apk, decoder=args.decoder)
            world, media['EN'], world_report = build_world(jar, apk, media['EN'])
            limits = {0:76, 1:141, 2:24, 3:30, 4:69}
            world['9'], media['EN'], catalog_report = build_catalog(
                jar, apk, world['9'], media['EN'], counts=limits)
            mobile = entries(world['9'])
            android = entries(apk.read('assets/800x480/13'))
            mobile[22] = append_recipe(mobile[22], android[22], mobile[1])
            mobile[7], media['EN'] = build_recipes(mobile, android, apk, media['EN'])
            mobile[12] = build_deeds(mobile[12],android[12])
            mobile[25] = build_achievements(mobile[25],android[25])
            scenery=table(android[15])[1]
            if (table(mobile[15])[1]!=scenery[:-2] or
                    [row[:2] for row in scenery[-2:]]!=[(28,184),(29,185)]):
                raise ValueError('Unexpected Android scenery registry')
            mobile[15]=android[15]
            build_unlocks(mobile,android)
            world_report['recipeDefinitions'] = len(table(mobile[7])[1])
            world_report['referenceOnlyUnmappedRecipes'] = []
            world_report.pop('unmatchedReferenceRecipeIds')
            world_report['additionalRecipes'] = world_report.pop('androidOnlyRecipeIds')
            # Both games read these columns directly as the time/cost lookup
            # arrays and the prices of the six farm expansion slots.
            for idx in (29, 30):
                source, reference = table(android[idx])[1], table(mobile[idx])[1]
                if [(v[0],len(v)) for v in source] != [(v[0],len(v)) for v in reference]:
                    raise ValueError('Unsupported offline pricing table')
                mobile[idx] = android[idx]
            reference = entries(jar.read('9'))
            world_report['tableRowCounts'] = [
                {'table': i, 'touchSource': len(table(ref)[1]), 'ported': len(table(dst)[1]),
                 'android': len(table(src)[1])}
                for i,(ref,dst,src) in enumerate(zip(reference,mobile,android))]
            world['9'] = pack(mobile)
            world['10'], world_report['layout'] = build_layout(world['10'], apk, mobile)
            media['EN'], media_report['mexicanVocabularyLines'] = regionalize(media['EN'])
            sprites, sprite_report = build_sprites(jar, apk)
            farm, slots = build_farm_art(jar, apk, sprites)
            sprites.update(farm)
            sprite_report['originalFarmArt'] = slots
            sprites.update(build_hud_art(jar, apk, sprites))
            sprite_report['originalHudArt'] = list(HUD_SLOTS)
            sprite_report['farmHudFrames'] = FARM_CONTROLS
            sprites.update(ground_tiles(jar, apk, sprites))
            sprite_report['terrainTileModules'] = {'nativeResolution':48, 'halfResolution':48}
            if world.keys() & media.keys() or sprites.keys() & (world.keys() | media.keys()):
                raise ValueError('Dos conversiones escriben el mismo recurso.')
            rebuilt = temp / 'localized.jar'
            classes = build_rules(jar, apk)
            classes.update(patch_crop_duster(classes['a.class'],apk))
            classes['a.class'] = patch_catalog_class(patch_mill(classes['a.class']), counts=limits)
            classes.update(patch_cooking(classes['a.class']))
            classes['GF3CatalogSave.class'] = catalog_save_helper()
            classes.update(patch_market(classes['a.class'], jar.read('k.class')))
            classes.update(patch_farm_audio(classes['a.class'],classes['k.class']))
            classes['GloftGF2M.class']=patch_audio_boot(jar.read('GloftGF2M.class'))
            classes.update(patch_kitchen_queue(classes['a.class'], classes['GF3CatalogSave.class']))
            classes['a.class'] = patch_unlocks(patch_journal(classes['a.class']))
            classes.update(patch_hives(classes['a.class'], jar.read('f.class')))
            classes['f.class'] = patch_decor_factory(classes['f.class'])
            classes.update(patch_dogs(classes['f.class']))
            classes.update(patch_toys(classes['a.class'],classes['f.class'],classes['GF3CatalogSave.class']))
            classes.update(patch_neighbor(classes['a.class'], classes['f.class'], apk))
            classes.update(patch_flock(classes['a.class'],classes['f.class']))
            classes.update(patch_horizon(classes['f.class'],classes['k.class']))
            classes['a.class'] = patch_farm_zoom(classes['a.class'], slots)
            classes.update(disconnect(jar,classes))
            renderer = patch_renderer(jar)
            renderer['e.class'] = patch_farm_decode_buffer(renderer['e.class'])
            classes.update(patch_house(classes['a.class'], renderer['e.class'], jar.read('6'), apk))
            classes.update(patch_home(classes['a.class'], classes['f.class'], classes['6'], apk))
            classes['a.class'] = patch_manor(classes['a.class'])
            classes.update(patch_dog_tutorial(classes,apk))
            classes.update(patch_visit_predators(classes,apk))
            classes['GF3CatalogSave.class'] = link_home_save(classes['GF3CatalogSave.class'])
            classes.update(patch_extractor_ui(classes,apk))
            classes.update(patch_honey_tutorial(classes,apk))
            classes.update(patch_marketfront(classes,apk,media['EN']))
            classes.update(patch_customer_orders(classes,apk))
            classes.update(patch_pond(classes['a.class'],apk))
            classes['a.class']=patch_mailbox(classes['a.class'])
            classes['6'] = farm_hud_panel(classes['6'],apk.read('assets/800x480/10'))
            classes.update(restore_loading_screen(classes,apk,api))
            classes.update(patch_farm_hud_text(classes,apk,api))
            classes.update(patch_pause(classes,apk,api))
            classes.update(build_zoom(classes,apk,api))
            classes.update(patch_farm_edits(classes,apk))
            changes = world | media | sprites | renderer | classes
            # The source APK's default launcher icon is the original 512 px artwork.
            changes['icon.png'] = apk.read('res/NR.png')
            changes['999'] = resource_index(jar, changes)
            rebuild(jar, changes, rebuilt)
        result = temp / filename
        subprocess.run([sys.executable, str(ROOT / 'tools/timing/build.py'),
                        '--input', str(rebuilt), '--api', str(api),
                        '--output', str(result)], check=True)
        with ZipFile(result) as jar:
            if jar.testzip() or 'GloftGF2M.class' not in jar.namelist():
                raise ValueError('JAR generado dañado o incompleto.')
            verify_offline(jar)
            manifest = jar.read('META-INF/MANIFEST.MF').decode('utf8').splitlines()
        # MIDP matches the identity fields with the manifest exactly.
        fields = [s for s in manifest if s.startswith(
            ('MIDlet-Name:', 'MIDlet-Vendor:', 'MIDlet-Version:', 'MIDlet-1:', 'MIDlet-Icon:',
             'MicroEdition-Configuration:', 'MicroEdition-Profile:', 'MIDlet-Touch-Support:', 'MIDlet-ScreenSize:', 'Nokia-UI-Enhancement:'))]
        fields += ['MIDlet-Jar-URL: ' + filename, f'MIDlet-Jar-Size: {result.stat().st_size}']
        (temp / 'GreenFarm3-MX.jad').write_bytes(('\r\n'.join(fields) + '\r\n').encode())
        report = {'sourceJar': JAR_DIGEST, 'sourceApk': APK_DIGEST, 'jarSha256': digest(result),
                  'world': world_report, 'catalog': catalog_report,
                  'media': media_report, 'sprites': sprite_report,
                  'timingPatchApplied': True, 'targetFps': 60,
                  'originalSceneSize': [800,480]}
        (temp / 'build.json').write_text(json.dumps(report, ensure_ascii=False, indent=2),
                                         encoding='utf-8')
        for p, dest in ((result, target), (temp / 'GreenFarm3-MX.jad', directory / 'GreenFarm3-MX.jad'),
                        (temp / 'build.json', directory / 'build.json')):
            os.replace(p, dest)
    print(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jar', type=Path, required=True)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=ROOT / 'build')
    parser.add_argument('--api', type=Path, help='API MIDP local. Por defecto se prepara FreeJ2ME-Plus.')
    parser.add_argument('--decoder', help='Optional audio decoder for conversion')
    build(parser.parse_args())
