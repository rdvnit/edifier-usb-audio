import AppKit
import Foundation

@main
struct MakeIcon {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let image = NSImage(size: NSSize(width: pixels, height: pixels))
                image.lockFocus()
                let s = CGFloat(pixels)
                let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
                NSColor(red: 0.06, green: 0.38, blue: 0.42, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: s * 0.19, yRadius: s * 0.19).fill()
                for x in [0.21, 0.53] {
                    let cabinet = NSRect(x: s * x, y: s * 0.22, width: s * 0.26, height: s * 0.57)
                    NSColor(white: 0.94, alpha: 1).setFill()
                    NSBezierPath(roundedRect: cabinet, xRadius: s * 0.04, yRadius: s * 0.04).fill()
                    NSColor(red: 0.04, green: 0.27, blue: 0.30, alpha: 1).setFill()
                    NSBezierPath(ovalIn: NSRect(x: cabinet.midX - s * 0.035, y: s * 0.66, width: s * 0.07, height: s * 0.07)).fill()
                    NSBezierPath(ovalIn: NSRect(x: cabinet.midX - s * 0.09, y: s * 0.32, width: s * 0.18, height: s * 0.18)).fill()
                    NSColor(red: 0.12, green: 0.62, blue: 0.64, alpha: 1).setFill()
                    NSBezierPath(ovalIn: NSRect(x: cabinet.midX - s * 0.035, y: s * 0.375, width: s * 0.07, height: s * 0.07)).fill()
                }
                image.unlockFocus()
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "IconGeneration", code: 1)
                }
                let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try png.write(to: folder.appendingPathComponent(filename))
            }
        }
    }
}
