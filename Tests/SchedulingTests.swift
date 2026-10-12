import Foundation
import CoreAudio

private final class Recording {
    private let lock = NSLock()
    private var events: [String] = []
    private var identities: [USBFingerprint?] = []
    func append(_ event: String, identity: USBFingerprint? = nil) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
        if event == "action" { identities.append(identity) }
    }
    func snapshot() -> ([String], [USBFingerprint?]) {
        lock.lock(); defer { lock.unlock() }
        return (events, identities)
    }
}

// Construct background test callbacks outside MainActor so runtime actor checks
// exercise the model, rather than trapping on the test's injected closure.
private func refreshingReadStub(_ recording: Recording, _ release: DispatchSemaphore,
                                _ report: Diagnostics) -> () -> Diagnostics {
    return {
        let first = recording.snapshot().0.isEmpty
        recording.append("read")
        if first { _ = release.wait(timeout: .now() + 5) }
        return report
    }
}
private func successfulActionStub(_ recording: Recording) -> (PendingAction) throws -> String {
    return { action in
        guard case .format(let original, _, _) = action else { throw ActionError("Unexpected action") }
        recording.append("action", identity: original.fingerprint)
        return "Synthetic confirmed action completed"
    }
}
private func fixedReadStub(_ report: Diagnostics) -> () -> Diagnostics { return { report } }
private func failedActionStub(_ action: PendingAction) throws -> String { throw ActionError("Synthetic failure") }

@main
struct SchedulingTests {
    @MainActor static func main() async {
        var failures = 0
        var count = 0
        func check(_ name: String, _ condition: Bool) {
            count += 1
            if condition { print("PASS \(name)") }
            else { failures += 1; print("FAIL \(name)") }
        }
        let fp = USBFingerprint(registryID: 10, vendorID: 0x2d99, productID: 0xa094, product: "EDIFIER M60", manufacturer: "bestechnic", serial: "TEST-SERIAL", locationID: 10)
        let format = PCMFormat(rate: 48000)
        let stream = AudioStream(id: 20, physical: format, virtual: nil, availablePhysicalFormats: [], physicalSettable: true, errors: [])
        let device = AudioDevice(id: 30, name: "EDIFIER M60", uid: "AppleUSBAudioEngine:bestechnic:EDIFIER M60:TEST-SERIAL:1", transport: kAudioDeviceTransportTypeUSB, alive: true, nominalRate: 48000, availableNominalRates: [], running: false, isDefaultOutput: false, isDefaultSystemOutput: false, streams: [stream], fingerprint: fp, evidence: "Synthetic test identity", errors: [])
        let empty = Diagnostics(schemaVersion: 1, status: "no_verified_m60", readOnly: true, usbFingerprints: [], devices: [], errors: [], limitations: [])
        let recording = Recording()
        let releaseRead = DispatchSemaphore(value: 0)
        let model = AppModel(startAutomatically: false,
                             diagnose: refreshingReadStub(recording, releaseRead, empty),
                             execute: successfulActionStub(recording))
        model.refresh()
        check("refresh is in flight before confirmation", model.refreshing)
        model.perform(.format(device, stream.id, format))
        check("confirmed action accepted while refreshing", model.working)
        model.perform(.test(device))
        check("duplicate action is visibly rejected", model.noticeIsError && model.notice != nil)
        releaseRead.signal()
        for _ in 0..<100 {
            if !model.busy { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let recorded = recording.snapshot()
        check("confirmed action runs once after refresh", recorded.0 == ["read", "action", "read"])
        check("queued action keeps original identity snapshot", recorded.1 == [fp])
        check("confirmed action publishes completion", model.notice == "Synthetic confirmed action completed" && !model.noticeIsError)
        check("action and refresh release busy state", !model.busy)
        let failureModel = AppModel(startAutomatically: false, diagnose: fixedReadStub(empty), execute: failedActionStub)
        failureModel.perform(.test(device))
        for _ in 0..<100 {
            if !failureModel.busy { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        check("failed action is surfaced and releases busy", failureModel.notice == "Synthetic failure" && failureModel.noticeIsError && !failureModel.busy)
        print("\(count) scheduling tests, \(failures) failures. Injected reads/actions only; no hardware mutation or playback.")
        exit(failures == 0 ? 0 : 1)
    }
}
