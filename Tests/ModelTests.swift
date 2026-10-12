import Foundation
import CoreAudio

@main
struct ModelTests {
    static var count = 0
    static var failures = 0
    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        count += 1
        if condition() { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
    }
    static func main() {
        let usb = USBFingerprint(registryID: 10, vendorID: 0x2d99, productID: 0xa094,
                                 product: "EDIFIER M60", manufacturer: "bestechnic", serial: "TEST-SERIAL", locationID: 10)
        let uid = "AppleUSBAudioEngine:bestechnic:EDIFIER M60:TEST-SERIAL:1"
        check("exact USB identity matches", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeUSB, fingerprints: [usb])?.0 == usb)
        check("Bluetooth rejected even with matching UID", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeBluetooth, fingerprints: [usb]) == nil)
        check("Bluetooth LE rejected", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeBluetoothLE, fingerprints: [usb]) == nil)
        check("friendly name is not identity", IdentityPolicy.correlate(uid: "EDIFIER M60", transport: kAudioDeviceTransportTypeUSB, fingerprints: [usb]) == nil)
        check("unrelated USB UID rejected", IdentityPolicy.correlate(uid: "AppleUSBAudioEngine:other:EDIFIER M60:TEST-SERIAL:1", transport: kAudioDeviceTransportTypeUSB, fingerprints: [usb]) == nil)
        check("USB registry required", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeUSB, fingerprints: []) == nil)
        check("duplicate registry identity fails closed", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeUSB, fingerprints: [usb, usb]) == nil)
        let wrongPID = USBFingerprint(registryID: 11, vendorID: usb.vendorID, productID: 0xa095, product: usb.product, manufacturer: usb.manufacturer, serial: usb.serial, locationID: 11)
        let wrongProduct = USBFingerprint(registryID: 12, vendorID: usb.vendorID, productID: usb.productID, product: "EDIFIER M60 Bluetooth", manufacturer: usb.manufacturer, serial: usb.serial, locationID: 12)
        check("wrong product ID rejected", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeUSB, fingerprints: [wrongPID]) == nil)
        check("product must match exactly", IdentityPolicy.correlate(uid: uid, transport: kAudioDeviceTransportTypeUSB, fingerprints: [wrongProduct]) == nil)
        check("different serial rejected", IdentityPolicy.correlate(uid: uid.replacingOccurrences(of: "TEST-SERIAL", with: "OTHER"), transport: kAudioDeviceTransportTypeUSB, fingerprints: [usb]) == nil)
        let unexpectedManufacturer = USBFingerprint(registryID: 13, vendorID: usb.vendorID, productID: usb.productID, product: usb.product, manufacturer: "UNEXPECTED-MANUFACTURER", serial: usb.serial, locationID: 13)
        check("consistent unexpected manufacturer rejected", IdentityPolicy.correlate(uid: uid.replacingOccurrences(of: "bestechnic", with: unexpectedManufacturer.manufacturer), transport: kAudioDeviceTransportTypeUSB, fingerprints: [unexpectedManufacturer]) == nil)
        check("unexpected manufacturer is not known M60", !unexpectedManufacturer.isM60)

        let f16 = PCMFormat(rate: 48000, bits: 16, bytes: 4)
        let f24 = PCMFormat(rate: 48000)
        check("valid packed stereo16 accepted", f16.isSafeStereoPCM)
        check("valid packed stereo24 accepted", f24.isSafeStereoPCM)
        check("unsupported encoding rejected", !PCMFormat(rate: 48000, formatID: kAudioFormatMPEG4AAC).isSafeStereoPCM)
        check("mono rejected", !PCMFormat(rate: 48000, channels: 1).isSafeStereoPCM)
        check("multichannel rejected", !PCMFormat(rate: 48000, channels: 6).isSafeStereoPCM)
        check("unsupported depth rejected", !PCMFormat(rate: 48000, bits: 20).isSafeStereoPCM)
        check("short container rejected", !PCMFormat(rate: 48000, bytes: 4).isSafeStereoPCM)
        check("huge container rejected without overflow", !PCMFormat(rate: 48000, bytes: UInt32.max).isSafeStereoPCM)
        check("zero rate rejected", !PCMFormat(rate: 0).isSafeStereoPCM)
        check("NaN rate rejected", !PCMFormat(rate: .nan).isSafeStereoPCM)
        check("infinite rate rejected", !PCMFormat(rate: .infinity).isSafeStereoPCM)
        check("PCM flags must have one numeric encoding", !PCMFormat(rate: 48000, flags: kAudioFormatFlagIsPacked).isSafeStereoPCM)
        check("float24 rejected", !PCMFormat(rate: 48000, flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked).isSafeStereoPCM)
        let range = FormatRange(format: f24, minimumRate: 48000, maximumRate: 96000)
        check("advertised interior rate supported", range.supports(f24.withRate(88200)))
        check("outside rate rejected", !range.supports(f24.withRate(44100)))
        check("different bit depth rejected", !range.supports(f16))
        check("common choices stay in advertised range", range.choices.map(\.sampleRate) == [48000, 88200, 96000])
        check("discrete format never invents44100", FormatRange(format: f24, minimumRate: 48000, maximumRate: 48000).choices.map(\.sampleRate) == [48000])
        check("reversed range produces no choices", FormatRange(format: f24, minimumRate: 96000, maximumRate: 48000).choices.isEmpty)
        check("malformed NaN range produces no choices", FormatRange(format: f24, minimumRate: .nan, maximumRate: .nan).choices.isEmpty)
        check("format IDs are stable", PCMFormat(f24.asbd).id == f24.id)
        check("format IDs distinguish rate", f24.withRate(96000).id != f24.id)
        var nonmix = f24.asbd; nonmix.mFormatFlags |= kAudioFormatFlagIsNonMixable
        let nm = PCMFormat(nonmix)
        check("format IDs distinguish flags", nm.id != f24.id)
        check("rate readback tolerates sub-centihertz rounding", f24.matches(f24.withRate(48000.005)))
        check("rate readback rejects other rate", !f24.matches(f24.withRate(96000)))
        check("readback verifies flags as well as rate", !f24.matches(nm))
        let stream = AudioStream(id: 20, physical: f16, virtual: PCMFormat(rate: 48000, bits: 32, flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, bytes: 8),
                                 availablePhysicalFormats: [FormatRange(format: nm, minimumRate: 48000, maximumRate: 48000), FormatRange(format: f24, minimumRate: 48000, maximumRate: 48000), FormatRange(format: f16, minimumRate: 48000, maximumRate: 48000)], physicalSettable: true, errors: [])
        check("picker deduplicates nonmixable variants", stream.choices.count == 2)
        check("picker prefers mixable even when nonmixable is first", stream.choices.first(where: { $0.bits == 24 })?.id == f24.id)
        check("hardware16 is separate from virtual float32", stream.physical?.bits == 16 && stream.virtual?.bits == 32)
        func device(id: UInt32 = 30, uid: String = uid, alive: Bool = true, fingerprint: USBFingerprint? = usb, transport: UInt32 = kAudioDeviceTransportTypeUSB) -> AudioDevice {
            AudioDevice(id: id, name: "EDIFIER M60", uid: uid, transport: transport, alive: alive, nominalRate: 48000,
                        availableNominalRates: [RateRange(minimum: 48000, maximum: 48000)], running: false, isDefaultOutput: false, isDefaultSystemOutput: false,
                        streams: [stream], fingerprint: fingerprint, evidence: fingerprint == nil ? nil : "Test evidence", errors: [])
        }
        let original = device()
        check("mutation permits unchanged verified live device", IdentityPolicy.allowsMutation(original: original, current: original))
        check("mutation denies dead device", !IdentityPolicy.allowsMutation(original: original, current: device(alive: false)))
        check("mutation denies stale numeric deviceID", !IdentityPolicy.allowsMutation(original: original, current: device(id: 31)))
        check("mutation denies changed UID", !IdentityPolicy.allowsMutation(original: original, current: device(uid: "other")))
        check("mutation denies missing USB proof", !IdentityPolicy.allowsMutation(original: original, current: device(fingerprint: nil)))
        check("mutation denies Bluetooth", !IdentityPolicy.allowsMutation(original: original, current: device(transport: kAudioDeviceTransportTypeBluetooth)))
        check("mutation denies changed registry object", !IdentityPolicy.allowsMutation(original: original, current: device(fingerprint: USBFingerprint(registryID: 99, vendorID: usb.vendorID, productID: usb.productID, product: usb.product, manufacturer: usb.manufacturer, serial: usb.serial, locationID: usb.locationID))))
        check("tone starts and ends silent", QuietTone.sample(time: 0, channel: 0) == 0 && QuietTone.sample(time: 2, channel: 1) == 0)
        check("tone has left-right separation", QuietTone.sample(time: 0.205, channel: 0) != 0 && QuietTone.sample(time: 0.205, channel: 1) == 0 && QuietTone.sample(time: 1.205, channel: 0) == 0 && QuietTone.sample(time: 1.205, channel: 1) != 0)
        check("tone silence between channels", QuietTone.sample(time: 0.95, channel: 0) == 0 && QuietTone.sample(time: 0.95, channel: 1) == 0)
        check("tone fades near segment endpoints", abs(QuietTone.sample(time: 0.1005, channel: 0)) < 0.001 && abs(QuietTone.sample(time: 0.7995, channel: 0)) < 0.001)
        check("tone rejects invalid time or channel", QuietTone.sample(time: .nan, channel: 0) == 0 && QuietTone.sample(time: .infinity, channel: 0) == 0 && QuietTone.sample(time: 0.205, channel: 4) == 0)
        var maximum: Float = 0
        for frame in 0..<192000 {
            let t = Double(frame) / 96000
            maximum = max(maximum, abs(QuietTone.sample(time: t, channel: 0)), abs(QuietTone.sample(time: t, channel: 1)))
        }
        check("all generated samples bounded at0.02", maximum <= Float(QuietTone.amplitude) && maximum > 0.019)
        var reads = 0
        var pauses = 0
        let delayed: Int? = PropertyReadback.waitForMatch(attempts: 5, pause: { pauses += 1 }, read: { reads += 1; return reads < 3 ? 1 : 2 }, matches: { $0 == 2 })
        check("readback accepts asynchronous route after delay", delayed == 2 && reads == 3 && pauses == 2)
        reads = 0; pauses = 0
        let timeout: Int? = PropertyReadback.waitForMatch(attempts: 3, pause: { pauses += 1 }, read: { reads += 1; return 1 }, matches: { $0 == 2 })
        check("readback timeout is bounded", timeout == nil && reads == 3 && pauses == 2)
        reads = 0
        let transient: Int? = PropertyReadback.waitForMatch(attempts: 3, pause: {}, read: { reads += 1; return reads < 2 ? nil : 2 }, matches: { $0 == 2 })
        check("readback tolerates transient unreadable property", transient == 2 && reads == 2)
        reads = 0
        let none: Int? = PropertyReadback.waitForMatch(attempts: 0, pause: {}, read: { reads += 1; return 2 }, matches: { $0 == 2 })
        check("zero attempts never reads", none == nil && reads == 0)
        print("\(count) tests, \(failures) failures. Pure models/waveform/readback only: no CoreAudio writes or playback.")
        exit(failures == 0 ? 0 : 1)
    }
}
