#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
arch="$(uname -m)"
case "$arch" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 1;; esac
xcrun swiftc -swift-version 5 -target "${arch}-apple-macosx13.0" -warnings-as-errors Sources/Models.swift Sources/QuietToneSignal.swift Tests/ModelTests.swift -o build/model-tests
build/model-tests
xcrun swiftc -swift-version 5 -target "${arch}-apple-macosx13.0" -warnings-as-errors -enable-actor-data-race-checks Sources/Models.swift Sources/AudioHardware.swift Sources/AudioActions.swift Sources/QuietToneSignal.swift Sources/QuietTone.swift Sources/AppModel.swift Tests/SchedulingTests.swift -o build/scheduling-tests
build/scheduling-tests
