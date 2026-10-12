import SwiftUI
import AppKit
import CoreAudio

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pending: PendingAction?
    @State private var showTechnical = false
    private let accent = Color(red: 0.43, green: 0.83, blue: 0.79)
    private let background = Color(red: 0.105, green: 0.115, blue: 0.125)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("EDIFIER M60")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-0.8)
                Text("Desktop speakers").font(.system(size: 13)).foregroundStyle(.secondary)
            }.frame(height: 64)

            if (model.report?.m60Devices.count ?? 0) > 1 {
                Picker("Speaker", selection: $model.selectedDevice) {
                    ForEach(model.report?.m60Devices ?? []) { device in
                        Text("\(device.name) · \(String(format: "%08x", device.fingerprint?.locationID ?? 0))")
                            .tag(Optional(device.id))
                    }
                }.labelsHidden().controlSize(.small).padding(.top, 8)
            }

            DeviceArtwork(connected: model.device?.alive == true)
                .frame(height: (model.report?.m60Devices.count ?? 0) > 1 ? 202 : 230)
                .padding(.top, 8)

            connectionPill
            Text(model.device == nil ? "Connect your M60 via USB" : " ")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(height: 26)

            settings
                .padding(.top, 10)
            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 400,
               minHeight: 620, idealHeight: 620, maxHeight: 650)
        .background(background)
        .preferredColorScheme(.dark)
        .tint(accent)
        .alert(item: $pending) { action in
            Alert(title: Text(action.title), message: Text(action.message),
                  primaryButton: .default(Text(action.confirmLabel)) { model.perform(action) },
                  secondaryButton: .cancel())
        }
        .sheet(isPresented: $showTechnical) { technicalSheet }
        .onChange(of: model.selectedDevice) { _ in model.selectedFormat = ""; model.reconcileFormat() }
    }

    private var connectionPill: some View {
        HStack(spacing: 7) {
            Circle().fill(model.device?.alive == true ? accent : Color.gray).frame(width: 6, height: 6)
            Image(systemName: "cable.connector").font(.system(size: 12))
            Text(model.device?.alive == true ? "USB audio" : (model.device == nil ? "Not connected" : "USB unavailable"))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(model.device?.alive == true ? accent : Color.secondary)
        .padding(.horizontal, 12).frame(height: 28)
        .background(Color.white.opacity(0.045), in: Capsule())
        .accessibilityIdentifier("connection-mode")
    }

    private var settings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                rowTitle("Quality", icon: "waveform.path")
                Spacer(minLength: 4)
                Menu {
                    if let device = model.device, let stream = model.stream {
                        ForEach(stream.choices) { format in
                            Button {
                                model.selectedFormat = format.id
                                pending = .format(device, stream.id, format)
                            } label: {
                                if stream.physical.map({ format.matches($0) }) == true {
                                    Label(formatMenuLabel(format), systemImage: "checkmark")
                                } else { Text(formatMenuLabel(format)) }
                            }
                            .disabled(stream.physical.map({ format.matches($0) }) == true)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(physicalLabel).font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }.foregroundStyle(model.device == nil ? Color.secondary : Color.white.opacity(0.88))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(model.device?.canMutate == true ? accent : Color.gray)
                .disabled(!formatEnabled)
                .opacity(formatEnabled ? 1 : 0.55)
                .accessibilityLabel("Physical USB audio format: \(physicalLabel)")
                .accessibilityIdentifier("physical-format-picker")
                .help("Choose an advertised USB format. A change requires confirmation.")
            }.frame(height: 50).padding(.horizontal, 14)
            rowDivider
            routeRow("Output", icon: "speaker.wave.2", selected: model.device?.isDefaultOutput == true) {
                guard let device = model.device else { return }; pending = .output(device)
            }
            rowDivider
            routeRow("Alerts", icon: "bell", selected: model.device?.isDefaultSystemOutput == true) {
                guard let device = model.device else { return }; pending = .alerts(device)
            }
        }
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var formatEnabled: Bool {
        !model.busy && model.device?.canMutate == true && model.stream?.physicalSettable == true && model.stream?.choices.isEmpty == false
    }
    private var physicalLabel: String {
        guard let device = model.device else { return "Unavailable" }
        guard device.streams.count == 1, let physical = device.streams.first?.physical else {
            return device.streams.count > 1 ? "Multiple streams" : "Unavailable"
        }
        return compactFormat(physical)
    }
    private func compactFormat(_ format: PCMFormat) -> String {
        "\(format.bits)-bit / \(rateLabel(format.sampleRate / 1000)) kHz"
    }
    private func formatMenuLabel(_ format: PCMFormat) -> String {
        compactFormat(format) + " · \(format.encoding)" + (format.flags & kAudioFormatFlagIsNonMixable != 0 ? " · non-mixable" : "")
    }
    private var rowDivider: some View {
        Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1).padding(.leading, 44)
    }
    private func rowTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 18)
            Text(title).font(.system(size: 13, weight: .medium))
        }
    }
    private func routeRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            rowTitle(title, icon: icon)
            Spacer()
            Button(action: action) {
                HStack(spacing: 5) {
                    if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    Text(selected ? "M60" : "Use M60").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(selected ? accent : (model.device?.canMutate == true ? Color.white.opacity(0.9) : Color.secondary))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? accent.opacity(0.09) : Color.white.opacity(0.065), in: Capsule())
            }
            .buttonStyle(.plain).disabled(selected || model.busy || model.device?.canMutate != true)
            .accessibilityLabel(selected ? "M60 selected for \(title.lowercased())" : "Use M60 for \(title.lowercased())")
            .accessibilityIdentifier(title == "Output" ? "use-m60-output" : "use-m60-alerts")
        }.frame(height: 50).padding(.horizontal, 14)
    }

    private var hasErrors: Bool {
        !(model.report?.errors.isEmpty ?? true) || !(model.device?.errors.isEmpty ?? true) ||
        model.device?.streams.contains(where: { !$0.errors.isEmpty }) == true ||
        (model.device == nil && !(model.report?.usbFingerprints.isEmpty ?? true))
    }
    private var footer: some View {
        HStack(spacing: 8) {
            if model.notice != nil || hasErrors {
                Button { showTechnical = true } label: {
                    Label(model.noticeIsError || hasErrors ? "Notice" : "Updated",
                          systemImage: model.noticeIsError || hasErrors ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 11)).foregroundStyle(model.noticeIsError || hasErrors ? Color.orange : accent)
                }.buttonStyle(.plain).help("Read the full operation result and diagnostic notices")
                    .accessibilityIdentifier("operation-result")
            } else {
                Text("USB settings").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.busy { ProgressView().controlSize(.mini).accessibilityLabel("Reading or applying audio properties") }
            iconButton("play.circle", label: "Play quiet stereo test", help: "Quiet left/right test; confirmation required") {
                guard let device = model.device else { return }; pending = .test(device)
            }
            .disabled(model.busy || model.device?.canMutate != true || model.device?.streams.count != 1)
            .accessibilityIdentifier("quiet-stereo-test")
            iconButton("info.circle", label: "Device information", help: "Connection details, formats and diagnostics") { showTechnical = true }
            iconButton("arrow.clockwise", label: "Refresh devices", help: "Read device properties without changing audio settings") { model.refresh() }
                .disabled(model.busy).keyboardShortcut("r", modifiers: .command)
        }.frame(height: 32)
    }
    private func iconButton(_ icon: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(help)
    }

    private var technicalSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Device information").font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { showTechnical = false }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notice = model.notice {
                        Label(notice, systemImage: model.noticeIsError ? "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundStyle(model.noticeIsError ? Color.orange : accent)
                    }
                    ForEach(model.report?.errors ?? [], id: \.self) { Text($0).foregroundStyle(.orange) }
                    if let device = model.device { deviceDetails(device) } else { disconnectedDetails }
                    informationSection("About USB audio") {
                        Text("USB audio describes the verified Mac connection, not a readback of the speaker's selected input mode. Speaker power, input mode and EQ are not known or controlled here.")
                        Text("Mac volume controls USB playback. Speaker touch volume is separate.")
                        Text("A reported 16-bit format is not evidence that macOS USB support is broken. Choosing 24-bit can reduce additional quantization when software changes volume or mixes audio, but cannot recover detail absent from the source.")
                        Text("24-bit / 48 kHz is practical for mixed music, video and calls when advertised. Use 96 kHz to match high-rate sources, not as an automatic quality upgrade. Nothing changes until you confirm a choice.")
                        Text("Source audio may be resampled if its rate differs from the device rate. These readouts do not prove bit-perfect playback, acoustic performance or the M60's internal DSP behavior.")
                        Text("This unofficial utility does not change speaker EQ, input mode or firmware. EDIFIER's official ConneX iOS app may be offered on Apple-silicon Macs; M60 control from Mac ConneX is not verified here.")
                    }
                    informationSection("Local diagnostics") {
                        Text("Unofficial · local only · no extra driver · no background service. Refresh is read-only every three seconds.")
                        Text("The white speaker artwork is an original M60 illustration, not a detected cabinet color.")
                        if let time = model.refreshedAt { Text("Last read \(time.formatted(date: .omitted, time: .standard))") }
                        Text("Diagnostics include device names, UIDs and USB serial/location identifiers. Review before sharing.")
                        Button { model.copyDiagnostics() } label: { Label("Copy diagnostics", systemImage: "doc.on.doc") }
                            .disabled(model.report == nil)
                    }
                }.font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
        }.frame(width: 520, height: 580).preferredColorScheme(.dark).tint(accent)
    }
    private func informationSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline).foregroundStyle(.primary)
            content().foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func deviceDetails(_ device: AudioDevice) -> some View {
        informationSection("Physical USB & CoreAudio") {
            Text(device.name)
            ForEach(device.streams) { stream in
                Text("Output stream \(stream.id)").fontWeight(.medium)
                Text("Physical USB: \(stream.physical.map { compactFormat($0) + " · \($0.channels) channels · \($0.encoding)" } ?? "Unavailable")")
                Text("CoreAudio virtual: \(stream.virtual.map { compactFormat($0) + " · \($0.channels) channels · \($0.encoding)" } ?? "Unavailable")")
                if !stream.physicalSettable { Text("The driver currently marks this stream as read-only.").foregroundStyle(.orange) }
                if stream.choices.isEmpty { Text("No supported stereo linear PCM choices were advertised. The app will not invent or force a format.").foregroundStyle(.orange) }
            }
            if model.stream == nil { Text("Format changes are disabled because the output stream is missing or ambiguous.").foregroundStyle(.orange) }
            Text("The physical format is what the driver reports for the USB stream. CoreAudio's float format belongs to the application/mixing path; it is not the speaker's hardware bit depth.")
            Text("Nominal rate: \(device.nominalRate.map { rateLabel($0) + " Hz" } ?? "unavailable")")
            Text("Advertised rates: \(device.availableNominalRates.map(\.label).joined(separator: ", "))")
        }
        informationSection("Routing & stereo check") {
            Text("Default output: \(model.report?.devices.first(where: \.isDefaultOutput)?.name ?? "Unavailable")")
            Text("System alerts: \(model.report?.devices.first(where: \.isDefaultSystemOutput)?.name ?? "Unavailable")")
            Text("Each Use M60 button changes only its named route, after confirmation. Apps can choose a different output. A checked M60 button means that route is already selected; it is not an on/off control.")
            Text("Audio engine: \(device.running.map { $0 ? "active" : "idle" } ?? "unavailable"). Device alive: \(device.alive ? "yes" : "no").")
            Text("The quiet stereo test plays left then right for two seconds, with no microphone, route changes or explicit physical-format writes. Turn down the speaker and pause playback before confirming.")
        }
        informationSection("Connection evidence & advertised formats") {
            Text(device.evidence ?? "No verified identity evidence")
            Text("UID: \(device.uid)").font(.system(.caption, design: .monospaced))
            if let fingerprint = device.fingerprint {
                Text("VID 2d99 · PID a094 · location \(String(format: "%08x", fingerprint.locationID))").font(.system(.caption, design: .monospaced))
            }
            ForEach(device.streams) { stream in
                Text("Output stream \(stream.id)").fontWeight(.medium)
                ForEach(Array(stream.availablePhysicalFormats.enumerated()), id: \.offset) { _, range in
                    Text("\(range.format.label) · flags 0x\(String(range.format.flags, radix: 16)) · \(range.format.bytesPerFrame) bytes/frame · rates \(rateLabel(range.minimumRate))–\(rateLabel(range.maximumRate)) Hz")
                        .font(.system(.caption, design: .monospaced))
                }
                ForEach(stream.errors, id: \.self) { Text($0).foregroundStyle(.orange) }
            }
            Text("The menu merges mixable/non-mixable duplicates and prefers mixable PCM. Raw advertised entries are preserved here and in JSON.")
            ForEach(device.errors, id: \.self) { Text($0).foregroundStyle(.orange) }
        }
    }
    private var disconnectedDetails: some View {
        informationSection(model.report == nil ? "Reading native audio devices…" : "No verified M60 USB output") {
            Text("Connect the speaker with a data-capable USB cable and select USB input on the M60. Bluetooth devices, lookalike names and unverified identities are intentionally excluded. Audio actions stay disabled.")
            if !(model.report?.usbFingerprints.isEmpty ?? true) {
                Text("An M60 USB fingerprint is present, but its CoreAudio identity could not be uniquely matched. Controls stay disabled; copy diagnostics for investigation.").foregroundStyle(.orange)
            }
            Text("Detection refreshes every three seconds while this app is open. No audio setting is changed automatically.")
        }
    }
}
