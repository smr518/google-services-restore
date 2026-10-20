from pathlib import Path
import hashlib, zipfile, argparse

P=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--payload',type=Path,default=P/'payload/system')
payload=parser.parse_args().payload.resolve()
assets=P/'assets'
out=assets/'payload.zip'
if not payload.is_dir():
    raise SystemExit('Missing verified v2 payload; do not substitute unknown APKs')
files=sorted(p for p in payload.rglob('*') if p.is_file())
if not files or len(files)!=62:
    raise SystemExit('Unexpected payload contents; review before packaging')
manifest=[]
for p in files:
    manifest.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  system/'+p.relative_to(payload).as_posix())
manifest_text='\n'.join(manifest)+'\n'
expected_manifest=(P/'config/expected-payload.sha256').read_text(encoding='utf-8')
if manifest_text != expected_manifest:
    raise SystemExit('Payload differs from the tested SHA-256 manifest; review compatibility first')
if out.exists() and (assets/'payload.sha256').exists() and (assets/'payload.sha256').read_text()==manifest_text:
    try:
        with zipfile.ZipFile(out) as z:
            expected={line.split('  ',1)[1]:line.split('  ',1)[0] for line in manifest}
            if set(z.namelist())==set(expected) and all(hashlib.sha256(z.read(n)).hexdigest()==sha for n,sha in expected.items()):
                print('Verified existing payload archive;',out.stat().st_size,'bytes')
                raise SystemExit(0)
    except (zipfile.BadZipFile, KeyError):
        pass
manifest=[]
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files:
        name='system/'+p.relative_to(payload).as_posix()
        manifest.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+name)
        zi=zipfile.ZipInfo(name,(2026,10,20,0,0,0))
        zi.compress_type=zipfile.ZIP_DEFLATED
        zi.external_attr=0o100644<<16
        z.writestr(zi,p.read_bytes())
(assets/'payload.sha256').write_text(manifest_text,encoding='utf-8',newline='\n')
print('Packaged',len(files),'files;',out.stat().st_size,'bytes')
