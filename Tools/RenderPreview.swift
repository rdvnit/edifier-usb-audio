import SwiftUI
import AppKit

// Factories are nonisolated: injected work runs on the model's background queue.
private func previewDiagnostic(_ report: Diagnostics) -> () -> Diagnostics { return { report } }
private func forbidPreviewAction(_ action: PendingAction) throws -> String { throw ActionError("Preview fixture forbids all audio actions") }

// Read-only offscreen UI smoke test. Never calls perform(), changes routes or plays sound.
// The first image uses live hardware. The second is a clearly synthetic no-device
// fixture, injected through AppModel's existing test seam, not a USB disconnection.
@main
struct RenderPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard CommandLine.arguments.count == 3 else {
            throw ActionError("Usage: render-preview connected.png disconnected.png")
        }
        let live = AppModel()
        try waitForReport(live)
        guard live.device?.alive == true else { throw ActionError("Connected preview requires a live verified M60; no fixture substitutes for it") }
        try render(live, path: CommandLine.arguments[1])
        print("Connected preview: live \(live.report?.status ?? "unknown"), physical \(live.stream?.physical?.label ?? "unavailable")")

        let fixture = Diagnostics(schemaVersion: 1, status: "synthetic disconnected preview", readOnly: true,
                                  usbFingerprints: [], devices: [], errors: [], limitations: ["Synthetic no-device UI fixture only"])
        let disconnected = AppModel(startAutomatically: false, diagnose: previewDiagnostic(fixture),
                                    execute: forbidPreviewAction)
        disconnected.refresh()
        try waitForReport(disconnected)
        try render(disconnected, path: CommandLine.arguments[2])
        print("Disconnected preview: SYNTHETIC no-device fixture; hardware remains untouched.")
        print("Both native SwiftUI images: 380 × 620 points; PNG pixel sizes reported above. No audio writes or playback.")
    }

    @MainActor private static func waitForReport(_ model: AppModel) throws {
        let deadline = Date().addingTimeInterval(5)
        while model.report == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard model.report != nil else { throw ActionError("Timed out reading preview diagnostics") }
    }

    @MainActor private static func render(_ model: AppModel, path: String) throws {
        let content = ContentView().environmentObject(model)
        let host = NSHostingView(rootView: content)
        let rect = NSRect(x: 0, y: 0, width: 380, height: 620)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = rect
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ActionError("No preview bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ActionError("No preview PNG") }
        try png.write(to: URL(fileURLWithPath: path))
        print("Saved \(path): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) pixels; host \(Int(host.bounds.width)) × \(Int(host.bounds.height)) points")
        window.contentView = nil
    }
}
