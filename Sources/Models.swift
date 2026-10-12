import Foundation
import CoreAudio

struct USBFingerprint: Codable, Equatable, Identifiable {
    let registryID: UInt64
    let vendorID: UInt32
    let productID: UInt32
    let product: String
    let manufacturer: String
    let serial: String
    let locationID: UInt32
    var id: UInt64 { registryID }
    var isM60: Bool { vendorID == 0x2d99 && productID == 0xa094 && product == "EDIFIER M60" && manufacturer == "bestechnic" }
}

struct PCMFormat: Codable, Equatable, Identifiable {
    let sampleRate: Double
    let formatID: UInt32
    let flags: UInt32
    let bytesPerPacket: UInt32
    let framesPerPacket: UInt32
    let bytesPerFrame: UInt32
    let channels: UInt32
    let bits: UInt32
    init(_ asbd: AudioStreamBasicDescription) {
        sampleRate = asbd.mSampleRate; formatID = asbd.mFormatID; flags = asbd.mFormatFlags
        bytesPerPacket = asbd.mBytesPerPacket; framesPerPacket = asbd.mFramesPerPacket
        bytesPerFrame = asbd.mBytesPerFrame; channels = asbd.mChannelsPerFrame; bits = asbd.mBitsPerChannel
    }
    init(rate: Double, bits: UInt32 = 24, channels: UInt32 = 2,
         formatID: UInt32 = kAudioFormatLinearPCM, flags: UInt32 = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
         bytes: UInt32 = 6) {
        sampleRate = rate; self.bits = bits; self.channels = channels; self.formatID = formatID
        self.flags = flags; bytesPerFrame = bytes; bytesPerPacket = bytes; framesPerPacket = 1
    }
    var id: String {
        // Include the complete ASBD: do not collapse packed/aligned or float/integer variants.
        "\(sampleRate)|\(formatID)|\(flags)|\(bytesPerPacket)|\(framesPerPacket)|\(bytesPerFrame)|\(channels)|\(bits)"
    }
    var isSafeStereoPCM: Bool {
        guard sampleRate.isFinite, sampleRate > 0, formatID == kAudioFormatLinearPCM,
              channels == 2, [16, 24, 32].contains(bits), framesPerPacket == 1,
              bytesPerFrame > 0, bytesPerFrame <= 64, bytesPerPacket == bytesPerFrame else { return false }
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        guard isFloat != isInteger, !isFloat || bits == 32 else { return false }
        let samplesPerFrame: UInt32 = flags & kAudioFormatFlagIsNonInterleaved != 0 ? 1 : channels
        return bytesPerFrame * 8 >= bits * samplesPerFrame
    }
    var encoding: String {
        formatID == kAudioFormatLinearPCM ? (flags & kAudioFormatFlagIsFloat != 0 ? "float PCM" : "integer PCM") : fourCC(formatID)
    }
    var label: String { "\(rateLabel(sampleRate)) Hz · \(bits)-bit · \(channels) ch · \(encoding)" }
    func withRate(_ rate: Double) -> PCMFormat {
        var a = asbd; a.mSampleRate = rate; return PCMFormat(a)
    }
    var asbd: AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: formatID, mFormatFlags: flags,
                                    mBytesPerPacket: bytesPerPacket, mFramesPerPacket: framesPerPacket,
                                    mBytesPerFrame: bytesPerFrame, mChannelsPerFrame: channels,
                                    mBitsPerChannel: bits, mReserved: 0)
    }
    func matches(_ other: PCMFormat) -> Bool {
        abs(sampleRate - other.sampleRate) < 0.01 && withRate(other.sampleRate).id == other.id
    }
}

struct FormatRange: Codable, Equatable {
    let format: PCMFormat
    let minimumRate: Double
    let maximumRate: Double
    func supports(_ candidate: PCMFormat) -> Bool {
        candidate.isSafeStereoPCM && minimumRate.isFinite && maximumRate.isFinite &&
        candidate.sampleRate >= minimumRate && candidate.sampleRate <= maximumRate &&
        format.withRate(candidate.sampleRate).id == candidate.id
    }
    var choices: [PCMFormat] {
        // Discrete endpoints plus common rates strictly within the driver-advertised range.
        let common: [Double] = [8000, 16000, 32000, 44100, 48000, 88200, 96000, 176400, 192000]
        return Array(Set(common + [minimumRate, maximumRate]))
            .filter { $0.isFinite && $0 >= minimumRate && $0 <= maximumRate }
            .sorted().map { format.withRate($0) }.filter(\.isSafeStereoPCM)
    }
}

struct AudioStream: Codable, Identifiable {
    let id: UInt32
    let physical: PCMFormat?
    let virtual: PCMFormat?
    let availablePhysicalFormats: [FormatRange]
    let physicalSettable: Bool
    let errors: [String]
    var choices: [PCMFormat] {
        var best: [String: PCMFormat] = [:]
        for choice in availablePhysicalFormats.flatMap(\.choices) {
            var mixable = choice.asbd
            mixable.mFormatFlags &= ~kAudioFormatFlagIsNonMixable
            let key = PCMFormat(mixable).id
            if let previous = best[key], previous.flags & kAudioFormatFlagIsNonMixable == 0 { continue }
            best[key] = choice
        }
        return best.values.sorted { $0.sampleRate == $1.sampleRate ? $0.id < $1.id : $0.sampleRate < $1.sampleRate }
    }
}

struct RateRange: Codable, Equatable {
    let minimum: Double
    let maximum: Double
    var label: String { minimum == maximum ? "\(rateLabel(minimum)) Hz" : "\(rateLabel(minimum))–\(rateLabel(maximum)) Hz" }
}

struct AudioDevice: Codable, Identifiable {
    let id: UInt32
    let name: String
    let uid: String
    let transport: UInt32
    let alive: Bool
    let nominalRate: Double?
    let availableNominalRates: [RateRange]
    let running: Bool?
    let isDefaultOutput: Bool
    let isDefaultSystemOutput: Bool
    let streams: [AudioStream]
    let fingerprint: USBFingerprint?
    let evidence: String?
    let errors: [String]
    var verifiedM60: Bool { fingerprint?.isM60 == true && evidence != nil && transport == kAudioDeviceTransportTypeUSB }
    var canMutate: Bool { verifiedM60 && alive && !streams.isEmpty }
    var transportLabel: String { transport == kAudioDeviceTransportTypeUSB ? "USB" : fourCC(transport) }
}

struct Diagnostics: Codable {
    let schemaVersion: Int
    let status: String
    let readOnly: Bool
    let usbFingerprints: [USBFingerprint]
    let devices: [AudioDevice]
    let errors: [String]
    let limitations: [String]
    var m60Devices: [AudioDevice] { devices.filter(\.verifiedM60) }
}

enum IdentityPolicy {
    static func correlate(uid: String, transport: UInt32, fingerprints: [USBFingerprint]) -> (USBFingerprint, String)? {
        guard transport == kAudioDeviceTransportTypeUSB else { return nil }
        // Apple USB UIDs encode manufacturer, product, serial and interface/engine identity.
        // Matching a friendly name or the presence of some other M60 on USB is not enough.
        let parts = uid.components(separatedBy: ":")
        guard parts.count >= 5, parts[0] == "AppleUSBAudioEngine" else { return nil }
        let candidates = fingerprints.filter {
            $0.isM60 && !$0.serial.isEmpty && parts[1] == $0.manufacturer && parts[2] == $0.product && parts[3] == $0.serial
        }
        guard candidates.count == 1 else { return nil }
        return (candidates[0], "USB VID 0x2d99 / PID 0xa094 and exact product; Apple USB CoreAudio UID manufacturer/product/serial matches one live IORegistry device")
    }
    static func allowsMutation(original: AudioDevice, current: AudioDevice) -> Bool {
        original.canMutate && current.canMutate && original.id == current.id && original.uid == current.uid &&
        original.fingerprint == current.fingerprint
    }
}

// Bounded readback only: callers issue a setter once, never from this helper.
enum PropertyReadback {
    static func waitForMatch<T>(attempts: Int = 10,
                                pause: () -> Void = { Thread.sleep(forTimeInterval: 0.1) },
                                read: () -> T?, matches: (T) -> Bool) -> T? {
        guard attempts > 0 else { return nil }
        for attempt in 0..<attempts {
            if let value = read(), matches(value) { return value }
            if attempt + 1 < attempts { pause() }
        }
        return nil
    }
}

func fourCC(_ value: UInt32) -> String {
    String(bytes: [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)], encoding: .ascii) ?? String(value)
}
func rateLabel(_ rate: Double) -> String { rate.isFinite ? String(format: rate.rounded() == rate ? "%.0f" : "%.2f", rate) : "unknown" }
