import Foundation

// Shared by the stand-alone CLI and app executable. This path only reads hardware.
enum DiagnosticCommand {
    static func run() -> Never {
        guard CommandLine.arguments.dropFirst().elementsEqual(["--diagnose"]) else {
            FileHandle.standardError.write(Data("Usage: edifier-usb-audio --diagnose\nRead-only JSON. Exits 0: live verified M60; 2: no live verified M60; 1: diagnostic/encoding failure; 64: usage.\n".utf8))
            exit(64)
        }
        let report = AudioHardware.diagnose()
        do {
            var data = try AudioHardware.encoded(report); data.append(0x0a)
            FileHandle.standardOutput.write(data)
            if !report.errors.isEmpty { exit(1) }
            if !report.m60Devices.contains(where: \.alive) {
                FileHandle.standardError.write(Data("No live verified EDIFIER M60 USB output. Use a data-capable cable and select USB on the speaker. Bluetooth and friendly-name-only matches are intentionally excluded.\n".utf8))
                exit(2)
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Diagnostics failed: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
