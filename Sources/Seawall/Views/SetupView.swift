import SeawallCore
import SwiftUI

/// Reads as a sentence: "Lock [Twitch] [TikTok] for 2 hours", then hold to lock.
struct SetupView: View {
    /// Back to the running blocks; `nil` when nothing is blocked yet.
    var close: (() -> Void)?
    @EnvironmentObject private var controller: BlockController
    @State private var newSite = ""
    @State private var adding = false
    @State private var holding = false
    @FocusState private var siteFieldFocused: Bool
    @ObservedObject private var dive = Dive.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let close {
                QuietButton(title: "‹  Running blocks", action: close)
                    .opacity(sunk)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lock")
                        .font(Self.wordFont)
                    Spacer()
                    QuietButton(title: adding ? "Done" : "+ Add") {
                        adding.toggle()
                        siteFieldFocused = adding
                    }
                    .help("Add a site or an app")
                }
                FlowLayout(spacing: 6) {
                    siteChips
                    Chip(
                        title: "Other browsers",
                        isOn: controller.config.blockOtherBrowsers,
                        locked: controller.otherBrowsersBlockedUntil != nil,
                        help: "Only Safari tabs can be filtered, so other browsers get closed during the block",
                        action: { controller.config.blockOtherBrowsers.toggle() }
                    ) {
                        BrowsersIcon()
                    }
                    appChips
                }
                if adding {
                    addRow
                }
            }
            .opacity(sunk)

            durationRow
                .opacity(sunk)

            deniedNotice
                .opacity(sunk)

            HoldButton(title: startTitle, isEnabled: controller.canStart, onPressing: { pressing in
                holding = pressing
                Water.shared.pressing(pressing)
            }) {
                Water.shared.lock()
                controller.startBlock()
                close?()
            }

            // The fine print shows up while you hold, when it matters, in place of Settings and Quit.
            ZStack(alignment: .leading) {
                Text("Leaving early will take a 10-minute wait.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(holding ? 1 : 0)
                HStack {
                    Spacer()
                    QuietButton(title: "Settings") { Panels.showSettings(controller: controller) }
                    if controller.sessions.isEmpty {
                        QuietButton(title: "Quit") { NSApp.terminate(nil) }
                            .padding(.leading, 10)
                    }
                }
                .opacity(holding ? 0 : 1)
                .allowsHitTesting(!holding)
            }
            .animation(.easeOut(duration: 0.2), value: holding)
            .padding(.top, -8)
        }
    }

    private static let wordFont = Font.system(size: 20, weight: .semibold)

    /// Everything but the hold button fades as the menu sinks.
    private var sunk: Double { 1 - 0.65 * dive.depth }

    // MARK: - What to lock

    private var siteChips: some View {
        ForEach($controller.config.sites) { $site in
            Chip(
                title: SiteRule(site.pattern)?.displayName ?? site.pattern,
                isOn: site.enabled,
                locked: controller.blockedUntil(site: site.pattern) != nil,
                help: site.pattern,
                onRemove: { controller.removeSite(site) },
                action: { site.enabled.toggle() }
            ) {
                SiteIcon(pattern: site.pattern)
            }
        }
    }

    private var appChips: some View {
        ForEach($controller.config.apps) { $app in
            Chip(
                title: app.name,
                isOn: app.enabled,
                locked: controller.blockedUntil(app: app.bundleID) != nil,
                onRemove: { controller.removeApp(app) },
                action: { app.enabled.toggle() }
            ) {
                AppIcon(path: app.path)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Site, e.g. reddit.com", text: $newSite)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($siteFieldFocused)
                .onSubmit(addSite)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.14)) }
            QuietButton(title: "Add app…") { controller.pickApps() }
        }
    }

    // MARK: - For how long

    /// "for 2 hours ⌄ … until 18:00", or "until ⌄" with the day and time underneath.
    private var durationRow: some View {
        let until = controller.config.duration == .untilTime
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    ForEach(BlockDuration.allCases) { duration in
                        if duration == .untilTime { Divider() }
                        Button(duration.title) { controller.config.duration = duration }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(until ? "until" : "for \(controller.config.duration.title)")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(Self.wordFont)
                    .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer()

                if controller.plannedEnd > controller.now {
                    Deep.label(until
                         ? Format.duration(controller.plannedEnd.timeIntervalSince(controller.now))
                         : "until \(Format.clockTime(controller.plannedEnd, relativeTo: controller.now))")
                }
            }
            if until {
                UntilPicker(until: $controller.config.until, now: controller.now)
            }
        }
    }

    // MARK: - Start

    @ViewBuilder
    private var deniedNotice: some View {
        if !controller.config.enabledSites.isEmpty, controller.safariAccess == .denied {
            HStack(alignment: .firstTextBaseline) {
                Text("Safari access is off, so Safari gets closed during blocks.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                QuietButton(title: "Fix…") { controller.openAutomationSettings() }
            }
        }
    }

    private var startTitle: String {
        if controller.config.isEmpty { return "Pick something to lock" }
        guard controller.plannedEnd > controller.now else { return "That time has passed" }
        return "Hold to lock"
    }

    private func addSite() {
        if controller.addSite(newSite) {
            newSite = ""
            siteFieldFocused = true
        }
    }
}

/// "Tomorrow ⌄ at 15 ⌄ : 00 ⌄", as quiet text menus that keep the sentence going.
private struct UntilPicker: View {
    @Binding var until: UntilTime
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            menu(Format.day(until.day, from: now), values: Array(UntilTime.days), label: { Format.day($0, from: now) }) {
                until.day = $0
            }
            Text("at")
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            menu(Self.twoDigits(until.hour), values: Array(0..<24), label: Self.twoDigits) { until.hour = $0 }
            Text(":")
                .foregroundStyle(.secondary)
            menu(Self.twoDigits(until.minute), values: Array(stride(from: 0, to: 60, by: UntilTime.minuteStep)),
                 label: Self.twoDigits) { until.minute = $0 }
        }
        .font(.system(size: 12.5, weight: .medium))
    }

    private func menu(_ title: String, values: [Int], label: @escaping (Int) -> String, set: @escaping (Int) -> Void) -> some View {
        Menu(title) {
            ForEach(values, id: \.self) { value in
                Button(label(value)) { set(value) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private static func twoDigits(_ n: Int) -> String {
        String(format: "%02d", n)
    }
}
