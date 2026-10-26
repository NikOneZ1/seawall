import SeawallCore
import SwiftUI

/// Settings, in the Seawall window: few of them, short labels, standard controls.
struct SettingsPane: View {
    @EnvironmentObject private var controller: BlockController
    @ObservedObject private var login = LoginItem.shared
    @ObservedObject private var preferences = Preferences.shared

    static let repository = URL(string: "https://github.com/NikOneZ1/seawall")!

    var body: some View {
        Form {
            Section {
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
                Text("The default for new blocks. You can change it for one block, right under Hold to lock.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Blocks")
            }

            Section("Look") {
                Picker("Show the sea", selection: $preferences.sea) {
                    ForEach(SeaMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(seaDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Hold to lock animation", selection: $preferences.holdAnimation) {
                    ForEach(HoldAnimation.allCases) { style in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(style.title)
                            Text(style.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("To preview one, hold Hold to lock and let go before it takes: nothing is locked. The sea needs \"While locked\" above.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Toggle("Notify me 5 minutes before a block ends", isOn: $preferences.notifications)
                Toggle("Play a soft sound when a block starts and ends", isOn: $preferences.sounds)
            }

            Section("General") {
                Picker("Menu bar shows", selection: $preferences.showsTimeLeft) {
                    Text("When it ends").tag(false)
                    Text("Time left").tag(true)
                }
                Toggle("Open Seawall at login", isOn: Binding(get: { login.isOn || login.needsApproval }, set: { login.set($0) }))
                if login.needsApproval {
                    HStack {
                        Text("It's switched off in System Settings, Login Items.")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items…") { login.openSystemSettings() }
                    }
                }
                Toggle("Open the menu from anywhere with \(MenuShortcut.title)", isOn: $preferences.shortcut)
                Button("Show the Welcome Again") { Panels.showWelcome(controller: controller) }
            }

            Section("About") {
                HStack(spacing: Space.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Seawall")
                            .font(.headline)
                        Text("Version \(Self.version)")
                            .foregroundStyle(.secondary)
                        Text("Free and open source, under the GPL-3.0.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Link("Source on GitHub", destination: Self.repository)
                    Spacer()
                    Link("Report a Problem", destination: Self.repository.appendingPathComponent("issues"))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { login.refresh() }
    }

    private var seaDetail: String {
        switch preferences.sea {
        case .always: "The menu is always underwater, like the block page."
        case .whileLocked: "The menu is clear glass. Water rises as you hold to lock and stays while you're locked."
        case .never: "A plain menu that follows light and dark mode. The sea stays on the block page."
        }
    }

    /// "0.1.0 (1)".
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
