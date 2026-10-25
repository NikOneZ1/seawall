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
        .background { SeaBackground(level: level, rising: !onWater) }
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

    var body: some View {
        GeometryReader { proxy in
            if level > 0 {
                // A hold let go early drains quickly; a block ending fades the sea out slowly.
                Tide(level: level, rising: rising, height: proxy.size.height)
                    .transition(.asymmetric(insertion: rising ? AnyTransition.identity : .opacity,
                                            removal: AnyTransition.opacity.animation(.easeOut(duration: rising ? 0.25 : 0.6))))
            }
        }
        .animation(.easeInOut(duration: 0.6), value: level > 0)
    }
}

/// The water itself, masked to the height it has reached. The height lives here rather than
/// in the level passed in: a view that has just appeared has nothing to animate from, so the
/// water stood at full height from the first frame instead of rising.
private struct Tide: View {
    let level: Double
    let rising: Bool
    let height: CGFloat
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WaterSurface()
            .mask(alignment: .bottom) {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: height * shown + (shown < 1 ? 14 : 0))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .onAppear {
                if rising, !reduceMotion {
                    withAnimation(.linear(duration: HoldButton.holdTime)) { shown = level }
                } else {
                    shown = level
                }
            }
            .onChange(of: level) { _, new in
                withAnimation(.easeOut(duration: 0.3)) { shown = new }
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
