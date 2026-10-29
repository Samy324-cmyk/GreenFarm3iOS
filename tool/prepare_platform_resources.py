"""Copy raw Android resources only after matching their exact bytes in the APK."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def prepare(apk, decoded, output):
    by_hash = {}
    with zipfile.ZipFile(apk) as archive:
        for entry in archive.infolist():
            if not entry.is_dir():
                digest = hashlib.sha256(archive.read(entry)).hexdigest()
                by_hash.setdefault(digest, []).append(entry.filename)
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for source in sorted((decoded / 'res' / 'raw').iterdir()):
        data = source.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest not in by_hash:
            raise ValueError(f'Raw resource is not byte-identical to APK: {source.name}')
        (output / source.name).write_bytes(data)
        records.append({'resource': f'res/raw/{source.name}',
                        'asset': f'assets/platform/raw/{source.name}',
                        'sha256': digest, 'archiveEntries': by_hash[digest]})
    manifest = {'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'resources': records}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('decoded', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = prepare(args.apk, args.decoded, args.output)
    print(f"Verified and copied {len(result['resources'])} original raw resources")
