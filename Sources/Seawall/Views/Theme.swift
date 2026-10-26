import SeawallCore
import SwiftUI

// MARK: - Scale

/// One spacing scale for everything, on a 4-point grid.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
}

/// Apple's own text styles, four of them. The timer is the one exception, and it uses
/// monospaced digits so it doesn't jitter.
extension Font {
    static let timer = Font.system(size: 34, weight: .semibold).monospacedDigit()
}

// MARK: - Surfaces and colour

/// What the menu is drawn on: clear system glass, or the sea. Controls pick their look from it.
enum SeaSurface {
    case glass, water
}

private struct SeaSurfaceKey: EnvironmentKey {
    static let defaultValue = SeaSurface.glass
}

extension EnvironmentValues {
    var seaSurface: SeaSurface {
        get { self[SeaSurfaceKey.self] }
        set { self[SeaSurfaceKey.self] = newValue }
    }
}

extension Color {
    /// Seawall's teal: deeper in light mode, lighter in dark mode and on the water.
    static let sea = dynamic(light: (0.07, 0.44, 0.49), dark: (0.40, 0.80, 0.84))
    /// The teal behind a filled button's label: white on deep teal in light mode, near-black
    /// on lighter teal in dark mode. White on the light teal measured under 2:1.
    static let seaFill = dynamic(light: (0.07, 0.44, 0.49), dark: (0.36, 0.75, 0.79))
    static let onSeaFill = dynamic(light: (1, 1, 1), dark: (0.02, 0.17, 0.19))
    /// A hold's progress across a filled button, moving away from the label's colour so the
    /// label only gets easier to read: darker in light mode, lighter in dark mode.
    static let seaTide = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.32)
            : NSColor(white: 0, alpha: 0.24)
    })

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension ListColor {
    /// The list's colour, tuned to read in light mode, dark mode and on the water.
    var color: Color {
        switch self {
        case .sea: Self.pair(light: (0.10, 0.56, 0.58), dark: (0.37, 0.81, 0.78))
        case .coral: Self.pair(light: (0.85, 0.36, 0.30), dark: (1.00, 0.55, 0.48))
        case .violet: Self.pair(light: (0.47, 0.38, 0.86), dark: (0.68, 0.62, 1.00))
        case .amber: Self.pair(light: (0.80, 0.53, 0.06), dark: (0.96, 0.75, 0.36))
        case .leaf: Self.pair(light: (0.24, 0.58, 0.29), dark: (0.50, 0.82, 0.48))
        case .sky: Self.pair(light: (0.16, 0.48, 0.85), dark: (0.48, 0.70, 1.00))
        case .rose: Self.pair(light: (0.82, 0.29, 0.55), dark: (1.00, 0.52, 0.72))
        case .slate: Self.pair(light: (0.38, 0.44, 0.50), dark: (0.66, 0.72, 0.78))
        }
    }

    var title: String { rawValue.capitalized }

    private static func pair(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// The water from the block page, so the menu and the page a blocked tab lands on look like one place.
enum Deep {
    /// Lit water near the surface and deep water below it.
    static let surface = Color(red: 0.18, green: 0.52, blue: 0.58)
    static let depth = Color(red: 0.05, green: 0.22, blue: 0.27)
    static let ink = Color(red: 0.04, green: 0.18, blue: 0.21)
    static let sandLight = Color(red: 0.50, green: 0.52, blue: 0.42)
    static let sandDark = Color(red: 0.32, green: 0.36, blue: 0.31)
    /// Height of the sand at the bottom of the menu.
    static let floor: CGFloat = 12

    /// The sand's top edge at `u` (0…1 across), in points from the bottom: two slow waves,
    /// like the floor on the block page. The water shader draws the same line.
    static func sandTop(at u: CGFloat) -> CGFloat {
        floor + sin(u * 7) * 2.2 + sin(u * 19 + 1) * 1.1
    }
}

/// Water lit from above and a strip of sand: the still version, where Metal isn't available.
struct WaterBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Deep.surface, Deep.depth], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.2), .clear], center: UnitPoint(x: 0.65, y: -0.08), startRadius: 0, endRadius: 300)
            Sand()
                .fill(LinearGradient(colors: [Deep.sandLight, Deep.sandDark], startPoint: .top, endPoint: .bottom))
                .frame(height: Deep.floor + 6)
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

// MARK: - Hold to lock

/// How far the hold has gone: 0 at rest, 1 when the lock takes. The water rises with it
/// and everything but the button dims, until the button is the only light left.
@MainActor
final class Dive: ObservableObject {
    static let shared = Dive()

    @Published private(set) var depth: Double = 0
    /// Set by a finished hold, so the release that follows doesn't cut the way back up short.
    private var surfacing = false

    func press(_ on: Bool) {
        if on {
            surfacing = false
        } else if surfacing {
            return
        }
        let style = Preferences.shared.holdAnimation
        withAnimation(on ? style.holdCurve : style.releaseCurve) {
            depth = on ? 1 : 0
        }
    }

    /// A moment at the bottom, then back up.
    func surface() {
        surfacing = true
        withAnimation(.easeInOut(duration: 0.6).delay(0.35)) { depth = 0 }
    }
}

/// Press and hold to lock: a deliberate second, never a stray click. The capsule fills from
/// the leading edge while held. Holding Return or Space does the same from the keyboard,
/// and VoiceOver gets a plain "Lock" action.
struct HoldButton: View {
    static let holdTime = 0.8

    let title: String
    let isEnabled: Bool
    /// Told when a press starts and stops.
    var onPressing: (Bool) -> Void = { _ in }
    let action: () -> Void

    @Environment(\.seaSurface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var dive = Dive.shared
    @ObservedObject private var preferences = Preferences.shared
    @State private var pressing = false
    @State private var flash = false
    @State private var keyHold: DispatchWorkItem?
    @FocusState private var focused: Bool

    var body: some View {
        let shape = Capsule()
        let water = surface == .water
        // Off, it's a plain grey pill with a readable reason ("Add something to lock"), not faded teal.
        let fill = isEnabled ? (water ? Color.white : .seaFill) : Color.primary.opacity(0.1)
        let ink = isEnabled ? (water ? Deep.ink : .onSeaFill) : Color.secondary
        ZStack(alignment: .leading) {
            shape.fill(fill)
            // The hold's progress, drawn the way Settings' "Hold to lock animation" says.
            HoldFill(progress: isEnabled ? dive.depth : 0, style: preferences.holdAnimation,
                     color: water ? Color.sea.opacity(0.35) : .seaTide)
                .clipShape(shape)
            label
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 36)
        // The menu's sea blooms from here.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: HoldPointKey.self, value: proxy.frame(in: .named(HoldPointKey.space)).center)
            }
        }
        .overlay { shape.strokeBorder(Color.white.opacity(flash ? 0.9 : 0), lineWidth: 2) }
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .contentShape(shape)
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { shape.strokeBorder(Color.accentColor, lineWidth: 2).padding(-3) } }
        .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 40) {
            complete()
        } onPressingChanged: { isPressing in
            guard isEnabled else { return }
            setPressing(isPressing)
        }
        .onKeyPress(keys: [.return, .space], phases: [.down, .up]) { press in
            guard isEnabled else { return .ignored }
            if press.phase == .down, keyHold == nil {
                setPressing(true)
                let work = DispatchWorkItem { complete() }
                keyHold = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdTime, execute: work)
            } else if press.phase == .up {
                keyHold?.cancel()
                keyHold = nil
                if pressing { setPressing(false) }
            }
            return .handled
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? "Press and hold to lock" : "")
        .accessibilityAction { if isEnabled { action() } }
    }

    private var label: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(pressing ? "Keep holding…" : title)
        }
        .font(.headline)
    }

    private func setPressing(_ value: Bool) {
        pressing = value
        onPressing(value)
        if reduceMotion {
            if !value { dive.press(false) }
        } else {
            dive.press(value)
        }
    }

    private func complete() {
        guard isEnabled else { return }
        keyHold = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        flash = true
        withAnimation(.easeOut(duration: 0.35).delay(0.3)) { flash = false }
        dive.surface()
        pressing = false
        onPressing(false)
        action()
    }
}

/// Where the hold button's middle is, in the menu's own coordinates.
struct HoldPointKey: PreferenceKey {
    static let space = "seawall.menu"
    static let defaultValue: CGPoint? = nil
    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
        value = nextValue() ?? value
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// A hold's progress across the button. Animatable, so SwiftUI hands it every in-between
/// value of the hold's curve and the gradients below are redrawn for each one.
private struct HoldFill: View, Animatable {
    var progress: Double
    let style: HoldAnimation
    let color: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        GeometryReader { proxy in
            switch style {
            case .classic:
                // A bar from the leading edge.
                Rectangle().fill(color).frame(width: proxy.size.width * p)
            case .tide:
                // The same sweep, with a soft front instead of an edge.
                let feather = 0.45
                let front = p * (1 + feather)
                Rectangle().fill(LinearGradient(stops: [
                    .init(color: color, location: min(max(front - feather, 0), 1)),
                    .init(color: color.opacity(0), location: min(max(front, 0), 1)),
                ], startPoint: .leading, endPoint: .trailing))
                .opacity(min(1, p * 8))
            case .bloom:
                // A soft circle opening from the middle.
                let reach = proxy.size.width / 2 / 0.55
                Rectangle().fill(RadialGradient(stops: [
                    .init(color: color, location: 0),
                    .init(color: color, location: 0.55),
                    .init(color: color.opacity(0), location: 1),
                ], center: .center, startRadius: 0, endRadius: max(1, reach * p * 1.02)))
                .opacity(min(1, p * 8))
            case .tint:
                // The whole button warms at once.
                Rectangle().fill(color).opacity(p)
            }
        }
    }
}

/// The one prominent button style in the menu, the hold button's colours at a normal size:
/// teal on glass, white on the water.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.seaSurface) private var surface
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(surface == .water ? Deep.ink : Color.onSeaFill)
            .padding(.horizontal, Space.m)
            .frame(height: 24)
            .background(Capsule().fill(surface == .water ? Color.white : Color.seaFill)
                .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.4)))
            .contentShape(Capsule())
    }
}

// MARK: - Lists

/// A list's mark: its symbol on its colour.
struct ListBadge: View {
    let symbol: String
    let color: ListColor
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.color))
            .accessibilityHidden(true)
    }
}

/// A list in the menu: its mark, then its name and when it runs on its own (or how much it
/// holds) beside it, two to a row so names have room. The picked one is filled in.
struct ListCard: View {
    let list: BlockList
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    static let height: CGFloat = 46
    @Environment(\.seaSurface) private var surface
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ListBadge(symbol: list.symbol, color: list.color, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(list.name)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill(isSelected ? AnyShapeStyle(selectedFill) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.08 : 0.04)))
                shape.strokeBorder(isSelected ? list.color.color : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(list.name), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isSelected ? "\(list.name) is picked for the next block" : "Pick \(list.name)")
    }

    private var selectedFill: Color {
        list.color.color.opacity(surface == .water ? 0.32 : 0.16)
    }
}

/// The "+" card at the end of the last row.
struct NewListCard: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                Text("Add a list")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: ListCard.height)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? 0.3 : 0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Make a new list in the Seawall window")
    }
}

// MARK: - Time

/// A slim bar that fills as the block runs. For a block in rounds, one segment per round.
struct ProgressBar: View {
    let value: Double
    var segments: Int = 1

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = segments > 1 ? 3 : 0
            let width = (proxy.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { index in
                    let start = Double(index) / Double(segments)
                    let fill = min(max((value - start) * Double(segments), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(Color.primary.opacity(0.8)).frame(width: width * fill)
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
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
            .accessibilityLabel(Format.duration(seconds) + " left")
    }
}

// MARK: - Icons

/// A site's own icon once it has been fetched, a globe until then.
struct SiteIcon: View {
    let pattern: String
    var size: CGFloat = 16
    @ObservedObject private var icons = SiteIcons.shared

    var body: some View {
        if let host = SiteRule(pattern)?.host, let image = icons.icon(for: host) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size / 4, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

struct AppIcon: View {
    let image: NSImage?
    var size: CGFloat = 16

    var body: some View {
        if let image {
            // App icons carry their own margin, so they draw a little larger to match.
            Image(nsImage: image)
                .resizable()
                .frame(width: size * 1.2, height: size * 1.2)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    init(path: String, size: CGFloat = 16) {
        image = NSWorkspace.shared.icon(forFile: path)
        self.size = size
    }

    init(bundleID: String, size: CGFloat = 16) {
        image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        self.size = size
    }
}

/// A category's mark: its symbol on its colour, like a list's.
struct GroupIcon: View {
    let group: SiteGroup
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: group.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(group.color))
    }
}

extension SiteGroup {
    var symbol: String {
        switch self {
        case .games: "gamecontroller.fill"
        case .social: "bubble.left.and.bubble.right.fill"
        case .video: "play.rectangle.fill"
        case .news: "newspaper.fill"
        case .shopping: "bag.fill"
        case .web: "globe"
        }
    }

    var color: Color {
        switch self {
        case .games: Color(red: 0.52, green: 0.42, blue: 0.92)
        case .social: Color(red: 0.90, green: 0.38, blue: 0.58)
        case .video: Color(red: 0.92, green: 0.30, blue: 0.27)
        case .news: Color(red: 0.25, green: 0.53, blue: 0.86)
        case .shopping: Color(red: 0.92, green: 0.58, blue: 0.16)
        case .web: Color(red: 0.10, green: 0.56, blue: 0.58)
        }
    }
}

/// The browsers "Other browsers" will actually close here, overlapping.
struct BrowsersIcon: View {
    var size: CGFloat = 16

    var body: some View {
        let icons = InstalledBrowsers.unreadable.prefix(3)
        if icons.isEmpty {
            Image(systemName: "globe")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            HStack(spacing: -size / 2) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, browser in
                    Image(nsImage: browser.icon)
                        .resizable()
                        .frame(width: size * 1.2, height: size * 1.2)
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

// MARK: - Keys

extension View {
    /// Esc runs `action`. A hidden button with the Cancel shortcut, because `onExitCommand`
    /// needs keyboard focus, which the menu usually doesn't have.
    func onEscape(_ action: @escaping () -> Void) -> some View {
        background {
            Button("", action: action)
                .keyboardShortcut(.cancelAction)
                .hidden()
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Layout

/// Lays views out like words, wrapping onto the next line.
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
