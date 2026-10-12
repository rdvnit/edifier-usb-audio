#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in "" ) arches=("$(uname -m)");; --universal ) arches=(arm64 x86_64);; *) printf 'Usage: bash scripts/build.sh [--universal]\n' >&2; exit 64;; esac
mkdir -p build
sdk="$(xcrun --show-sdk-path)"
app='build/EDIFIER USB Audio.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
common=(Sources/Models.swift Sources/AudioHardware.swift Sources/DiagnosticCommand.swift)
gui=(Sources/AudioActions.swift Sources/QuietToneSignal.swift Sources/QuietTone.swift Sources/AppModel.swift Sources/DeviceArtwork.swift Sources/ContentView.swift Sources/App.swift)
for arch in "${arches[@]}"; do
  case "$arch" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 1;; esac
  target="${arch}-apple-macosx13.0"
  xcrun swiftc -swift-version 5 -sdk "$sdk" -target "$target" -warnings-as-errors -O "${common[@]}" "${gui[@]}" -o "build/app-$arch"
  xcrun swiftc -swift-version 5 -sdk "$sdk" -target "$target" -warnings-as-errors -O "${common[@]}" Sources/CLI.swift -o "build/cli-$arch"
done
if [ "${#arches[@]}" -eq 2 ]; then
  xcrun lipo -create build/app-arm64 build/app-x86_64 -output "$app/Contents/MacOS/EDIFIER USB Audio"
  xcrun lipo -create build/cli-arm64 build/cli-x86_64 -output build/edifier-usb-audio
else
  cp "build/app-${arches[0]}" "$app/Contents/MacOS/EDIFIER USB Audio"
  cp "build/cli-${arches[0]}" build/edifier-usb-audio
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun swiftc -parse-as-library -warnings-as-errors Tools/MakeIcon.swift -o build/make-icon
build/make-icon build/AppIcon.iconset
xcrun iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc signature for this local build. Not Developer ID signed or notarized.
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
printf '\nBuilt: %s\nCLI: build/edifier-usb-audio\nArchitectures: %s\nLocal ad-hoc signature only; no notarization.\n' "$app" "${arches[*]}"
