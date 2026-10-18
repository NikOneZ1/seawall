import FocusLockCore
import SwiftUI

/// The text colour of the window behind us: what sits on top of a `Color.primary` fill.
private let inverted = Color(nsColor: .windowBackgroundColor)

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
        let fill = configuration.isPressed ? 0.16 : (isOn ? 0.09 : 0) + (hovering ? 0.05 : 0)
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isOn ? Color.primary : Color.primary.opacity(0.55))
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(max(fill, 0.001)))
                    .strokeBorder(Color.primary.opacity(isOn ? 0.06 : 0.14))
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

/// Press and hold to lock. The fill sweeps across and the label inverts under it,
/// so starting a block is a deliberate second, not a stray click.
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
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            shape.fill(Color.primary.opacity(isEnabled ? 0.09 : 0.04))
            label.foregroundStyle(Color.primary.opacity(isEnabled ? 1 : 0.35))
            ZStack {
                shape.fill(Color.primary)
                label.foregroundStyle(inverted)
            }
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * progress)
                }
            }
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
