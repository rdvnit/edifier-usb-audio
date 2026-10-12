import Foundation
import CoreAudio
import IOKit

struct HardwareError: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "\(operation): OSStatus \(status) (\(fourCC(UInt32(bitPattern: status))))" }
}

enum AudioHardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var a = address(selector, scope); var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let expected = size
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        guard status == noErr, size == expected else { throw HardwareError(operation: "Read \(fourCC(selector)) on \(object)", status: status == noErr ? kAudioHardwareBadPropertySizeError : status) }
        return value
    }
    static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [T] {
        var a = address(selector, scope); var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size)
        guard status == noErr else { throw HardwareError(operation: "Size \(fourCC(selector)) on \(object)", status: status) }
        guard Int(size) % MemoryLayout<T>.stride == 0, size <= 4_194_304 else { throw HardwareError(operation: "Invalid property size", status: kAudioHardwareBadPropertySizeError) }
        if size == 0 { return [] }
        var result = Array(repeating: initial, count: Int(size) / MemoryLayout<T>.stride)
        let capacity = size
        status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr, size <= capacity, Int(size) % MemoryLayout<T>.stride == 0 else { throw HardwareError(operation: "Read \(fourCC(selector)) on \(object)", status: status == noErr ? kAudioHardwareBadPropertySizeError : status) }
        return Array(result.prefix(Int(size) / MemoryLayout<T>.stride))
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var a = address(selector); var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value)
        guard status == noErr, let value = value else { throw HardwareError(operation: "Read \(fourCC(selector)) on \(object)", status: status) }
        return value.takeRetainedValue() as String
    }
    static func settable(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var a = address(selector); var value: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &a, &value) == noErr && value.boolValue
    }
    static func usbFingerprints() throws -> [USBFingerprint] {
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator)
        guard status == KERN_SUCCESS else { throw HardwareError(operation: "Enumerate USB registry", status: status) }
        defer { IOObjectRelease(iterator) }
        var found: [USBFingerprint] = []
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = properties?.takeRetainedValue() as NSDictionary? else { continue }
            let vid = (properties["idVendor"] as? NSNumber)?.uint32Value ?? 0
            let pid = (properties["idProduct"] as? NSNumber)?.uint32Value ?? 0
            // Include only this known M60 fingerprint; no unrelated USB serials in diagnostics.
            guard vid == 0x2d99, pid == 0xa094 else { continue }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &registryID) == KERN_SUCCESS else { continue }
            found.append(USBFingerprint(registryID: registryID, vendorID: vid, productID: pid,
                                        product: properties["USB Product Name"] as? String ?? "",
                                        manufacturer: properties["USB Vendor Name"] as? String ?? "",
                                        serial: properties["USB Serial Number"] as? String ?? "",
                                        locationID: (properties["locationID"] as? NSNumber)?.uint32Value ?? 0))
        }
        return found.sorted { $0.registryID < $1.registryID }
    }
    static func stream(_ id: AudioStreamID) -> AudioStream {
        var errors: [String] = []
        func attempt<T>(_ block: () throws -> T) -> T? {
            do { return try block() } catch { errors.append(error.localizedDescription); return nil }
        }
        let physical = attempt { PCMFormat(try scalar(id, kAudioStreamPropertyPhysicalFormat, initial: AudioStreamBasicDescription())) }
        let virtual = attempt { PCMFormat(try scalar(id, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())) }
        let raw: [AudioStreamRangedDescription] = attempt { try array(id, kAudioStreamPropertyAvailablePhysicalFormats, initial: AudioStreamRangedDescription()) } ?? []
        let ranges: [FormatRange] = raw.map { entry in
            FormatRange(format: PCMFormat(entry.mFormat), minimumRate: entry.mSampleRateRange.mMinimum,
                        maximumRate: entry.mSampleRateRange.mMaximum)
        }
        let available = ranges.sorted { left, right in
            if left.format.id == right.format.id { return left.minimumRate < right.minimumRate }
            return left.format.id < right.format.id
        }
        return AudioStream(id: id, physical: physical, virtual: virtual, availablePhysicalFormats: available,
                           physicalSettable: settable(id, kAudioStreamPropertyPhysicalFormat), errors: errors)
    }
    static func diagnose() -> Diagnostics {
        var errors: [String] = []
        func attempt<T>(_ block: () throws -> T) -> T? {
            do { return try block() } catch { errors.append(error.localizedDescription); return nil }
        }
        let usb = attempt { try usbFingerprints() } ?? []
        let ids = attempt { try array(system, kAudioHardwarePropertyDevices, initial: AudioObjectID(0)) } ?? []
        let output = attempt { try scalar(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0)) }
        let systemOutput = attempt { try scalar(system, kAudioHardwarePropertyDefaultSystemOutputDevice, initial: AudioObjectID(0)) }
        let devices: [AudioDevice] = ids.sorted().compactMap { id in
            var failures: [String] = []
            func read<T>(_ block: () throws -> T) -> T? {
                do { return try block() } catch { failures.append(error.localizedDescription); return nil }
            }
            let streamIDs = read { try array(id, kAudioDevicePropertyStreams, initial: AudioStreamID(0), scope: kAudioDevicePropertyScopeOutput) } ?? []
            guard !streamIDs.isEmpty else { return nil }
            let name = read { try string(id, kAudioObjectPropertyName) } ?? "Unknown device"
            let uid = read { try string(id, kAudioDevicePropertyDeviceUID) } ?? ""
            let transport = read { try scalar(id, kAudioDevicePropertyTransportType, initial: UInt32(0)) } ?? 0
            let alive = read { try scalar(id, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) } == 1
            let rate = read { try scalar(id, kAudioDevicePropertyNominalSampleRate, initial: Double(0)) }
            let rateRanges: [AudioValueRange] = read { try array(id, kAudioDevicePropertyAvailableNominalSampleRates, initial: AudioValueRange()) } ?? []
            let nominalUnsorted: [RateRange] = rateRanges.map { entry in RateRange(minimum: entry.mMinimum, maximum: entry.mMaximum) }
            let nominalRates: [RateRange] = nominalUnsorted.sorted { left, right in
                if left.minimum == right.minimum { return left.maximum < right.maximum }
                return left.minimum < right.minimum
            }
            let runningValue: UInt32? = read { try scalar(id, kAudioDevicePropertyDeviceIsRunningSomewhere, initial: UInt32(0)) }
            let running: Bool? = runningValue.map { $0 == 1 }
            let match = IdentityPolicy.correlate(uid: uid, transport: transport, fingerprints: usb)
            return AudioDevice(id: id, name: name, uid: uid, transport: transport, alive: alive,
                               nominalRate: rate, availableNominalRates: nominalRates, running: running,
                               isDefaultOutput: id == output, isDefaultSystemOutput: id == systemOutput,
                               streams: streamIDs.sorted().map(stream), fingerprint: match?.0, evidence: match?.1, errors: failures)
        }
        let matched = devices.filter(\.verifiedM60)
        let status = matched.isEmpty ? (errors.isEmpty ? "no_verified_m60" : "diagnostic_error") : (matched.contains(where: \.alive) ? "connected" : "not_alive")
        return Diagnostics(schemaVersion: 1, status: status, readOnly: true, usbFingerprints: usb, devices: devices, errors: errors,
                           limitations: ["Physical formats are driver-reported, not proof of bit-perfect playback, acoustic quality or internal speaker DSP.",
                                         "Virtual float PCM describes CoreAudio's application/mixing path, not USB hardware bit depth.",
                                         "No vendor EQ, firmware, Bluetooth control or USB/speaker volume synchronization is implemented."])
    }
    static func encoded(_ diagnostics: Diagnostics) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(diagnostics)
    }
}
