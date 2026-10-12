#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 0 ]; then
  printf 'Usage: bash scripts/package-dmg.sh\n' >&2
  exit 64
fi
# Always rebuild both architectures. No third-party tools or downloads.
bash scripts/build.sh --universal
python3 - <<'PY'
import hashlib
import os
import pathlib
import plistlib
import stat
import subprocess
import tempfile

root = pathlib.Path.cwd()
build = root / 'build'
name = 'EDIFIER USB Audio'
app = build / (name + '.app')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
expected = {
    'CFBundleName': name, 'CFBundleDisplayName': name, 'CFBundleExecutable': name,
    'CFBundleIdentifier': 'io.github.rdvnit.EDIFIERUSBAudio',
    'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '13.0',
}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Unexpected bundle metadata: {key}')
exe = app / 'Contents/MacOS' / name
arches = subprocess.check_output(['xcrun', 'lipo', '-archs', str(exe)], text=True).split()
if set(arches) != {'arm64', 'x86_64'}:
    raise SystemExit('The release app must contain both arm64 and x86_64.')
subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
signature = subprocess.run(['/usr/bin/codesign', '-dv', str(app)], capture_output=True, text=True, check=True)
if 'Signature=adhoc' not in signature.stderr:
    raise SystemExit('This packaging workflow expects the documented local ad-hoc signature.')

def manifest(bundle):
    result = {}
    for p in sorted(bundle.rglob('*')):
        relative = str(p.relative_to(bundle))
        mode = stat.S_IMODE(p.lstat().st_mode)
        if p.is_symlink():
            result[relative] = ('symlink', os.readlink(p), mode)
        elif p.is_file():
            data = p.read_bytes()
            if any(token in data for token in (b'/Users/', b'/home/')):
                raise SystemExit(f'Local home path found in bundle file: {relative}')
            result[relative] = ('file', hashlib.sha256(data).hexdigest(), mode)
        elif p.is_dir():
            result[relative] = ('directory', mode)
        else:
            raise SystemExit(f'Unexpected bundle entry: {relative}')
    return result

baseline = manifest(app)
allowed_files = {'Contents/Info.plist', 'Contents/MacOS/EDIFIER USB Audio',
                 'Contents/Resources/AppIcon.icns', 'Contents/_CodeSignature/CodeResources'}
allowed_dirs = {'Contents', 'Contents/MacOS', 'Contents/Resources', 'Contents/_CodeSignature'}
if (set(baseline) != allowed_files | allowed_dirs
        or any(baseline[path][0] != 'file' for path in allowed_files)
        or any(baseline[path][0] != 'directory' for path in allowed_dirs)):
    raise SystemExit('The app contains unexpected entries; refusing to package extra data.')
image = build / 'EDIFIER-USB-Audio-0.1.0-universal.dmg'
license_bytes = (root / 'LICENSE').read_bytes()
if b'MIT License' not in license_bytes or b'Permission is hereby granted' not in license_bytes:
    raise SystemExit('The complete MIT license notice is required for distribution.')
install = '''EDIFIER USB Audio 0.1.0

Requires macOS 13 or later. Universal Apple silicon and Intel app.
Only the verified EDIFIER M60 USB fingerprint is supported. Bluetooth and
other EDIFIER devices are not supported. This is an unofficial utility,
not a driver, firmware updater, EQ or audio enhancer.

Download access requires permission to the private GitHub repository:
https://github.com/rdvnit/edifier-usb-audio/releases/latest

Drag EDIFIER USB Audio.app to Applications, then eject this disk image.
Connect M60 with a data-capable USB cable and select USB on the speaker.
Opening or refreshing the app is read-only. Format, route and finite test
playback actions require explicit confirmation. Turn down the speaker's
own volume before confirming the optional test. Diagnostics can contain
private device names and identifiers; review them before sharing.

This app has a local ad-hoc signature only. It is NOT Developer ID signed
or notarized by Apple. Gatekeeper may block the downloaded app. Building
from the reviewed source with Apple's development tools is recommended
if it is blocked. Do not disable Gatekeeper or SIP globally.

Intel and macOS 13 runtime compatibility have not been tested.
Unofficial community software, not affiliated with or endorsed by EDIFIER.
'''
with tempfile.TemporaryDirectory(prefix='.dmg-stage-', dir=build) as temp:
    stage = pathlib.Path(temp)
    copied = stage / app.name
    subprocess.run(['/usr/bin/ditto', str(app), str(copied)], check=True)
    if manifest(copied) != baseline:
        raise SystemExit('Staged bundle hashes or permissions differ from the build.')
    (stage / 'Applications').symlink_to('/Applications')
    (stage / 'INSTALL.txt').write_text(install, encoding='utf-8')
    (stage / 'LICENSE').write_bytes(license_bytes)
    subprocess.run(['hdiutil', 'create', '-srcfolder', str(stage), '-volname', name,
                    '-fs', 'HFS+', '-format', 'UDZO', '-ov', str(image)], check=True)
subprocess.run(['hdiutil', 'verify', str(image)], check=True)
with tempfile.TemporaryDirectory(prefix='.dmg-mount-', dir=build) as temp:
    mount = pathlib.Path(temp)
    try:
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                        '-mountpoint', str(mount), '-plist', str(image)],
                       capture_output=True, check=True, timeout=120)
        mounted = mount / app.name
        if {p.name for p in mount.iterdir() if not p.name.startswith('.')} != {app.name, 'Applications', 'INSTALL.txt', 'LICENSE'}:
            raise SystemExit('Unexpected disk image contents.')
        if not (mount / 'Applications').is_symlink() or os.readlink(mount / 'Applications') != '/Applications':
            raise SystemExit('Applications shortcut is incorrect.')
        if (mount / 'INSTALL.txt').read_text(encoding='utf-8') != install or manifest(mounted) != baseline:
            raise SystemExit('Mounted payload differs from the verified build or install text.')
        if (mount / 'LICENSE').read_bytes() != license_bytes:
            raise SystemExit('Mounted MIT license differs from the source notice.')
        if plistlib.loads((mounted / 'Contents/Info.plist').read_bytes()) != info:
            raise SystemExit('Mounted bundle metadata differs from the build.')
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(mounted)], check=True)
        print('Readonly image mount: payload, bundle hashes, permissions, metadata and signature verified.')
    finally:
        # Address only this scoped mountpoint, including after attach/parse failures.
        if os.path.ismount(mount):
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True, timeout=120)
digest = hashlib.sha256(image.read_bytes()).hexdigest()
checksum = build / 'SHA256SUMS.txt'
checksum.write_text(f'{digest}  {image.name}\n', encoding='ascii')
print(f'DMG: {image}\nSHA256: {digest}\nChecksum: {checksum}')
print('Rebuildable packaging workflow; byte-identical DMG output is not promised.')
PY
