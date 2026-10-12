import SwiftUI

// Original vector illustration, drawn from cabinet/driver geometry. No vendor
// photograph, logo, traced asset or external dependency is included. White is an
// illustrative finish, not a detected property of the connected speaker.
struct DeviceArtwork: View {
    let connected: Bool

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 340, size.height / 240)
            context.translateBy(x: (size.width - 340 * scale) / 2,
                                y: (size.height - 240 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            var shadow = context
            shadow.addFilter(.blur(radius: 10))
            shadow.fill(Path(ellipseIn: CGRect(x: 32, y: 211, width: 295, height: 15)),
                        with: .color(.black.opacity(0.45)))
            cabinet(context, x: 25, y: 26, width: 99, height: 172, depth: 55)
            cabinet(context, x: 152, y: 44, width: 103, height: 176, depth: 62)
        }
        .saturation(connected ? 1 : 0)
        .opacity(connected ? 1 : 0.32)
        .accessibilityLabel(connected ? "M60 speaker pair illustration, white illustrative finish" : "Disconnected M60 speaker pair illustration")
    }

    private func cabinet(_ context: GraphicsContext, x: CGFloat, y: CGFloat,
                         width: CGFloat, height: CGFloat, depth: CGFloat) {
        let slope: CGFloat = 11
        let backY = y - 19
        let front = face([
            CGPoint(x: x, y: y), CGPoint(x: x + width, y: y + slope),
            CGPoint(x: x + width, y: y + height + slope), CGPoint(x: x, y: y + height)
        ], radius: 8)
        let side = face([
            CGPoint(x: x + width - 3, y: y + slope), CGPoint(x: x + width + depth, y: backY + slope),
            CGPoint(x: x + width + depth, y: backY + height + slope), CGPoint(x: x + width - 3, y: y + height + slope)
        ], radius: 7)
        let top = face([
            CGPoint(x: x, y: y + 3), CGPoint(x: x + depth, y: backY),
            CGPoint(x: x + width + depth, y: backY + slope), CGPoint(x: x + width, y: y + slope + 3)
        ], radius: 7)
        context.fill(side, with: .linearGradient(Gradient(colors: [Color(white: 0.77), Color(white: 0.91)]),
                     startPoint: CGPoint(x: x + width, y: y), endPoint: CGPoint(x: x + width + depth, y: y + height)))
        context.fill(top, with: .linearGradient(Gradient(colors: [Color(white: 0.99), Color(white: 0.89)]),
                     startPoint: CGPoint(x: x, y: backY), endPoint: CGPoint(x: x, y: y + 20)))
        context.fill(front, with: .linearGradient(Gradient(colors: [Color(white: 0.96), Color(white: 0.84), Color(white: 0.95)]),
                     startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + width, y: y + height)))
        context.stroke(front, with: .color(.white.opacity(0.5)), lineWidth: 0.7)
        driver(context, center: CGPoint(x: x + width * 0.5, y: y + 44), radius: 15)
        driver(context, center: CGPoint(x: x + width * 0.5, y: y + 116), radius: 39)
    }

    private func driver(_ context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        func oval(_ factor: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius * factor * 0.83,
                                   y: center.y - radius * factor,
                                   width: radius * factor * 1.66, height: radius * factor * 2))
        }
        context.fill(oval(1.12), with: .color(Color(white: 0.78)))
        context.fill(oval(1.03), with: .color(Color(white: 0.10)))
        context.stroke(oval(0.96), with: .color(Color(white: 0.37)), lineWidth: 1)
        context.fill(oval(0.89), with: .linearGradient(Gradient(colors: [Color(white: 0.30), Color(white: 0.08), Color(white: 0.24)]),
                     startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                     endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
        context.stroke(oval(0.76), with: .color(.black.opacity(0.65)), lineWidth: radius > 20 ? 3 : 1)
        context.fill(oval(0.43), with: .radialGradient(Gradient(colors: [Color(white: 0.39), Color(white: 0.07), .black]),
                     center: CGPoint(x: center.x - radius * 0.14, y: center.y - radius * 0.20),
                     startRadius: 0, endRadius: radius * 0.65))
        let highlight = Path(ellipseIn: CGRect(x: center.x - radius * 0.20, y: center.y - radius * 0.30,
                                               width: radius * 0.24, height: radius * 0.13))
        context.fill(highlight, with: .color(.white.opacity(0.33)))
    }

    private func face(_ corners: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        for index in corners.indices {
            let previous = corners[(index + corners.count - 1) % corners.count]
            let current = corners[index]
            let next = corners[(index + 1) % corners.count]
            func near(_ point: CGPoint) -> CGPoint {
                let distance = hypot(point.x - current.x, point.y - current.y)
                let fraction = min(radius / distance, 0.25)
                return CGPoint(x: current.x + (point.x - current.x) * fraction,
                               y: current.y + (point.y - current.y) * fraction)
            }
            let incoming = near(previous)
            if index == 0 { path.move(to: incoming) } else { path.addLine(to: incoming) }
            path.addQuadCurve(to: near(next), control: current)
        }
        path.closeSubpath()
        return path
    }
}
