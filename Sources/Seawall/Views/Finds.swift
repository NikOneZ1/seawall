import SwiftUI

/// What you picked up on the block page, lying in the menu's sand. Hover one to see what it is
/// and when you found it. The newest ones that fit, no count to chase.
struct FindsShelf: View {
    let finds: [Find]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Spread across the floor, closer together as the collection grows.
            let shown = Array(finds.suffix(max(0, Int((width - 28) / 32))).enumerated())
            let spacing = shown.count > 1 ? min(64, (width - 48) / CGFloat(shown.count - 1)) : 0
            let start = (width - spacing * CGFloat(max(shown.count - 1, 0))) / 2
            ZStack(alignment: .topLeading) {
                ForEach(shown, id: \.offset) { index, find in
                    let x = start + CGFloat(index) * spacing + Self.jitter(index) * 6
                    FindView(find: find, tilt: Self.jitter(index + 7) * 0.4)
                        .position(x: x, y: proxy.size.height - Deep.sandTop(at: x / width) + 7)
                }
            }
        }
        .frame(height: Deep.floor + 34)
    }

    /// A steady -1…1 per slot, so the finds don't jump around between openings.
    private static func jitter(_ n: Int) -> CGFloat {
        let s = sin(Double(n) * 127.1 + 311.7) * 43758.5453
        return CGFloat(s - s.rounded(.down)) * 2 - 1
    }
}

private struct FindView: View {
    let find: Find
    let tilt: CGFloat
    @State private var hovering = false

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    var body: some View {
        Canvas { context, size in
            FindDrawing.draw(find.kind, in: &context, at: CGPoint(x: size.width / 2, y: size.height / 2), size: 17, tilt: tilt, glowing: hovering)
        }
        .frame(width: 44, height: 44)
        .offset(y: hovering ? -4 : 0)
        .overlay(alignment: .top) {
            if hovering {
                Text("\(find.kind.title) · found \(Self.date.string(from: find.foundAt))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Deep.ink.opacity(0.85)))
                    .fixedSize()
                    .offset(y: -22)
                    .transition(.opacity)
            }
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement()
        .accessibilityLabel("\(find.kind.title), found \(Self.date.string(from: find.foundAt))")
    }
}

/// The same small drawings as the block page's finds.
enum FindDrawing {
    static func draw(_ kind: Find.Kind, in context: inout GraphicsContext, at center: CGPoint, size s: CGFloat, tilt: CGFloat, glowing: Bool) {
        var c = context
        c.translateBy(x: center.x, y: center.y)

        var shadow = c
        shadow.addFilter(.blur(radius: s * 0.12))
        shadow.fill(Path(ellipseIn: CGRect(x: -s * 0.72, y: s * 0.22, width: s * 1.56, height: s * 0.4)), with: .color(Color(red: 0.03, green: 0.12, blue: 0.13).opacity(0.35)))

        if glowing {
            c.fill(Path(ellipseIn: CGRect(x: -s * 1.6, y: -s * 1.6, width: s * 3.2, height: s * 3.2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 0.88, green: 1, blue: 0.98).opacity(0.42), .clear]), center: .zero, startRadius: 0, endRadius: s * 1.6))
            c.scaleBy(x: 1.08, y: 1.08)
        }
        c.rotate(by: .radians(tilt))

        switch kind {
        case .scallop:
            var fan = Path()
            fan.move(to: CGPoint(x: 0, y: s * 0.35))
            for step in 0...24 {
                let a = .pi * (1.2 + 0.6 * CGFloat(step) / 24)
                fan.addLine(to: CGPoint(x: cos(a) * s * 0.78, y: s * 0.35 + sin(a) * s * 0.78))
            }
            fan.closeSubpath()
            c.fill(fan, with: .linearGradient(Gradient(colors: [rgb(244, 232, 214), rgb(210, 182, 147)]), startPoint: CGPoint(x: 0, y: -s * 0.5), endPoint: CGPoint(x: 0, y: s * 0.35)))
            for i in -3...3 {
                let a = .pi * (1.5 + CGFloat(i) * 0.1)
                var rib = Path()
                rib.move(to: CGPoint(x: 0, y: s * 0.35))
                rib.addLine(to: CGPoint(x: cos(a) * s * 0.74, y: s * 0.35 + sin(a) * s * 0.74))
                c.stroke(rib, with: .color(rgb(140, 100, 70).opacity(0.35)), lineWidth: s * 0.035)
            }
            c.fill(Path(CGRect(x: -s * 0.2, y: s * 0.26, width: s * 0.4, height: s * 0.12)), with: .color(rgb(205, 175, 138)))

        case .glass:
            var piece = Path()
            piece.move(to: CGPoint(x: -s * 0.5, y: -s * 0.05))
            piece.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.32), control: CGPoint(x: -s * 0.4, y: -s * 0.38))
            piece.addQuadCurve(to: CGPoint(x: s * 0.48, y: s * 0.05), control: CGPoint(x: s * 0.5, y: -s * 0.3))
            piece.addQuadCurve(to: CGPoint(x: -s * 0.05, y: s * 0.28), control: CGPoint(x: s * 0.4, y: s * 0.3))
            piece.addQuadCurve(to: CGPoint(x: -s * 0.5, y: -s * 0.05), control: CGPoint(x: -s * 0.55, y: s * 0.25))
            c.fill(piece, with: .color(rgb(150, 222, 190).opacity(0.88)))
            let glint = Path(ellipseIn: CGRect(x: -s * 0.16, y: -s * 0.06, width: s * 0.32, height: s * 0.12))
                .applying(CGAffineTransform(rotationAngle: -0.3).concatenating(CGAffineTransform(translationX: -s * 0.15, y: -s * 0.12)))
            c.fill(glint, with: .color(.white.opacity(0.45)))

        case .stone:
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.62, y: -s * 0.38, width: s * 1.24, height: s * 0.76)),
                   with: .radialGradient(Gradient(colors: [rgb(185, 188, 179), rgb(102, 106, 99)]), center: CGPoint(x: -s * 0.2, y: -s * 0.2), startRadius: s * 0.05, endRadius: s * 0.7))

        case .dollar:
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.5, y: -s * 0.5, width: s, height: s)), with: .color(rgb(238, 230, 212)))
            for i in 0..<5 {
                let a = CGFloat(i) / 5 * 2 * .pi - .pi / 2
                let petal = Path(ellipseIn: CGRect(x: -s * 0.15, y: -s * 0.05, width: s * 0.3, height: s * 0.1))
                    .applying(CGAffineTransform(rotationAngle: a).concatenating(CGAffineTransform(translationX: cos(a) * s * 0.2, y: sin(a) * s * 0.2)))
                c.fill(petal, with: .color(rgb(160, 135, 100).opacity(0.45)))
            }

        case .snail:
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.45, y: -s * 0.45, width: s * 0.9, height: s * 0.9)),
                   with: .radialGradient(Gradient(colors: [rgb(235, 216, 184), rgb(190, 156, 114)]), center: CGPoint(x: -s * 0.1, y: -s * 0.1), startRadius: 0, endRadius: s * 0.55))
            var spiral = Path()
            for step in 0...125 {
                let t = CGFloat(step) * 0.1, r = s * 0.04 + s * 0.4 * t / (4 * .pi)
                let point = CGPoint(x: cos(t) * r, y: sin(t) * r)
                step == 0 ? spiral.move(to: point) : spiral.addLine(to: point)
            }
            c.stroke(spiral, with: .color(rgb(110, 75, 45).opacity(0.5)), lineWidth: s * 0.05)

        case .star:
            var star = Path()
            for i in 0..<10 {
                let a = CGFloat(i) / 10 * 2 * .pi - .pi / 2, r = i % 2 == 1 ? s * 0.2 : s * 0.55
                let point = CGPoint(x: cos(a) * r, y: sin(a) * r)
                i == 0 ? star.move(to: point) : star.addLine(to: point)
            }
            star.closeSubpath()
            c.fill(star, with: .color(rgb(217, 148, 112)))
            c.stroke(star, with: .color(rgb(217, 148, 112)), style: StrokeStyle(lineWidth: s * 0.12, lineJoin: .round))
            for i in 0..<5 {
                let a = CGFloat(i) / 5 * 2 * .pi - .pi / 2
                c.fill(Path(ellipseIn: CGRect(x: cos(a) * s * 0.25 - s * 0.04, y: sin(a) * s * 0.25 - s * 0.04, width: s * 0.08, height: s * 0.08)),
                       with: .color(rgb(255, 230, 210).opacity(0.35)))
            }
        }
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
