import SeawallCore
import SwiftUI

/// The first launch, from opening Seawall to a running block in under a minute: pick what pulls
/// you in (that goes into a list), let Seawall see browser tabs, choose how leaving early works,
/// activate Seawall (when the build has licensing), then press and hold to start a 1-hour
/// Flexible first block, or leave it for later. Each thing macOS will ask is said on screen
/// before it asks. Doing beats reading.
struct WelcomeView: View {
    @EnvironmentObject private var controller: BlockController
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var license = WelcomeLicense.shared
    @State private var key = ""
    @State private var hasKey = false
    @State private var step = Welcome.Step.pick
    /// Tiles that were on when the welcome opened (or last saved), and the ones ticked now.
    /// Only the difference is written to the list.
    @State private var saved: Set<String> = []
    @State private var picked: Set<String> = []
    /// Apps people often lock, the ones installed here.
    @State private var apps: [ListApp] = []
    /// The list the picks go into and the first block locks: the menu's list, or the first one.
    @State private var listID: UUID?
    @State private var asking = false
    @State private var openAtLogin = true
    /// macOS hasn't asked about notifications yet; it will when the block starts.
    @State private var notificationsPending = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.primary.opacity(0.04)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .padding(.leading, 26)
                    .padding(.bottom, 14)
            }
            .frame(height: 96)

            Group {
                switch step {
                case .pick: pick
                case .browsers: browsers
                case .leaving: leaving
                case .license: licenseStep
                case .start: start
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, Space.l)

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, Space.l)
        }
        .frame(width: 560, height: 640)
        .onAppear {
            controller.refreshBrowserAccess()
            openAtLogin = LoginItem.shared.isOn || !LoginItem.shared.hasBeenChosen
            InstalledApps.shared.load()
            apps = Starter.appBundleIDs.compactMap { id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap(InstalledApps.item(at:))
            }
            let list = controller.selectedList
            listID = list?.id
            if let list {
                saved = Starter.picked(in: list, from: Starter.items(apps: apps))
                picked = saved
            }
        }
        .task {
            notificationsPending = await Notifier.shared.willAsk()
        }
    }

    private var items: [StarterItem] { Starter.items(apps: apps) }

    private var shownSteps: [Welcome.Step] { Welcome.Step.shown(showsLicense: license.isAvailable) }

    private var list: BlockList? { controller.config.list(listID) }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: 6) {
                ForEach(shownSteps, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \((shownSteps.firstIndex(of: step) ?? 0) + 1) of \(shownSteps.count)")
            Spacer()
            if let previous = step.previous(showsLicense: license.isAvailable) {
                Button("Back") { step = previous }
            }
            if step.isLast {
                Button("Not Now") { finish(starting: false) }
                    .help("Close the welcome without starting a block. The lock in the menu bar starts one any time.")
                // Press and hold, like the menu: a first block never starts from a stray click.
                HoldButton(title: "Hold to lock for 1 hour", isEnabled: canStartFirstBlock) { finish(starting: true) }
                    .frame(width: 230)
            } else if step == .license, !license.isLicensed {
                Button("Continue Without a Key") { advance() }
                    .help("Setup works without a key. Starting a block needs one.")
            } else {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .pick && pickedNothing)
            }
        }
    }

    // MARK: - 1. What pulls you in

    private var pick: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Welcome to Seawall")
                .font(.title.weight(.semibold))
            Text("Seawall locks the sites and apps that eat your time, for as long as you choose. No changing your mind five seconds later.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap what pulls you in. It goes into your list \(list?.name ?? "Distractions"), and you can change it any time.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                ForEach(items) { item in
                    tile(item)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: StarterItem) -> some View {
        switch item.kind {
        case .sites(let patterns):
            let first = patterns.first ?? ""
            tile(item.id, SiteRule(first)?.displayName ?? first, help: patterns.joined(separator: " and ")) {
                SiteIcon(pattern: first, size: 22)
            }
        case .group(let group):
            tile(item.id, group == .games ? "All games" : group.title, help: group.summary) {
                GroupIcon(group: group, size: 22)
            }
        case .app(let app):
            tile(item.id, app.name, help: app.name) { AppIcon(path: app.path, size: 22) }
        }
    }

    private func tile(_ id: String, _ title: String, help: String, @ViewBuilder icon: () -> some View) -> some View {
        let on = picked.contains(id)
        return Button {
            if on { picked.remove(id) } else { picked.insert(id) }
        } label: {
            HStack(spacing: 7) {
                icon()
                    .overlay(alignment: .topTrailing) {
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white, Color.sea)
                                .offset(x: 5, y: -5)
                        }
                    }
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color.sea.opacity(0.15) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Color.sea : Color.primary.opacity(0.08)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Nothing ticked here and nothing else in the list either: there'd be nothing to lock.
    private var pickedNothing: Bool {
        guard let list else { return true }
        return Starter.applying(from: saved, to: picked, offered: items, to: list).isEmpty(otherBrowsersInstalled: false)
    }

    // MARK: - 2. Browsers

    private var browsers: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Let Seawall see your tabs")
                .font(.title.weight(.semibold))
            Text("During a block Seawall reads each tab's address and swaps blocked ones for a calm page. Nothing leaves your Mac. Without access it can only close that browser while a block runs.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(controller.installedBrowsers.enumerated()), id: \.element.bundleID) { index, browser in
                    if index > 0 { Divider() }
                    HStack(spacing: Space.s) {
                        AppIcon(bundleID: browser.bundleID, size: 22)
                        Text(browser.name)
                        Spacer()
                        switch controller.browserAccess[browser.bundleID] {
                        case .granted:
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .denied:
                            Button("Turn On in System Settings…") { controller.openAutomationSettings() }
                        default:
                            Text("Not asked yet")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .frame(height: 40)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            if controller.installedBrowsers.contains(where: { controller.browserAccess[$0.bundleID] != .granted && controller.browserAccess[$0.bundleID] != .denied }) {
                Text("Next, macOS asks \u{201C}Seawall wants to control …\u{201D} once for each browser. Choose Allow. A closed browser opens in the background so macOS can ask.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(asking ? "Waiting for macOS…" : "Allow Access") {
                    asking = true
                    Task {
                        await controller.askForBrowserAccess()
                        asking = false
                    }
                }
                .disabled(asking)
            }
            if !controller.deniedBrowsers.isEmpty {
                Text("Said Don't Allow? That's fine: the browser is closed during blocks instead. You can turn access on any time in System Settings, Privacy & Security, Automation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 3. Leaving early

    private var leaving: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("How hard is leaving early?")
                .font(.title.weight(.semibold))
            Text("A block can be left before its time, just not on a whim. After the wait you get 2 minutes to end it; do nothing and it keeps going.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Leaving early", selection: $preferences.earlyExit) {
                ForEach(EarlyExit.allCases) { level in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(level.name)
                        Text(level.detail.prefix(1).uppercased() + level.detail.dropFirst())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text("This is the default for new blocks. Change it later in Settings, or for one block right under Hold to lock. Your first block, at the end of this setup, is Flexible, so trying Seawall never traps you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 4. Activate (only when this build has licensing)

    private var licenseStep: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Activate Seawall")
                .font(.title.weight(.semibold))
            if license.isLicensed {
                Label("Seawall is activated on this Mac.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.sea)
                Text("Next, start your first block.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Seawall is \(WelcomeLicense.price), once, for up to 3 Macs. Not for you? Get a refund within 14 days, no questions asked.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your lists are saved either way. Starting a block needs a license key.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s) {
                    Button("Buy for \(WelcomeLicense.price)") { NSWorkspace.shared.open(WelcomeLicense.buyURL) }
                        .buttonStyle(.borderedProminent)
                        .help(WelcomeLicense.buyURL.absoluteString)
                    Button("I already have a key") { hasKey = true }
                        .disabled(hasKey)
                }
                if hasKey {
                    HStack(spacing: Space.s) {
                        TextField("License key", text: $key, prompt: Text("Paste the key from your purchase email"))
                            .autocorrectionDisabled()
                            .onSubmit(activate)
                            .disabled(license.isWorking)
                        if license.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Activate", action: activate)
                            .disabled(license.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let failure = license.failure {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func activate() {
        let typed = key
        Task {
            await license.activate(typed)
            if license.isLicensed { key = "" }
        }
    }

    // MARK: - 5. Start

    private var start: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(controller.sessions.isEmpty ? "Start your first block" : "Start another block")
                .font(.title.weight(.semibold))
            Text("Seawall lives in your menu bar. Click the tilted lock any time to start a block, see the time left or edit your lists.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.l) {
                Spacer()
                Text("Wi-Fi")
                Image(nsImage: SlabGlyph.open)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.sea.opacity(0.25)))
                Text("Tue 14:05")
            }
            .font(.headline)
            .padding(.horizontal, Space.m)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .accessibilityHidden(true)

            if let list {
                blockCard(list)
            }

            Toggle("Open Seawall when I log in, so it's always there", isOn: $openAtLogin)
                .toggleStyle(.switch)
            Text(askNotice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the block will lock, for how long, and how it can be left.
    private func blockCard(_ list: BlockList) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ListBadge(symbol: list.symbol, color: list.color, size: 22)
                Text(list.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                Text(Welcome.firstBlockLength.short)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text(blockSummary(list))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(Welcome.firstBlockStrictness.name) · \(Welcome.firstBlockStrictness.detail)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var firstBlockEnd: Date { Welcome.firstBlockLength.end(from: controller.now) }

    private func blockSummary(_ list: BlockList) -> String {
        guard !list.isEmpty(otherBrowsersInstalled: controller.otherBrowsersInstalled) else {
            return "\(list.name) is empty. Go back and tick something to lock."
        }
        let what = list.summary(otherBrowsersInstalled: controller.otherBrowsersInstalled)
        var summary = "\(what), until \(Format.clockTime(firstBlockEnd, relativeTo: controller.now))"
        if license.isAvailable, !license.isLicensed {
            summary += ". Starting a block needs a license key: go Back to activate, or choose Not Now."
        }
        return summary
    }

    /// Something to lock and, when this build has licensing, a license.
    private var canStartFirstBlock: Bool {
        guard let list, !list.isEmpty(otherBrowsersInstalled: controller.otherBrowsersInstalled) else { return false }
        return !license.isAvailable || license.isLicensed
    }

    /// What macOS may say once the block starts, so it's no surprise.
    private var askNotice: String {
        var notice = "When a block starts, macOS may say Seawall added a background item: that's what reopens Seawall if it's quit during a block."
        if notificationsPending {
            notice += " It also asks once about notifications, for a note 5 minutes before a block ends."
        }
        return notice
    }

    // MARK: - Moving on

    private func advance() {
        if step == .pick { savePicks() }
        if let next = step.next(showsLicense: license.isAvailable) { step = next }
    }

    /// Starting goes through the menu's own path (so the same checks apply), as a 1-hour Flexible
    /// block. Flexible is a one-off for this block; the default from step 3 stays for later ones.
    private func finish(starting: Bool) {
        LoginItem.shared.set(openAtLogin)
        let running = controller.sessions.count
        if starting, let listID {
            controller.config.next.listID = listID
            controller.config.next.length = Welcome.firstBlockLength
            controller.config.next.breaks = false
            controller.strictness = Welcome.firstBlockStrictness
            controller.startBlock()
        }
        Panels.close("welcome")
        // Open the menu on the block that just started, so it's clear it's running.
        if controller.sessions.count > running {
            DispatchQueue.main.async { MenuShortcut.openMenu() }
        }
    }

    /// Only what changed on this screen goes into the list: ticked is added or switched on,
    /// unticked is switched off, never removed, and the rest stays as it is. Seen again from
    /// Settings, the welcome mustn't throw away a list someone has built since.
    private func savePicks() {
        guard let id = list?.id else { return }
        let items = self.items, before = saved, after = picked
        controller.mutateList(id) { Starter.apply(from: before, to: after, offered: items, to: &$0) }
        controller.config.next.listID = id
        saved = after
    }
}
