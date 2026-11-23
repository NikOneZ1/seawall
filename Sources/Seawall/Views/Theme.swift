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

/// One corner shape, the Soft look (chosen 2026-11-23): 8 on small controls, 10 on big ones and
/// tiles, 12 on cards. The blocked page and the site use the same.
enum Radius {
    static let small: CGFloat = 8
    static let control: CGFloat = 10
    static let card: CGFloat = 12
}

/// Apple's own text styles, four of them. The timer is the one exception, and it uses
/// monospaced digits so it doesn't jitter.
extension Font {
    static let timer = Font.system(size: 34, weight: .semibold).monospacedDigit()
}

// MARK: - Colour

extension Color {
    /// Seawall's ink, from the Timetable look: the one prominent fill (Hold to lock, the primary
    /// button) and the mark on a picked option. Near-black in light mode, near-white in dark mode.
    static let ink = dynamic(light: (0.086, 0.086, 0.086), dark: (0.949, 0.949, 0.941))
    /// The label on an ink fill: white in light mode, ink in dark mode.
    static let onInk = dynamic(light: (1, 1, 1), dark: (0.086, 0.086, 0.086))
    /// Red means a time and nothing else, as on the blocked page: the wait's ring, a block's end.
    static let time = dynamic(light: (0.85, 0.19, 0.15), dark: (1.0, 0.35, 0.31))
    /// The colour a list without one of its own is drawn in: the Sea list colour.
    static let sea = ListColor.sea.color
    /// A soft grey tile: an unpicked option, a secondary button, a card. No outlines in the Soft look.
    static let surface = Color.primary.opacity(0.07)
    static let surfaceHover = Color.primary.opacity(0.11)
    /// A hold's progress across the ink button: a lighter grey in light mode, a darker one in
    /// dark mode. The label stays at least 9:1 against it.
    static let holdProgress = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0.18)
            : NSColor(white: 1, alpha: 0.24)
    })

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension ListColor {
    /// The list's colour, tuned to read in light mode and dark mode.
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

// MARK: - Hold to lock

/// Press and hold to lock: a deliberate second, never a stray click. A soft fill moves across
/// the button while held, easing in and out. Holding Return or Space does the same from the
/// keyboard, and VoiceOver gets a plain "Lock" action.
struct HoldButton: View {
    static let holdTime = 0.8

    let title: String
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the hold has gone, 0 at rest and 1 when the lock takes.
    @State private var progress: Double = 0
    @State private var pressing = false
    /// Set by a finished hold, so the release that follows doesn't cut the fill's fade-out short.
    @State private var completed = false
    @State private var flash = false
    @State private var keyHold: DispatchWorkItem?
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        // Off, it's a plain grey tile with a readable reason ("Add something to lock"), not faded ink.
        let fill = isEnabled ? Color.ink : Color.primary.opacity(0.1)
        let ink = isEnabled ? Color.onInk : Color.secondary
        ZStack(alignment: .leading) {
            shape.fill(fill)
            // The hold's progress, a soft fill moving across.
            GeometryReader { proxy in
                shape.fill(Color.holdProgress)
                    .frame(width: proxy.size.width * (isEnabled ? progress : 0))
            }
            .clipShape(shape)
            label
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 36)
        .overlay { shape.strokeBorder(Color.white.opacity(flash ? 0.9 : 0), lineWidth: 2) }
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .contentShape(shape)
        .focusable(isEnabled, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous).strokeBorder(Color.ink.opacity(0.5), lineWidth: 2).padding(-3) } }
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
        guard !reduceMotion else {
            if !value { progress = 0 }
            return
        }
        if value {
            completed = false
            withAnimation(.timingCurve(0.35, 0, 0.25, 1, duration: Self.holdTime)) { progress = 1 }
        } else if !completed {
            withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
        }
    }

    private func complete() {
        guard isEnabled else { return }
        keyHold = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        flash = true
        withAnimation(.easeOut(duration: 0.35).delay(0.3)) { flash = false }
        // A moment full, then back to empty: the button can be on screen again for another block.
        completed = true
        withAnimation(.easeInOut(duration: 0.5).delay(0.35)) { progress = 0 }
        pressing = false
        action()
    }
}

/// The one prominent button style, the hold button's colours at a normal size. `large` is for
/// a window's footer (Continue).
struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: large ? Radius.control : Radius.small, style: .continuous)
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.onInk)
            .padding(.horizontal, large ? Space.l : Space.m)
            .frame(minHeight: large ? 32 : 26)
            .background(shape.fill(Color.ink)
                .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.35)))
            .contentShape(shape)
    }
}

/// Every other button: a soft grey tile, no outline. Set on the menu and the welcome as the default.
struct SoftButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: large ? Radius.control : Radius.small, style: .continuous)
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, large ? Space.l : Space.m)
            .frame(minHeight: large ? 32 : 26)
            .background(shape.fill(configuration.isPressed || hovering ? Color.surfaceHover : Color.surface))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}

/// One option of a few side by side (25m, 1h, 2h): ink when picked, a soft tile when not.
struct ChoiceButtonStyle: ButtonStyle {
    let isOn: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isOn ? Color.onInk : Color.primary)
            .padding(.horizontal, Space.s + 2)
            .frame(minHeight: 26)
            .background(shape.fill(isOn ? Color.ink : (configuration.isPressed || hovering ? Color.surfaceHover : Color.surface)))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    /// Draws this view's contents as if on an ink fill: light on dark in light mode, and the
    /// other way round in dark mode, so `.primary` and `.secondary` read on the fill.
    func onInk(_ isOn: Bool, scheme: ColorScheme) -> some View {
        environment(\.colorScheme, isOn ? (scheme == .dark ? .light : .dark) : scheme)
    }
}

/// The label's icon in Seawall's ink, its text in the usual colour.
struct SeaIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon
                .foregroundStyle(Color.ink)
            configuration.title
        }
    }
}

// MARK: - Lists

/// A list's mark: its symbol in ink on a soft tile, and the list's colour as a small dot. The
/// colour only tells lists apart; everything else stays black and white.
struct ListBadge: View {
    let symbol: String
    let color: ListColor
    var size: CGFloat = 22

    var body: some View {
        let dot = max(6, (size * 0.3).rounded())
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Color.primary.opacity(0.09)))
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(color.color)
                    .frame(width: dot, height: dot)
                    .offset(x: dot * 0.3, y: dot * 0.3)
            }
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
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

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
            .foregroundStyle(.primary)
            .onInk(isSelected, scheme: scheme)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isSelected ? Color.ink : (hovering ? Color.surfaceHover : Color.surface))
            }
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(list.name), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isSelected ? "\(list.name) is picked for the next block" : "Pick \(list.name)")
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
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0.03))
            }
            .contentShape(.rect(cornerRadius: Radius.card))
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
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.primary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.ink).frame(width: width * fill)
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
            // Logos in black and white, so a page of them doesn't turn into a rainbow.
            Image(nsImage: image.monochrome)
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
            Image(nsImage: image.monochrome)
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

/// A category's mark: its symbol in ink on a soft tile, like a list's, without the dot.
struct GroupIcon: View {
    let group: SiteGroup
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: group.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.primary.opacity(0.09)))
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
                    Image(nsImage: browser.icon.monochrome)
                        .resizable()
                        .frame(width: size * 1.2, height: size * 1.2)
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

extension NSImage {
    private static let monochromes = NSCache<NSImage, NSImage>()

    /// The same image in black and white, so logos don't turn a page into a rainbow. Drawn once
    /// per image and kept; a view filter (`.grayscale`) isn't drawn in every context, this is.
    var monochrome: NSImage {
        if let done = Self.monochromes.object(forKey: self) { return done }
        guard let tiff = tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIPhotoEffectMono") else { return self }
        filter.setValue(input, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return self }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        Self.monochromes.setObject(image, forKey: self)
        return image
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
