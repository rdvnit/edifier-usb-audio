# Verification and manual acceptance

## Implementation-worker verification (2026-10-12)

Performed using the real system SDK, not mocked hardware responses:

- Host: macOS 27.0.1 (26A434), Apple silicon. Apple Swift 6.4, language mode Swift 5, macOS 13 deployment target.
- `bash scripts/test.sh`: **52 tests, 0 failures**. Tests cover USB-versus-Bluetooth discovery, wrong/ambiguous registry identity, PCM constraints, advertised rates, complete stable IDs, readback tolerance, mixable duplicate preference, stale-device mutation guards and quiet-waveform amplitude/fades/channel separation. These are pure tests; they do not call a HAL setter or start playback.
- `bash scripts/build.sh --universal`: SDK-only ARM64 and x86_64 compilation with `-warnings-as-errors`; app and CLI produced. Ad-hoc signature verified with `codesign --verify --strict`; `Info.plist` lint passed. Universal slices confirmed by `lipo`.
- Both `build/m60-audio --diagnose` and the app's `--diagnose` executable path returned **exit 0**, with identical parsed JSON for a live verified M60. Invalid mutation-style CLI arguments were rejected with exit **64**. `nm -u` confirmed the standalone CLI does not import `AudioObjectSetPropertyData` or `AudioOutputUnitStart`.
- Sharing archive integrity check passed: **26 files**, source plus universal app/CLI. A byte-level scan found none of the live host's local home path, observed device serials or current unrelated output-device name. No local `verification/` files are included.
- Live USB/UID correlation succeeded with VID `2d99`, PID `a094`, exact product/manufacturer/serial agreement. Physical stereo integer PCM was **16-bit / 48,000 Hz**, 4 bytes/frame, flags `0x0c`; virtual stereo float PCM was **32-bit / 48,000 Hz**, 8 bytes/frame, flags `0x09`.
- Driver advertised nominal rates **48,000 and 96,000 Hz** and **eight raw physical entries**: 16/24-bit at each rate with mixable `0x0c` and non-mixable `0x4c` variants. The picker exposes four meaningful rate/depth choices, preferring mixable PCM.
- Read-only offscreen native SwiftUI render succeeded using the live model. The locally captured preview was visually checked for format/routing controls, clipping and legibility. It is not included in sharing archives because it may contain current device names.

No audio property was mutated, no tone was played, no device was unplugged or paired, no firmware/system setting was changed, and no software was installed globally by the implementation worker. System routing/running state can change independently during these snapshots; do not interpret it as fixed product behavior.

Local raw evidence lives under `verification/` and is deliberately gitignored/excluded from archives. Shareable documentation omits the host's local username, device serial, transient numeric IDs and unrelated output-device names.

## Primary independent live acceptance (2026-10-12)

- Re-ran the 52 pure tests: zero failures. Independently verified the local app signature and universal ARM64/x86_64 slices.
- Launched the actual native app and exercised its physical-format picker and confirmation UI. Initially it reported physical 16-bit/48 kHz, matching the standalone CLI and an independently compiled C CoreAudio probe. Opening the app did not change that format.
- With the user's explicit permission, the format change was confirmed during the interactive session. The app displayed `Verified physical format: 48000 Hz · 24-bit · 2 ch · integer PCM`. Independent CLI and C probe readback both confirmed packed stereo 24-bit/48 kHz, 6 bytes/frame, flags `0x0c`; the virtual format remained float32/48 kHz.
- Exercised the quiet-test confirmation UI. The user explicitly confirmed hearing left, then right from the M60. This is human listening acceptance, not an acoustic or bit-perfect measurement.
- Fresh CLI readback after the listening test confirmed the physical format remained 24-bit/48 kHz and both default output/system-alert routes were unchanged from the immediately preceding snapshot. The system default was a different device during this test; the tone was therefore accepted on M60 without changing default routing.
- No speaker volume/mute change, route write, firmware operation, additional driver, privileged operation or installation was performed by the primary. Cancel-without-change, real unplug/reconnect, video-call latency and keyboard/VoiceOver acceptance have not been established. Some background automation attempts at native confirmation sheets were refused; the user participated in confirmation, so no claim of fully unattended UI automation is made.

## Review-driven repairs

The initial independent review found one strict-identity blocker and three reliability/privacy issues. All four were repaired locally:

- The known fingerprint now requires manufacturer `bestechnic`, not merely agreement between an arbitrary registry manufacturer and UID. Two regression checks failed before the repair and now pass.
- Route readback now waits for a matching property for up to ten bounded reads, tolerating asynchronous HAL changes and transient read failures. The setter is still called once only; timeout is reported as unverified completion with possible partial change. Four pure readback-policy tests cover delayed success, timeout, transient failure and zero attempts. Actual route writes remain unexercised.
- A confirmed action is queued behind an in-flight read on the existing serial hardware queue, retaining the original device snapshot. It is no longer silently discarded when `refreshing` is true. Duplicate confirmed actions receive a visible refusal. Injected AppModel tests failed before this repair and now verify order, exactly-once execution, snapshot preservation, success/failure publication and busy-state cleanup without touching hardware.
- The entire `/verification/` directory is gitignored, including identifying screenshots, and remains excluded from the archive.

After repair: **58 model/waveform/readback tests plus 8 injected scheduling tests, zero failures**. The universal ARM64/x86_64 app and CLI rebuilt with warnings treated as errors; ad-hoc signature and plist checks passed. The quiet-tone implementation was unchanged from the accepted listening test. Focused independent rereview found no blocking production issues within these four repairs. It also found that injected test callbacks inherited MainActor isolation under optional runtime actor checking; those callbacks were moved to nonisolated factories, and the scheduling suite now runs with `-enable-actor-data-race-checks`. The final 58 + 8 tests pass with zero failures and no compiler warnings. This is scoped verification, not public-release certification.

## Compact interface revision

- Normal panel: 380 × 620 points, with bounds up to 400 × 650. Always-dark graphite background, bold device heading, large original white M60 illustration, USB connection pill, compact Quality/Output/Alerts controls and test/info/refresh icons. Technical information and complete notices live in a scrollable information sheet.
- Core audio, action, identity, polling, waveform and CLI source files were compared against a pre-redesign checksum baseline and remained byte-identical. Format-menu selections still require confirmation; routing controls are truthful one-way Use M60 buttons, not simulated power/off switches. USB connection is not presented as a readback of the speaker's selected hardware input.
- Primary independently reran 66 tests with zero failures and verified the universal app's ad-hoc signature. Primary compiled and executed the native preview renderer with the macOS 13 deployment target, warnings-as-errors and runtime actor checks. Live connected and explicitly synthetic disconnected 380 × 620 renders were visually inspected; all normal controls fit without overflow. The synthetic render is a UI fixture, not a claim of a real USB disconnect test.
- Artwork is original SwiftUI geometry. No vendor photograph or logo is distributed; the white cabinet finish is illustrative, not autodetected.
- Read-only volume capability probe found writable output master scalar volume/mute and virtual main volume; individual left/right channel volume properties were absent. The M60 was selected as default output. Mac-side volume can control USB playback gain independently of the speaker touch setting. This was capability inspection, not a volume write or acoustic transfer measurement.
- No audio mutation, playback, speaker volume change, system configuration change or publication was performed for the redesign. Focused independent UI review found no blockers in confirmation safety, truthful state labels, error visibility, compact layout, accessibility labels or build integration. Information-sheet presentation and VoiceOver interaction remain source-reviewed rather than interactively exercised.

## EDIFIER USB Audio 0.1.0 local release build

- Renamed the app, bundle metadata, window title, read-only CLI and archive branding. Bundle ID is `io.github.rdvnit.EDIFIERUSBAudio`, version `0.1.0`, build `1`; minimum system version remains `13.0`. EDIFIER M60 device labels and exact known USB-only identity policy are unchanged.
- `bash scripts/test.sh`: 58 pure model/waveform/readback tests and 8 injected AppModel scheduling tests passed with zero failures. Scheduling tests retain runtime actor checks. No hardware mutation or playback was performed.
- `bash scripts/package-dmg.sh` rebuilt the universal ARM64/x86_64 app and standalone CLI with warnings treated as errors. App plist lint and strict ad-hoc signature verification passed. A second packaging run also succeeded; the app executable hashes were unchanged, while the DMG hash differed. This is a repeatable build/package workflow, not byte-identical disk-image reproducibility.
- `hdiutil verify` accepted the compressed UDZO image. The packaging script mounted it read-only and compared all app files, directories, SHA-256 hashes, modes and metadata against the built app, checked the Applications shortcut and install text, verified the copied signature and detached the image.
- An additional independent local verification harness checked a non-writable mounted volume, exact visible payload (`EDIFIER USB Audio.app`, `/Applications` symlink, `INSTALL.txt`), both executable slices and permissions, version/identity, strict signature and SHA-256 checksum-file agreement. All checks passed and the image was detached.
- Built app, standalone CLI and mounted app `--diagnose` paths each returned exit 0 with valid JSON for the connected verified M60. Mutation-style arguments were rejected with exit 64. `nm -u` found no HAL setter or AudioUnit initialization/start imports in the standalone CLI.
- Mounted payload bytes contained no local home paths or serials observed in these diagnostic snapshots. The DMG contains no source, CLI or local verification data. Hash comparisons confirmed the six core engine/model files, ContentView, device artwork and both test sources remained byte-identical.
- Local logs, diagnostic snapshots, complete bundle manifests and artifact hashes remain in ignored `verification/`. The final DMG and `SHA256SUMS.txt` are under ignored `build/`. This worker did not publish, install/replace the application, change system settings, write audio properties or play audio.
- The image remains locally ad-hoc signed, not Developer ID signed or Apple-notarized. Intel and macOS 13 runtime testing remain outstanding. macOS 27 emitted deprecation warnings for `hdiutil` image creation/detachment, but both operations and verification succeeded.

## Final distribution repair

Independent release review found that the initial DMG did not include the complete MIT copyright/permission/warranty notice. Packaging was corrected to include a root `LICENSE` file byte-identical to the source notice, and to require it in the mounted-payload allowlist and readback checks. The app bundle and audio engine are unchanged. The DMG and its checksum were rebuilt after this repair and passed `hdiutil verify`, source-identical license readback, complete mounted app hash/mode/metadata comparison and strict signature verification. The prior image hash is not the final release hash. Attach/detach handling also addresses only its own temporary mountpoint inside a `try/finally`, with timeouts on attach/detach; exceptional failure-path behavior is not claimed exhaustively tested.

## Limits of these checks

- Physical-format writes, default-route writes, finite AudioUnit playback, and real unplug/reconnect behavior are implemented but **not exercised by the implementation worker**. They need explicit user consent and independent validation. Do not claim them tested solely because the app compiled.
- The UI check is an offscreen render, not interactive accessibility/UI automation. Real-window resizing, keyboard/VoiceOver traversal, dialogs and end-to-end user workflows still need manual acceptance.
- x86_64 compiled, but Intel and macOS 13 runtime compatibility remain untested.
- No bit-perfect, analog/acoustic, latency/video-call or internal speaker-DSP measurements were performed.
- These historical checks do not establish Developer ID release signing or notarization. See the README for current release and packaging instructions.

## Consent-gated manual checklist

1. Launch the app with the M60 connected. Confirm readouts against Audio MIDI Setup / read-only JSON; opening/refreshing must not change format or routes.
2. Verify the initial selected format is the current physical format. Confirm duplicate non-mixable entries are hidden from the picker but retained in raw evidence. Select an alternative, cancel its confirmation, and confirm nothing changed.
3. With permission and other playback paused, apply advertised **24-bit / 48 kHz**. Check the in-app success message and a fresh `--diagnose` physical ASBD/readback. Do not infer audible improvement from the write's success.
4. With separate permission, change default output and system-alert routes one at a time; read back each and verify the other route remains unchanged. Restore any prior route only with permission.
5. Turn down the speaker's own volume, pause playback and explicitly confirm the quiet test. Listen for left then right. Verify it stops within roughly 2.2 seconds, does not use input/microphone, remains bound to M60 even when another device is default, and leaves routing/physical format unchanged. Treat an output-unit failure as a real defect, not a passed listening test.
6. With permission, unplug/reconnect USB. Within about three seconds controls should disable/repopulate. Stale dialog actions must be rejected after identity change. Bluetooth-only, missing/duplicate USB identity and lookalike names must never enable M60 actions.
7. Check the intentionally dark compact panel at 380 × 620 points (up to 400 × 650), keyboard and VoiceOver labels, diagnostics copy privacy warning, information-sheet scrolling and dismissal.
8. Close the app. No helper daemon, auto-format changes or ongoing polling should remain.

## Independent validation entry points

The app has no mutation CLI flags; unknown flags are rejected. Its standalone CLI does not link the write or AudioUnit code. To independently exercise the exact implementation with consent, use the visible confirmation-gated UI, or compile a local Swift harness against `Models.swift`, `AudioHardware.swift`, `AudioActions.swift`, `QuietToneSignal.swift` and `QuietTone.swift`:

- Read `AudioHardware.diagnose().m60Devices` and select the one uniquely verified device.
- Read `device.streams[0].choices` and find the advertised mixable 24-bit/48 kHz entry. Never fabricate an ASBD.
- Call `AudioActions.applyFormat(device, streamID: device.streams[0].id, format: choice)` once; it revalidates and reads back. Read diagnostics independently afterward.
- Only after explicit volume/playback consent, call `QuietTonePlayer.play(device)`; it uses HAL output bound to the revalidated M60 and does not fall back to default output.

That harness is an independent validation mechanism, not authorization to run mutations automatically.
