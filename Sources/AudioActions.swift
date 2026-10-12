import Foundation
import CoreAudio

// UI-only explicit actions. This file is not linked into the stand-alone read-only CLI.
// Re-resolve live USB identity before acting: stale numeric CoreAudio IDs alone are unsafe.
enum AudioActions {
    static func revalidate(_ original: AudioDevice) throws -> AudioDevice {
        guard let current = AudioHardware.diagnose().devices.first(where: { $0.id == original.id }),
              IdentityPolicy.allowsMutation(original: original, current: current) else {
            throw ActionError("M60 disconnected or identity changed. Refresh and select the verified USB device again. Nothing was changed.")
        }
        return current
    }
    static func write<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, value: T) throws {
        var a = AudioHardware.address(selector); var v = value
        guard AudioHardware.settable(object, selector) else { throw ActionError("The driver reports this property as read-only. Nothing was changed.") }
        let status = withUnsafePointer(to: &v) { AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0) }
        guard status == noErr else { throw HardwareError(operation: "Set \(fourCC(selector)) on \(object)", status: status) }
    }
    static func setDefault(_ original: AudioDevice, systemAlerts: Bool) throws -> String {
        let current = try revalidate(original)
        let selector = systemAlerts ? kAudioHardwarePropertyDefaultSystemOutputDevice : kAudioHardwarePropertyDefaultOutputDevice
        try write(AudioHardware.system, selector, value: current.id)
        let result = PropertyReadback.waitForMatch(read: {
            try? AudioHardware.scalar(AudioHardware.system, selector, initial: AudioObjectID(0))
        }, matches: { $0 == current.id })
        guard result != nil else {
            throw ActionError("Route write completed, but its readback did not settle on M60 within one second. It may have changed or another app may have changed it; inspect System Settings → Sound before retrying. No other route was written and no rollback was attempted.")
        }
        return systemAlerts ? "System alerts now use M60. The main output route was not changed." : "Default output now uses M60. The system-alert route was not changed. Apps with their own routing can override this."
    }
    static func applyFormat(_ original: AudioDevice, streamID: AudioStreamID, format: PCMFormat) throws -> String {
        let current = try revalidate(original)
        guard current.streams.count == 1, let stream = current.streams.first, stream.id == streamID,
              stream.physicalSettable, format.isSafeStereoPCM,
              stream.availablePhysicalFormats.contains(where: { $0.supports(format) }) else {
            throw ActionError("The selected stereo PCM format is no longer advertised or this device has multiple output streams. Nothing was changed.")
        }
        try write(stream.id, kAudioStreamPropertyPhysicalFormat, value: format.asbd)
        // HAL changes can be asynchronous: at most one second of readback, never retry the write.
        var latest: PCMFormat?
        for _ in 0..<10 {
            latest = try? PCMFormat(AudioHardware.scalar(stream.id, kAudioStreamPropertyPhysicalFormat, initial: AudioStreamBasicDescription()))
            if let latest = latest, latest.matches(format) { return "Verified physical format: \(latest.label). Other apps may later change it." }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw ActionError("Format write completed but readback \(latest?.label ?? "unavailable") did not match the requested format. The device may have partially changed; inspect the current hardware format before trying again. No rollback was attempted.")
    }
}

struct ActionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
