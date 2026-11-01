import SeawallCore
import SwiftUI

/// "Activate Seawall": shown when a block couldn't start because this Mac has no license.
/// One calm screen: a key field, Activate, and a Buy link. Closes itself once activated.
struct ActivateView: View {
    @ObservedObject private var license = LicenseModel.shared
    let reason: String?
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activate Seawall")
                        .font(.title2.weight(.semibold))
                    Text("\(LicenseModel.price) once, for up to 3 Macs.")
                        .foregroundStyle(.secondary)
                }
            }
            Text(reason ?? "Starting a block needs a license key. Paste the key from your purchase email, or buy one at seawall.work.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Your lists and schedules are all still here. A block that's already running is never affected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                TextField("License key", text: $key, prompt: Text("Paste your key"))
                    .autocorrectionDisabled()
                    .onSubmit(activate)
                    .disabled(license.isWorking)
                if license.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Activate", action: activate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(license.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let failure = license.failure {
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link("Buy Seawall for \(LicenseModel.price)", destination: LicenseModel.buyURL)
                Spacer()
                Button("Not Now") { Panels.close("activate") }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func activate() {
        let typed = key
        Task {
            await license.activate(typed)
            if license.state.isLicensed {
                key = ""
                Panels.close("activate")
            }
        }
    }
}
