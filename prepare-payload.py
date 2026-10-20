"""Assemble the tested payload from locally supplied, unmodified Google packages."""
from pathlib import Path
import argparse
import hashlib
import io
import zipfile

P = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
for name in ('gsf', 'gms', 'store'):
    parser.add_argument('--'+name, type=Path, required=True)
args = parser.parse_args()
expected = dict(line.split('  ', 1)[::-1] for line in
                (P/'config/expected-payload.sha256').read_text(encoding='utf-8').splitlines())
files = {}
with zipfile.ZipFile(args.gms) as gms, zipfile.ZipFile(args.store) as store:
    store_apks = {Path(name).name: store.read(Path(name).name) for name in expected
                  if name.startswith('system/priv-app/Phonesky/') and name.endswith('.apk')}
    for name in expected:
        if name.endswith('/gsf.apk'):
            data = args.gsf.read_bytes()
        elif name.endswith('/gms.apk'):
            data = args.gms.read_bytes()
        elif name.endswith('.xml'):
            data = (P/'config'/Path(name).name).read_bytes()
        elif name.endswith('.apk'):
            data = store_apks[Path(name).name]
        elif '/GooglePlayServices/lib/arm64/' in name:
            data = gms.read('lib/arm64-v8a/'+Path(name).name)
        else:
            candidates = []
            for apk in store_apks.values():
                with zipfile.ZipFile(io.BytesIO(apk)) as split:
                    entry = 'lib/arm64-v8a/'+Path(name).name
                    if entry in split.namelist():
                        candidates.append(split.read(entry))
            if not candidates or any(item != candidates[0] for item in candidates):
                raise SystemExit('Missing or conflicting native library: '+name)
            data = candidates[0]
        if hashlib.sha256(data).hexdigest() != expected[name]:
            raise SystemExit('Does not match tested payload: '+name)
        files[name] = data
destination = P/'payload'
if destination.exists():
    raise SystemExit('payload already exists; inspect it before replacing anything')
for name, data in files.items():
    target = destination/name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
print('Prepared and verified', len(files), 'files')
