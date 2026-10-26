import SeawallCore
import SwiftUI

/// Today in numbers: time locked, tries caught, days in a row, today's timeline, the last few
/// blocks, and any shells found in the sand on earlier block pages.
struct TodayPane: View {
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let stats = controller.todayStats
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(spacing: Space.m) {
                    tile(stats.locked < 60 ? "None" : Format.duration(stats.locked), "locked today")
                    tile("\(stats.attempts)", stats.attempts == 1 ? "try caught" : "tries caught")
                    tile(Format.count(stats.streak, "day", "days"), "in a row with a block")
                }
                timeline
                recent
                if !controller.finds.isEmpty { finds }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Today")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private var timeline: some View {
        let now = controller.now
        let colors = Dictionary(uniqueKeysWithValues: controller.config.lists.map { ($0.id, $0.color) })
        let past = controller.history
            .filter { $0.endedAt > Calendar.current.startOfDay(for: now) }
            .map { record -> DayStretch in
                let start = Calendar.current.startOfDay(for: now)
                return DayStretch(from: max(0, record.startedAt.timeIntervalSince(start) / 86_400),
                                  to: min(1, record.endedAt.timeIntervalSince(start) / 86_400),
                                  kind: .running, color: record.color)
            }
        let stretches = past + Timeline.stretches(on: now, schedules: controller.config.schedules, colors: colors, running: controller.sessions)
        return VStack(alignment: .leading, spacing: Space.s) {
            Text("Today's blocks")
                .font(.headline)
            DayTrack(stretches: stretches, now: now.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 86_400, height: 14)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(String(format: "%02d:00", hour % 24))
                    if hour < 24 { Spacer() }
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            Text("Solid: blocks that ran or are running. Outlined: schedules.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recent: some View {
        let records = controller.history.suffix(6).reversed()
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Recent blocks")
                .font(.headline)
            if records.isEmpty {
                Text("Blocks you finish show up here.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                        if index > 0 { Divider() }
                        HStack(spacing: Space.s) {
                            Circle().fill(record.color?.color ?? .sea).frame(width: 8, height: 8)
                            Text(record.name).lineLimit(1)
                            if record.endedEarly {
                                Text("left early")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.span(record.startedAt, record.endedAt, relativeTo: controller.now))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(record.attempts == 0 ? "no tries" : Format.count(record.attempts, "try", "tries"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, Space.m)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    @ViewBuilder
    private var finds: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Found in the sand")
                .font(.headline)
            if controller.finds.isEmpty {
                EmptyView()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Space.s)], spacing: Space.s) {
                    ForEach(Array(controller.finds.reversed().enumerated()), id: \.offset) { index, find in
                        VStack(spacing: 4) {
                            Canvas { context, size in
                                FindDrawing.draw(find.kind, in: &context, at: CGPoint(x: size.width / 2, y: size.height / 2),
                                                 size: 20, tilt: CGFloat(index % 5) * 0.12 - 0.24, glowing: false)
                            }
                            .frame(width: 48, height: 40)
                            Text(find.kind.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(find.foundAt, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
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
