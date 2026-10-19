import SwiftUI

/// Opening at login, and what this copy of Seawall is.
struct SettingsView: View {
    @EnvironmentObject private var controller: BlockController
    @ObservedObject private var login = LoginItem.shared

    static let repository = URL(string: "https://github.com/NikOneZ1/seawall")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Deep.label("General")
                .padding(.top, 12)

            Toggle(isOn: Binding(get: { login.isOn || login.needsApproval }, set: { login.set($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at login")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Seawall waits in the menu bar from the moment you sign in.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if login.needsApproval {
                HStack(alignment: .firstTextBaseline) {
                    Text("It's switched off in System Settings → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    QuietButton(title: "Open Login Items…") { login.openSystemSettings() }
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            Deep.label("About")

            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Seawall")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Version \(Self.version)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Free and open source, under the GPL-3.0.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Link(destination: Self.repository) { Text("Source on GitHub") }
                    .buttonStyle(PillButtonStyle())
                Link(destination: Self.repository.appendingPathComponent("issues")) { Text("Report a problem") }
                    .buttonStyle(PillButtonStyle())
                Spacer()
            }

            QuietButton(title: "Show the welcome again") { Panels.showWelcome(controller: controller) }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, Deep.floor + 14)
        .onAppear { login.refresh() }
    }

    /// "0.1.0 (1)".
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
