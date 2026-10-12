#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build first. This archive deliberately excludes all local diagnostics, logs and screenshots.
test -f 'build/EDIFIER USB Audio.app/Contents/MacOS/EDIFIER USB Audio'
/usr/bin/codesign --verify --strict 'build/EDIFIER USB Audio.app'
python3 - <<'PY'
import pathlib, zipfile
root = pathlib.Path.cwd()
files = []
for name in ('Sources', 'Tests', 'Tools', 'Resources', 'scripts', 'docs'):
    files.extend(p for p in (root/name).rglob('*') if p.is_file())
files.extend(root/name for name in ('README.md', 'LICENSE', '.gitignore'))
app = root/'build/EDIFIER USB Audio.app'
files.extend(p for p in app.rglob('*') if p.is_file())
files.append(root/'build/edifier-usb-audio')
archive = root/'build/EDIFIER-USB-Audio-local.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for p in sorted(set(files)):
        if p.name == '.DS_Store':
            continue
        # zipfile.write preserves Unix executable bits for the local app and scripts.
        z.write(p, pathlib.Path('EDIFIER-USB-Audio')/p.relative_to(root))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any('/verification/' in n for n in z.namelist())
    print(f'Archive verified: {archive.name} ({len(z.namelist())} files). No local diagnostics included.')
PY
