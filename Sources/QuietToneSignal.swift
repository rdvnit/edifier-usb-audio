import Foundation

// Pure waveform math; tested without creating an audio unit or touching hardware.
enum QuietTone {
    static let duration: Double = 2.0
    static let amplitude: Double = 0.02
    static func sample(time: Double, channel: Int) -> Float {
        let start = channel == 0 ? 0.10 : 1.10
        let local = time - start
        guard time.isFinite, (channel == 0 || channel == 1), local > 0, local < 0.70 else { return 0 }
        let envelope = min(1, min(local / 0.05, (0.70 - local) / 0.05))
        return Float(amplitude * envelope * sin(2 * Double.pi * 440 * local))
    }
}
