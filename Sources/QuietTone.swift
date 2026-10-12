import Foundation
import AudioToolbox
import CoreAudio

private final class ToneState {
    let rate: Double
    var frame: UInt64 = 0
    init(rate: Double) { self.rate = rate }
}

private let quietRender: AURenderCallback = { refCon, _, _, _, frameCount, data in
    guard let data = data else { return kAudio_ParamError }
    let state = Unmanaged<ToneState>.fromOpaque(refCon).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(data)
    // The client format below is interleaved Float32 stereo. Fail silent for any mismatch.
    guard buffers.count == 1, buffers[0].mNumberChannels == 2,
          buffers[0].mDataByteSize >= frameCount * 8, let raw = buffers[0].mData else {
        for buffer in buffers {
            if let raw = buffer.mData { memset(raw, 0, Int(buffer.mDataByteSize)) }
        }
        return noErr
    }
    let samples = raw.assumingMemoryBound(to: Float.self)
    for i in 0..<Int(frameCount) {
        let time = Double(state.frame + UInt64(i)) / state.rate
        samples[i * 2] = QuietTone.sample(time: time, channel: 0)
        samples[i * 2 + 1] = QuietTone.sample(time: time, channel: 1)
    }
    state.frame += UInt64(frameCount)
    return noErr
}

enum QuietTonePlayer {
    // Synchronous on the model's background queue, finite and bound to the verified USB device.
    // Never call from diagnostics or tests. No microphone/input is enabled.
    static func play(_ original: AudioDevice) throws -> String {
        let current = try AudioActions.revalidate(original)
        guard current.streams.count == 1, let physical = current.streams[0].physical,
              physical.isSafeStereoPCM, let rate = current.nominalRate, rate.isFinite, rate > 0 else {
            throw ActionError("The verified device does not have a readable stereo PCM output. No test was played.")
        }
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                     componentSubType: kAudioUnitSubType_HALOutput,
                                                     componentManufacturer: kAudioUnitManufacturer_Apple,
                                                     componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw ActionError("Apple HAL output unit is unavailable.") }
        var unit: AudioUnit?
        try checked(AudioComponentInstanceNew(component, &unit), "Create HAL output unit")
        guard let unit = unit else { throw ActionError("HAL output unit creation returned no instance.") }
        let state = ToneState(rate: rate)
        // Hold callback state independently until disposal succeeds. If disposal fails, leak the
        // tiny state rather than free memory potentially still referenced by a render callback.
        let retainedState = Unmanaged.passRetained(state)
        var initialized = false
        var started = false
        var disposed = false
        defer {
            if !disposed {
                if started { _ = AudioOutputUnitStop(unit) }
                if initialized { _ = AudioUnitUninitialize(unit) }
                if AudioComponentInstanceDispose(unit) == noErr { retainedState.release() }
            }
        }
        var enabled: UInt32 = 1
        try property(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enabled)
        enabled = 0
        try property(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled)
        var deviceID = current.id
        try property(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID)
        var bound: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try checked(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &bound, &size), "Read output unit device")
        guard bound == current.id else { throw ActionError("Output unit did not bind to the exact M60. No test was played.") }
        var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                                 mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        try property(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format)
        var callback = AURenderCallbackStruct(inputProc: quietRender, inputProcRefCon: retainedState.toOpaque())
        try property(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback)
        try checked(AudioUnitInitialize(unit), "Initialize output unit"); initialized = true
        // A second identity guard immediately before starting. Never fall back to default output.
        _ = try AudioActions.revalidate(current)
        try checked(AudioOutputUnitStart(unit), "Start quiet M60 test"); started = true
        Thread.sleep(forTimeInterval: QuietTone.duration + 0.15)
        try checked(AudioOutputUnitStop(unit), "Stop quiet M60 test"); started = false
        try checked(AudioUnitUninitialize(unit), "Uninitialize test output"); initialized = false
        try checked(AudioComponentInstanceDispose(unit), "Dispose test output"); disposed = true
        retainedState.release()
        return "Quiet left-then-right test completed on the verified M60 USB output. Listening is needed to confirm the speaker channels; this is not an audio-quality measurement."
    }
    private static func checked(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw HardwareError(operation: operation, status: status) }
    }
    private static func property<T>(_ unit: AudioUnit, _ selector: AudioUnitPropertyID, _ scope: AudioUnitScope,
                                    _ element: AudioUnitElement, _ value: inout T) throws {
        let result = withUnsafePointer(to: &value) { AudioUnitSetProperty(unit, selector, scope, element, $0, UInt32(MemoryLayout<T>.size)) }
        try checked(result, "Configure test output \(selector)")
    }
}
