import SeawallCore
import SwiftUI

/// Today at a glance, at the bottom of the menu: what's scheduled, what's running, where now
/// is, and what starts next. Clicking it opens the Today page.
struct TodayStrip: View {
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let now = controller.now
        let stretches = Timeline.stretches(on: now, schedules: controller.config.schedules, colors: colors,
                                           running: controller.sessions)
        Button {
            Panels.showMain(.today, controller: controller)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                DayTrack(stretches: stretches, now: fraction(of: now), height: 8)
                HStack {
                    Text(nextText)
                    Spacer()
                    Text(lockedText)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open Today")
        .accessibilityLabel("Today: \(nextText). \(lockedText).")
    }

    private var colors: [UUID: ListColor] {
        Dictionary(uniqueKeysWithValues: controller.config.lists.map { ($0.id, $0.color) })
    }

    private func fraction(of date: Date) -> Double {
        let start = Calendar.current.startOfDay(for: date)
        return date.timeIntervalSince(start) / 86_400
    }

    private var nextText: String {
        guard let (date, schedule) = Timeline.nextStart(after: controller.now, schedules: controller.config.schedules) else {
            return "Nothing scheduled"
        }
        let name = controller.list(for: schedule)?.name ?? schedule.listName
        return "Next: \(name) \(Format.clockTime(date, relativeTo: controller.now))"
    }

    private var lockedText: String {
        let locked = controller.todayStats.locked
        return locked < 60 ? "Nothing locked today" : "\(Format.duration(locked)) locked today"
    }
}

/// One day, midnight to midnight: scheduled stretches striped, running ones solid, and a mark for now.
struct DayTrack: View {
    let stretches: [DayStretch]
    let now: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                ForEach(Array(stretches.enumerated()), id: \.offset) { _, stretch in
                    let color = stretch.color?.color ?? Color.sea
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(stretch.kind == .running ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.35)))
                        .overlay {
                            if stretch.kind == .scheduled {
                                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                                    .strokeBorder(color.opacity(0.7), lineWidth: 1)
                            }
                        }
                        .frame(width: max(height, width * (stretch.to - stretch.from)))
                        .offset(x: width * stretch.from)
                }
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2, height: height + 6)
                    .offset(x: width * now - 1)
            }
            .frame(height: height + 6)
        }
        .frame(height: height + 6)
        .accessibilityHidden(true)
    }
}
