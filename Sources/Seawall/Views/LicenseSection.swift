import SeawallCore
import SwiftUI

/// Settings → License: a key field while unlicensed, the status and Deactivate once licensed.
/// Nothing here touches a running block.
struct LicenseSection: View {
    @ObservedObject private var license = LicenseModel.shared
    @State private var key = ""
    @State private var confirmingDeactivate = false

    var body: some View {
        Section {
            switch license.state {
            case .unlicensed:
                unlicensed
            case .licensed(let info):
                licensed(info)
            case .grace(let info, let problem, let until):
                licensed(info)
                Text("seawall.work says \(problem.wording). New blocks keep starting at least until \(until.formatted(date: .long, time: .omitted)), and running blocks are never affected. If that's a mistake, email \(LicenseModel.supportEmail).")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if let failure = license.failure {
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        } header: {
            Text("License")
        }
    }

    @ViewBuilder private var unlicensed: some View {
        Text("Seawall isn't activated on this Mac yet. Starting a block needs a license key: \(LicenseModel.price) once, for up to 3 Macs.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
                .disabled(license.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        HStack {
            Link("Buy Seawall for \(LicenseModel.price)", destination: LicenseModel.buyURL)
            Spacer()
            Text("Works on up to 3 Macs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func licensed(_ info: LicenseInfo) -> some View {
        HStack {
            Label(info.summary, systemImage: "checkmark.seal.fill")
                .labelStyle(SeaIconLabelStyle())
            Spacer()
            if license.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Deactivate This Mac…") { confirmingDeactivate = true }
                .disabled(license.isWorking)
        }
        .confirmationDialog("Deactivate Seawall on this Mac?", isPresented: $confirmingDeactivate) {
            Button("Deactivate", role: .destructive) {
                Task { await license.deactivate() }
            }
        } message: {
            Text("This frees one of your Macs for the key. Blocks keep running, and you can activate again with the same key.")
        }
        if license.offersLocalRemoval {
            HStack {
                Text("Remove it from this Mac anyway? Its spot stays taken until you deactivate later or email \(LicenseModel.supportEmail).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove Anyway") { license.removeFromThisMac() }
            }
        }
    }

    private func activate() {
        let typed = key
        Task {
            await license.activate(typed)
            if license.state.isLicensed { key = "" }
        }
    }
}

/// The label's icon in Seawall's teal, its text in the usual colour.
private struct SeaIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon
                .foregroundStyle(Color.sea)
            configuration.title
        }
    }
}
