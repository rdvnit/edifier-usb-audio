import Foundation
import SwiftUI
import AppKit
import CoreAudio

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var report: Diagnostics?
    @Published private(set) var refreshing = false
    @Published private(set) var working = false
    @Published var selectedDevice: UInt32?
    @Published var selectedFormat = ""
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published private(set) var refreshedAt: Date?
    private let queue = DispatchQueue(label: "m60.hardware", qos: .userInitiated)
    private let readHardware: () -> Diagnostics
    private let executeAction: (PendingAction) throws -> String
    private var timer: Timer?
    var device: AudioDevice? { report?.m60Devices.first { $0.id == selectedDevice } }
    var stream: AudioStream? { device?.streams.count == 1 ? device?.streams.first : nil }
    var chosenFormat: PCMFormat? { stream?.choices.first { $0.id == selectedFormat } }
    var busy: Bool { refreshing || working }
    init(startAutomatically: Bool = true,
         diagnose: @escaping () -> Diagnostics = AudioHardware.diagnose,
         execute: @escaping (PendingAction) throws -> String = { action in
             switch action {
             case .output(let device): return try AudioActions.setDefault(device, systemAlerts: false)
             case .alerts(let device): return try AudioActions.setDefault(device, systemAlerts: true)
             case .format(let device, let stream, let format): return try AudioActions.applyFormat(device, streamID: stream, format: format)
             case .test(let device): return try QuietTonePlayer.play(device)
             }
         }) {
        readHardware = diagnose
        executeAction = execute
        guard startAutomatically else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    deinit { timer?.invalidate() }
    func refresh() {
        guard !busy else { return }
        refreshing = true
        let read = readHardware
        queue.async { [weak self] in
            let next = read()
            DispatchQueue.main.async { self?.accept(next) }
        }
    }
    private func accept(_ next: Diagnostics) {
        let old = device
        let followedCurrentFormat = stream?.physical?.id == selectedFormat
        report = next; refreshing = false; refreshedAt = Date()
        if !next.m60Devices.contains(where: { $0.id == selectedDevice }) {
            selectedDevice = next.m60Devices.first(where: \.isDefaultOutput)?.id ?? next.m60Devices.first?.id
        }
        if old?.fingerprint != device?.fingerprint || old?.uid != device?.uid || followedCurrentFormat {
            selectedFormat = ""
        }
        reconcileFormat()
    }
    func reconcileFormat() {
        guard let stream = stream else { selectedFormat = ""; return }
        if stream.choices.contains(where: { $0.id == selectedFormat }) { return }
        // Start on the actual physical format, never silently select a higher rate/depth.
        if let physical = stream.physical,
           let same = stream.choices.first(where: { $0.matches(physical) }) {
            selectedFormat = same.id
        } else {
            selectedFormat = ""
        }
    }
    func perform(_ action: PendingAction) {
        guard !working else {
            notice = "Another confirmed action is already queued or running. Wait for it to finish before confirming a new change."
            noticeIsError = true
            return
        }
        // Preserve the confirmed snapshot and queue behind any in-flight read. The
        // action implementation revalidates it immediately before touching hardware.
        working = true; notice = nil
        let execute = executeAction
        let read = readHardware
        queue.async { [weak self] in
            let outcome: Result<String, Error> = Result {
                try execute(action)
            }
            let next = read()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.working = false
                switch outcome {
                case .success(let message): self.notice = message; self.noticeIsError = false
                case .failure(let error): self.notice = error.localizedDescription; self.noticeIsError = true
                }
                self.accept(next)
            }
        }
    }
    func copyDiagnostics() {
        guard let report = report, let data = try? AudioHardware.encoded(report), let text = String(data: data, encoding: .utf8) else {
            notice = "Diagnostics are not available yet."; noticeIsError = true; return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "Copied locally. Diagnostics include device names, UIDs and M60 USB serial/location identifiers; review before sharing."; noticeIsError = false
    }
}

enum PendingAction: Identifiable {
    case output(AudioDevice)
    case alerts(AudioDevice)
    case format(AudioDevice, UInt32, PCMFormat)
    case test(AudioDevice)
    var id: String {
        switch self {
        case .output(let d): return "output-\(d.id)"
        case .alerts(let d): return "alerts-\(d.id)"
        case .format(let d, let stream, let f): return "format-\(d.id)-\(stream)-\(f.id)"
        case .test(let d): return "test-\(d.id)"
        }
    }
    var title: String {
        switch self {
        case .output: return "Change default output?"
        case .alerts: return "Change system-alert output?"
        case .format: return "Change the physical USB format?"
        case .test: return "Play a quiet stereo check?"
        }
    }
    var confirmLabel: String {
        if case .test = self { return "Play quiet test" }
        return "Confirm change"
    }
    var message: String {
        switch self {
        case .output(let d): return "This sets \(d.name) as the system default for audio output. Apps with their own routing may not follow it. System alerts are unchanged."
        case .alerts(let d): return "This sends system alerts to \(d.name). The default audio output is unchanged. Speaker volume is independent of Mac volume."
        case .format(_, _, let f): return "Requested: \(f.label).\n\nThis changes a system-wide device property, not just this app. Pause playback first; other apps may be interrupted or may later change the format. Higher sample rates do not automatically improve audio quality. The app reads the hardware format back after applying it."
        case .test: return "Turn the M60's own volume down first and pause other playback. USB speaker volume is independent of Mac volume.\n\nA quiet 440 Hz tone (maximum digital amplitude 0.02, with fades) plays left then right for two seconds on this exact verified USB device. It does not use the microphone, change the default route or explicitly write the physical format. Even a quiet signal may sound louder at a high speaker volume."
        }
    }
}
