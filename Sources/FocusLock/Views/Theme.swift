import FocusLockCore
import SwiftUI

/// The water from the block page, so the menu and the page a blocked tab lands on look like one place.
enum Deep {
    /// Lit water near the surface and deep water below it.
    static let surface = Color(red: 0.18, green: 0.52, blue: 0.58)
    static let depth = Color(red: 0.05, green: 0.22, blue: 0.27)
    /// Dark glass for quiet controls, and the text that sits on a white fill.
    static let glass = Color(red: 0.03, green: 0.16, blue: 0.19).opacity(0.35)
    static let ink = Color(red: 0.04, green: 0.18, blue: 0.21)
    /// Small mono labels: "UNTIL 18:02".
    static let accent = Color(red: 0.63, green: 0.88, blue: 0.92)
    static let sandLight = Color(red: 0.50, green: 0.52, blue: 0.42)
    static let sandDark = Color(red: 0.32, green: 0.36, blue: 0.31)
    /// Height of the sand at the bottom of the menu, tall enough for the finds lying in it.
    static let floor: CGFloat = 26

    /// The sand's top edge at `u` (0…1 across), in points from the bottom: two slow waves,
    /// like the floor on the block page. The water shader draws the same line.
    static func sandTop(at u: CGFloat) -> CGFloat {
        floor + sin(u * 7) * 2.2 + sin(u * 19 + 1) * 1.1
    }

    static func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(accent.opacity(0.85))
    }
}

/// Water lit from above, a few slanted rays, and a strip of sand along the bottom.
struct WaterBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Deep.surface, Deep.depth], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.2), .clear], center: UnitPoint(x: 0.65, y: -0.08), startRadius: 0, endRadius: 300)
            Canvas { context, size in
                for (i, x) in [0.14, 0.38, 0.6, 0.86].enumerated() {
                    let top = size.width * x, lean = size.height * 0.22, width = 14.0 + Double(i % 2) * 10
                    var ray = Path()
                    ray.move(to: CGPoint(x: top, y: 0))
                    ray.addLine(to: CGPoint(x: top + width, y: 0))
                    ray.addLine(to: CGPoint(x: top + width * 2 - lean, y: size.height))
                    ray.addLine(to: CGPoint(x: top - lean, y: size.height))
                    context.fill(ray, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.045), .white.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height * 0.7)))
                }
            }
            .blur(radius: 14)
            Sand()
                .fill(LinearGradient(colors: [Deep.sandLight, Deep.sandDark], startPoint: .top, endPoint: .bottom))
                .frame(height: Deep.floor + 6)
                .blur(radius: 0.6)
        }
        .ignoresSafeArea()
    }
}

/// The sand, up to `Deep.sandTop`.
private struct Sand: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...64 {
            let u = CGFloat(step) / 64
            path.addLine(to: CGPoint(x: rect.minX + rect.width * u, y: rect.maxY - Deep.sandTop(at: u)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The one selection control: every site and app is a chip with its icon. On is tinted with
/// the icon in colour, off is an outline with the icon in grey; a running block adds a small lock.
struct Chip<Icon: View>: View {
    let title: String
    let isOn: Bool
    var locked = false
    var help: String?
    var onRemove: (() -> Void)?
    let action: () -> Void
    @ViewBuilder let icon: Icon

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                    .saturation(isOn ? 1 : 0)
                    .opacity(isOn ? 1 : 0.55)
                Text(title)
                    .lineLimit(1)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(ChipStyle(isOn: isOn, hovering: hovering))
        .onHover { hovering = $0 }
        .help(help ?? title)
        .contextMenu {
            if let onRemove { Button("Remove", action: onRemove) }
        }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

private struct ChipStyle: ButtonStyle {
    let isOn: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill = configuration.isPressed ? 0.24 : (isOn ? 0.16 : 0) + (hovering ? 0.06 : 0)
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.6))
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(Deep.glass)
                    .overlay {
                        Capsule()
                            .fill(Color.white.opacity(max(fill, 0.001)))
                            .strokeBorder(Color.white.opacity(isOn ? 0.1 : 0.16))
                    }
            }
            .contentShape(.capsule)
    }
}

// MARK: - Icons

/// A site's own icon once it has been fetched, a globe until then.
struct SiteIcon: View {
    let pattern: String
    @ObservedObject private var icons = SiteIcons.shared

    var body: some View {
        if let host = SiteRule(pattern)?.host, let image = icons.icon(for: host) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(.rect(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }
}

struct AppIcon: View {
    let image: NSImage?

    var body: some View {
        if let image {
            // App icons carry their own margin, so they draw a little larger to match.
            Image(nsImage: image)
                .resizable()
                .frame(width: 19, height: 19)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "app")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }

    init(path: String) {
        image = NSWorkspace.shared.icon(forFile: path)
    }

    init(bundleID: String) {
        image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// The browsers "Other browsers" will actually close here, overlapping.
struct BrowsersIcon: View {
    var body: some View {
        let icons = InstalledBrowsers.all.prefix(3)
        if icons.isEmpty {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        } else {
            HStack(spacing: -8) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, browser in
                    Image(nsImage: browser.icon)
                        .resizable()
                        .frame(width: 19, height: 19)
                        .frame(width: 16, height: 16)
                }
            }
        }
    }
}

/// Installed browsers other than Safari.
enum InstalledBrowsers {
    static let all: [(name: String, icon: NSImage)] = KnownBrowsers.all.compactMap { browser in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else { return nil }
        return (browser.name, NSWorkspace.shared.icon(forFile: url.path))
    }
}

// MARK: - Layout

/// Lays chips out like words, wrapping onto the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

// MARK: - Actions

/// Press and hold to lock. A white fill sweeps across the dark glass pill and the label
/// turns deep under it, so starting a block is a deliberate second, not a stray click.
struct HoldButton: View {
    static let holdTime = 0.8

    let title: String
    let isEnabled: Bool
    /// Told when a press starts and stops, to explain what's about to happen.
    var onPressing: (Bool) -> Void = { _ in }
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false

    var body: some View {
        let shape = Capsule()
        ZStack {
            shape.fill(Deep.glass)
                .overlay { shape.fill(Color.white.opacity(isEnabled ? 0.1 : 0.03)) }
                .overlay { shape.strokeBorder(Color.white.opacity(isEnabled ? 0.18 : 0.1)) }
            label.foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.4))
            ZStack {
                shape.fill(Color.white.opacity(0.92))
                label.foregroundStyle(Deep.ink)
            }
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * progress)
                }
            }
            // A zero-width mask still lets a hairline of the round end through.
            .opacity(progress > 0 ? 1 : 0)
        }
        .frame(height: 40)
        .contentShape(shape)
        .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 40) {
            guard isEnabled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            action()
            setPressing(false)
            withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
        } onPressingChanged: { isPressing in
            guard isEnabled else { return }
            setPressing(isPressing)
            withAnimation(isPressing ? .linear(duration: Self.holdTime) : .easeOut(duration: 0.25)) {
                progress = isPressing ? 1 : 0
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityAction { if isEnabled { action() } }
    }

    private var label: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(pressing ? "Keep holding…" : title)
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private func setPressing(_ value: Bool) {
        pressing = value
        onPressing(value)
    }
}

/// Small text actions. Quiet until hovered.
struct QuietButton: View {
    let title: String
    var destructive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Time

/// A hairline that fills as the block runs.
struct ProgressHairline: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(Color.primary.opacity(0.75))
                    .frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 2)
    }
}

/// "4:59" with the seconds ":12" a step quieter.
struct CountdownText: View {
    let seconds: TimeInterval

    var body: some View {
        let text = Format.countdown(seconds)
        let split = text.lastIndex(of: ":") ?? text.endIndex
        (Text(text[..<split]) + Text(text[split...]).foregroundStyle(.tertiary))
            .monospacedDigit()
    }
}
