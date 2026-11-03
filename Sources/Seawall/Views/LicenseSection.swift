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
            #if DEBUG
            if license.isDevLicense {
                Label("Dev license: this debug build starts blocks without a key (SEAWALL_DEV_LICENSE=1). Release builds have no such switch.",
                      systemImage: "hammer.fill")
                    .labelStyle(SeaIconLabelStyle())
                    .foregroundStyle(.orange)
            }
            #endif
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
            // While unlicensed, the activation form shows its own failure line.
            if let failure = license.failure, license.state != .unlicensed {
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        } header: {
            Text("License")
        }
    }

    private var unlicensed: some View {
        LicenseActivationForm(layout: .formRows, key: $key, price: LicenseModel.price,
                              buyURL: LicenseModel.buyURL, isWorking: license.isWorking,
                              failure: license.failure?.message, isLicensed: false,
                              buy: { NSWorkspace.shared.open(LicenseModel.buyURL) },
                              activate: activate)
    }

    @ViewBuilder private func licensed(_ info: LicenseInfo) -> some View {
        LicensedRow(summary: info.summary, isWorking: license.isWorking) { confirmingDeactivate = true }
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

/// "Licensed on this Mac · 1 of 3 Macs" and Deactivate. Values and closures only, so
/// `LicenseShots` can draw it.
struct LicensedRow: View {
    let summary: String
    let isWorking: Bool
    let deactivate: () -> Void

    var body: some View {
        HStack {
            Label(summary, systemImage: "checkmark.seal.fill")
                .labelStyle(SeaIconLabelStyle())
            Spacer()
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Deactivate This Mac…", action: deactivate)
                .disabled(isWorking)
        }
    }
}
