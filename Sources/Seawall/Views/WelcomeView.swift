import SeawallCore
import SwiftUI

/// The first launch: pick what pulls you in (that becomes your first list), let Seawall see
/// browser tabs, then find the lock in the menu bar. Doing beats reading.
struct WelcomeView: View {
    @EnvironmentObject private var controller: BlockController
    @State private var step = 0
    @State private var picked: Set<String> = []
    @State private var asking = false
    @State private var openAtLogin = true

    private static let steps = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                WaterBackground()
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .padding(.leading, 26)
                    .padding(.bottom, 14)
            }
            .frame(height: 96)

            Group {
                switch step {
                case 0: pick
                case 1: browsers
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, Space.l)

            HStack(spacing: Space.s) {
                HStack(spacing: 6) {
                    ForEach(0..<Self.steps, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(step + 1) of \(Self.steps)")
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Button(step == Self.steps - 1 ? "Start Using Seawall" : "Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 0 && picked.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, Space.l)
        }
        .frame(width: 560, height: 640)
        .onAppear {
            controller.refreshBrowserAccess()
            openAtLogin = LoginItem.shared.isOn || !LoginItem.shared.hasBeenChosen
            InstalledApps.shared.load()
            if let list = controller.config.lists.first {
                picked = Set(list.groups.filter(\.isOn).map { "group:\($0.value.rawValue)" }
                    + list.sites.filter(\.isOn).map { "site:\($0.value)" }
                    + list.apps.filter(\.isOn).map { "app:\($0.bundleID)" })
            }
        }
    }

    // MARK: - 1. What pulls you in

    private var pick: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("What pulls you in?")
                .font(.title.weight(.semibold))
            Text("Tap everything that eats your time. It becomes your first list; you can change it any time.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                ForEach(Self.sites, id: \.self) { site in
                    tile("site:\(site)", SiteRule(site)?.displayName ?? site) { SiteIcon(pattern: site, size: 22) }
                }
                ForEach(Self.groups, id: \.self) { group in
                    tile("group:\(group.rawValue)", group == .games ? "All games" : group.title) { GroupIcon(group: group, size: 22) }
                }
                ForEach(distractingApps) { app in
                    tile("app:\(app.bundleID)", app.name) { AppIcon(path: app.path, size: 22) }
                }
            }
        }
    }

    private func tile(_ id: String, _ title: String, @ViewBuilder icon: () -> some View) -> some View {
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
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private static let groups: [SiteGroup] = [.social, .video, .games, .news, .shopping]
    private static let sites = ["youtube.com/shorts", "tiktok.com", "instagram.com", "x.com", "reddit.com", "twitch.tv",
                                "youtube.com", "netflix.com", "facebook.com", "news.ycombinator.com"]

    /// Apps people often lock, the ones installed here.
    private var distractingApps: [ListApp] {
        let ids = ["com.valvesoftware.steam", "com.hnc.Discord", "ru.keepcoder.Telegram", "com.tinyspeck.slackmacgap",
                   "net.whatsapp.WhatsApp", "com.epicgames.EpicGamesLauncher", "com.spotify.client"]
        return ids.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap(InstalledApps.item(at:))
        }
    }

    // MARK: - 2. Browsers

    private var browsers: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Let Seawall see your tabs")
                .font(.title.weight(.semibold))
            Text("During a block Seawall reads each tab's address and swaps blocked ones for a calm page. Without access it can only close the browser. macOS asks once per browser.")
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
                Button(asking ? "Waiting for macOS…" : "Allow Access") {
                    asking = true
                    Task {
                        await controller.askForBrowserAccess()
                        asking = false
                    }
                }
                .disabled(asking)
                Text("A closed browser opens in the background so macOS can ask.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 3. Done

    private var done: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Seawall lives in your menu bar")
                .font(.title.weight(.semibold))
            HStack(spacing: Space.l) {
                Spacer()
                Text("Wi-Fi")
                Image(nsImage: SlabGlyph.open)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.sea.opacity(0.25)))
                    .overlay(alignment: .bottom) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.sea)
                            .offset(y: 30)
                    }
                Text("Tue 14:05")
            }
            .font(.headline)
            .padding(.horizontal, Space.m)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.bottom, 36)
            Text("Click the tilted lock to start a block: pick a list, pick how long, and hold the button for a second. Leaving early takes a wait, so a five-second impulse passes.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Open Seawall when I log in, so it's always there", isOn: $openAtLogin)
                .toggleStyle(.switch)
                .padding(.top, Space.s)
        }
    }

    private func advance() {
        switch step {
        case 0:
            savePicks()
            step = 1
        case 1:
            step = 2
        default:
            LoginItem.shared.set(openAtLogin)
            Panels.close("welcome")
        }
    }

    /// The picks go into the first list. Only what's on this screen changes: picked is added or
    /// ticked, unpicked is unticked, never removed. Seen again from Settings, the welcome mustn't
    /// throw away a list someone has built since.
    private func savePicks() {
        guard let first = controller.config.lists.first else { return }
        let apps = distractingApps
        controller.mutateList(first.id) { list in
            for group in Self.groups {
                list.groups.set(on: picked.contains("group:\(group.rawValue)"), where: { $0.value == group }) { Toggled(group) }
            }
            for site in Self.sites {
                list.sites.set(on: picked.contains("site:\(site)"), where: { $0.value == site }) { Toggled(site) }
            }
            for app in apps {
                list.apps.set(on: picked.contains("app:\(app.bundleID)"), where: { $0.bundleID == app.bundleID }) { app }
            }
        }
        controller.config.next.listID = first.id
    }
}

private extension Array where Element: Switchable {
    /// Ticks or unticks the matching item, adding it only when it's picked and missing.
    mutating func set(on: Bool, where matches: (Element) -> Bool, make: () -> Element) {
        if let index = firstIndex(where: matches) {
            self[index].isOn = on
        } else if on {
            append(make())
        }
    }
}

/// Something in a list that can be ticked.
private protocol Switchable {
    var isOn: Bool { get set }
}

extension Toggled: Switchable {}
extension ListApp: Switchable {}
