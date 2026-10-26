import SeawallCore
import SwiftUI

/// The menu bar panel. Ready to lock it shows the lists and the hold button; while blocks
/// run it shows how long is left. The sea comes and goes with Settings' "Show the sea".
struct MenuView: View {
    @EnvironmentObject private var controller: BlockController
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var dive = Dive.shared
    @Environment(\.colorScheme) private var systemScheme
    /// Setting up one more block while others run.
    @State private var addingBlock = false
    /// Where the hold button is, for the sea to bloom from.
    @State private var holdPoint: CGPoint?

    var body: some View {
        let locked = !controller.sessions.isEmpty
        let level = seaLevel(locked: locked)
        // The controls switch to their water look once the sea is in for good, not while a
        // hold brings it up behind them.
        let onWater = preferences.sea == .always || (preferences.sea == .whileLocked && locked)
        VStack(alignment: .leading, spacing: Space.m) {
            Group {
                if !locked {
                    LockView()
                } else if addingBlock {
                    LockView(back: { addingBlock = false })
                } else {
                    LockedView(onAdd: { addingBlock = true })
                }
            }
            Divider()
                .padding(.horizontal, -Space.l)
            TodayStrip()
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m + 2)
        .padding(.bottom, onWater ? Space.m + Deep.floor : Space.m)
        .frame(width: 320)
        .coordinateSpace(name: HoldPointKey.space)
        .onPreferenceChange(HoldPointKey.self) { point in
            if let point, point != holdPoint { holdPoint = point }
        }
        .background { SeaBackground(level: level, rising: !onWater, style: preferences.holdAnimation, origin: holdPoint) }
        .environment(\.seaSurface, onWater ? .water : .glass)
        .environment(\.colorScheme, onWater ? .dark : systemScheme)
        .onContinuousHover { phase in
            guard level > 0 else { return }
            switch phase {
            case .active(let location): Water.shared.hover(location)
            case .ended: Water.shared.endHover()
            }
        }
        .onAppear {
            controller.refreshBrowserAccess()
            Water.shared.opened()
        }
        .background {
            Button("") { Panels.showMain(.settings, controller: controller) }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        .onChange(of: controller.sessions.isEmpty) { addingBlock = false }
        // A blocked site was just tried: the water clouds over.
        .onChange(of: controller.totalAttempts) { old, new in
            if new > old { Water.shared.attempt() }
        }
    }

    /// How high the water stands, 0 to 1: always full, full while locked and rising with a
    /// hold, or never there.
    private func seaLevel(locked: Bool) -> Double {
        switch preferences.sea {
        case .always: 1
        case .whileLocked: locked ? 1 : dive.depth
        case .never: 0
        }
    }
}

/// The live water, up to `level` of the panel's height: the tide coming in during a hold,
/// and staying while a block runs.
private struct SeaBackground: View {
    let level: Double
    /// Coming in under a held button, rather than already there when the menu opens.
    let rising: Bool
    let style: HoldAnimation
    /// The hold button's middle, in the panel's coordinates.
    let origin: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            if level > 0 {
                // A hold let go early drains gently; a block ending fades the sea out slowly.
                Tide(level: level, rising: rising, style: style, size: proxy.size, origin: origin)
                    .transition(.asymmetric(insertion: rising ? AnyTransition.identity : .opacity,
                                            removal: AnyTransition.opacity.animation(.easeOut(duration: rising ? style.releaseFade : 0.6))))
            }
        }
        .animation(.easeInOut(duration: 0.6), value: level > 0)
    }
}

/// The water itself, revealed as far as it has come. The progress lives here rather than in
/// the level passed in: a view that has just appeared has nothing to animate from, so the
/// water stood at full from the first frame instead of coming in.
private struct Tide: View {
    let level: Double
    let rising: Bool
    let style: HoldAnimation
    let size: CGSize
    let origin: CGPoint?
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SeaReveal(progress: shown, style: style, size: size,
                  origin: origin ?? CGPoint(x: size.width / 2, y: max(0, size.height - 100))) {
            WaterSurface()
        }
        .onAppear {
            if rising, !reduceMotion {
                withAnimation(style.holdCurve) { shown = level }
            } else {
                shown = level
            }
        }
        .onChange(of: level) { _, new in
            withAnimation(new < shown ? style.releaseCurve : .easeOut(duration: 0.3)) { shown = new }
        }
    }
}

/// Shows `content` to `progress` (0 nothing, 1 all of it), the way `style` does. Animatable, so
/// every frame of the hold's curve reaches `body`; at 1 it is exactly the full, plain water,
/// whichever style got it there.
private struct SeaReveal<Content: View>: View, Animatable {
    var progress: Double
    let style: HoldAnimation
    let size: CGSize
    let origin: CGPoint
    @ViewBuilder let content: Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // Exactly one modifier on the water: a mask, as before. Opacity and scale are folded
        // into the mask, so the Metal view underneath is handled the same as ever.
        content.mask { mask }
    }

    @ViewBuilder
    private var mask: some View {
        let p = min(max(progress, 0), 1)
        switch style {
        case .classic:
            // The first version: a mask whose height rises, with a short fade at its top.
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * p + (p < 1 ? 14 : 0))
                .frame(maxHeight: .infinity, alignment: .bottom)
        case .tide:
            // A band of mist, as tall as most of the menu, sliding up until it has passed over everything.
            // Its feather is so wide that there's never an edge to look at.
            let feather = max(size.height, 1) * 0.8
            let front = size.height - p * (size.height + feather)
            VStack(spacing: 0) {
                LinearGradient(stops: Ease.softStops, startPoint: .top, endPoint: .bottom)
                    .frame(height: feather)
                Color.black.frame(height: size.height)
            }
            .offset(y: front)
            .frame(width: size.width, height: size.height, alignment: .top)
            .opacity(Ease.smooth(p, 0, 0.3))
            .mask(Ease.topFade)
        case .bloom:
            // A soft circle from the hold button, wide enough at the end to cover the corners.
            let far = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
                .map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? size.width
            // Solid for the inner 45% of the radius, then soft: at the end that inner part has passed the farthest corner.
            let radius = max(1, far / 0.45 * p)
            RadialGradient(stops: [Gradient.Stop(color: .black, location: 0)]
                               + Ease.softStops.reversed().map { Gradient.Stop(color: $0.color, location: 0.45 + 0.55 * (1 - $0.location)) },
                           center: UnitPoint(x: origin.x / max(size.width, 1), y: origin.y / max(size.height, 1)),
                           startRadius: 0, endRadius: radius)
                .opacity(Ease.smooth(p, 0, 0.2))
                .mask(Ease.topFade)
        case .tint:
            // Nothing sweeps: the whole sea comes up through itself.
            Color.black
                .opacity(Ease.smooth(p, 0.05, 0.95))
                .mask(Ease.topFade)
        }
    }
}

/// The gear in the corner: everything that isn't starting or watching a block.
struct MoreMenu: View {
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let locked = !controller.sessions.isEmpty
        Menu {
            Button("Edit Lists…") { Panels.showMain(.list(controller.selectedList?.id), controller: controller) }
            Button("New List…") { Panels.showNewList(controller: controller) }
            Button("Schedules…") { Panels.showMain(.schedules, controller: controller) }
            Button("Today…") { Panels.showMain(.today, controller: controller) }
            Divider()
            Button("Settings…") { Panels.showMain(.settings, controller: controller) }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            if locked {
                Text("Quit is off while a block runs")
            }
            Button("Quit Seawall") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .disabled(locked)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Lists, schedules, settings")
        .accessibilityLabel("More")
    }
}

/// Curves for `SeaReveal`.
private enum Ease {
    /// 0 to 1 as `x` goes from `a` to `b`, with no corner at either end.
    static func smooth(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The short fade at the water's top edge, which the sea has always had once it is all the way in.
    static var topFade: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Clear to black along a smoothstep, top to bottom.
    static let softStops: [Gradient.Stop] = (0...8).map { i in
        let t = Double(i) / 8
        return Gradient.Stop(color: Color.black.opacity(t * t * (3 - 2 * t)), location: t)
    }
}
