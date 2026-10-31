import SeawallCore
import SwiftUI

/// Settings, in the Seawall window: few of them, short labels, standard controls.
struct SettingsPane: View {
    @EnvironmentObject private var controller: BlockController
    @ObservedObject private var login = LoginItem.shared
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var crashes = CrashReporter.shared

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
                Picker("Blocked page", selection: $preferences.blockedPage) {
                    ForEach(BlockedPageChoice.allCases) { Text($0.title).tag($0) }
                }
                Text(preferences.blockedPage.detail + " It's what a blocked tab shows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Blocks")
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

            Section("Feedback") {
                HStack {
                    Text("Opens an email to \(FeedbackMail.address) with the versions and a recent log, cleaned of sites and lists.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Send Feedback…") { Diagnostics.sendFeedback(controller: controller) }
                }
                Toggle("Offer to send crash reports", isOn: $preferences.crashReports)
                Text("After a crash, Seawall asks before emailing a short report: versions and where its code stopped, never your sites or lists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if preferences.crashReports, !crashes.reports.isEmpty {
                    HStack {
                        Text(Format.count(crashes.reports.count, "saved report", "saved reports"))
                        Spacer()
                        Button("Show in Finder") { crashes.showInFinder() }
                        Button("Delete") { crashes.deleteAll() }
                    }
                }
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
        .onAppear {
            login.refresh()
            crashes.refresh()
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
