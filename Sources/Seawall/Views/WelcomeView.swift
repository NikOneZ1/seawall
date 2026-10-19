import SeawallCore
import SwiftUI

/// Shown once, on the first launch: what Seawall does, browser access asked for now rather than
/// in the middle of the first block, and whether to open at login.
struct WelcomeView: View {
    @EnvironmentObject private var controller: BlockController
    @State private var step: Int
    @State private var asking = false
    @State private var openAtLogin = true

    private static let steps = 3

    init(step: Int = 0) {
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Deep.label("Step \(step + 1) of \(Self.steps)")
                .padding(.bottom, 10)

            Group {
                switch step {
                case 0: intro
                case 1: browsers
                default: login
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(PillButtonStyle())
                }
                Spacer()
                Button(step == Self.steps - 1 ? "Done" : "Next") { advance() }
                    .buttonStyle(PillButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, Deep.floor + 20)
        .onAppear {
            controller.refreshBrowserAccess()
            openAtLogin = LoginItem.shared.isOn || !LoginItem.shared.hasBeenChosen
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.leading, -6)
            title("Keep the sites that pull you in closed")
            paragraph("Pick the sites and apps that eat your time, choose how long, and hold the lock for a second. "
                + "They stay closed until then. Leaving early takes a 10-minute wait, so a five-second impulse passes.")
        }
    }

    private var browsers: some View {
        let names = Format.list(controller.installedBrowsers.map(\.name))
        let denied = controller.deniedBrowsers.map(\.name)
        let allGranted = controller.installedBrowsers.allSatisfy { controller.browserAccess[$0.bundleID] == .granted }
        return VStack(alignment: .leading, spacing: 14) {
            title("Let Seawall see your tabs")
            paragraph("During a block, Seawall reads the address of each tab in \(names) and swaps blocked ones for a calm page. "
                + "Without this it can only close the browser. macOS asks once for each; a closed browser opens in the background so it can.")

            if !denied.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Format.list(denied)) access is off. You can turn it on under Automation.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    QuietButton(title: "Open System Settings…") { controller.openAutomationSettings() }
                }
            } else if allGranted {
                Label("Access is on for \(names)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Deep.accent)
            } else {
                Button(asking ? "Waiting for macOS…" : "Allow access") {
                    asking = true
                    Task {
                        await controller.askForBrowserAccess()
                        asking = false
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(asking)
            }
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Open at login?")
            (Text("Seawall lives in the menu bar: the tilted lock \(Image(nsImage: SlabGlyph.open).renderingMode(.template)) ")
                + Text("at the top of your screen. Click it to lock something. Opening at login keeps it there after a restart."))
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.78))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $openAtLogin) {
                Text("Open Seawall when I sign in")
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .toggleStyle(.switch)
            .padding(.top, 4)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .tracking(-0.4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(.white.opacity(0.78))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func advance() {
        guard step == Self.steps - 1 else {
            step += 1
            return
        }
        LoginItem.shared.set(openAtLogin)
        Panels.close("welcome")
    }
}
