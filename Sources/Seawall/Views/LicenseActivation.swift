import SwiftUI

/// Buying or activating Seawall: the price, Buy, a key field with Activate, and how it went.
///
/// Only values and closures come in, so it can be drawn in any state (empty, key typed, working,
/// failed, activated) without the real license, the Keychain or the network. The welcome's
/// "Activate Seawall" step and Settings, License bind it to `WelcomeLicense` and `LicenseModel`.
///
/// One prominent button at a time: Buy while the key field is empty, Activate once a key is in it.
struct LicenseActivationForm: View {
    enum Layout {
        /// One rounded card, like the welcome's other cards: the offer above, the key below.
        case card
        /// Separate rows, for a grouped `Form` section.
        case formRows
    }

    let layout: Layout
    @Binding var key: String
    let price: String
    let buyURL: URL
    let isWorking: Bool
    /// The last failure's wording (`LicenseFailure.message`), if any.
    let failure: String?
    let isLicensed: Bool
    /// Under "Seawall is activated on this Mac." when activated.
    let successDetail: String?
    let buy: () -> Void
    let activate: () -> Void

    init(layout: Layout, key: Binding<String>, price: String, buyURL: URL, isWorking: Bool,
         failure: String?, isLicensed: Bool, successDetail: String? = nil,
         buy: @escaping () -> Void, activate: @escaping () -> Void) {
        self.layout = layout
        self._key = key
        self.price = price
        self.buyURL = buyURL
        self.isWorking = isWorking
        self.failure = failure
        self.isLicensed = isLicensed
        self.successDetail = successDetail
        self.buy = buy
        self.activate = activate
    }

    var body: some View {
        switch layout {
        case .card: card
        case .formRows: rows
        }
    }

    private var hasTypedKey: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var terms: String {
        "For up to 3 Macs. Not for you? Full refund within 14 days, no questions asked."
    }

    // MARK: - Layouts

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLicensed {
                success
                    .padding(Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text(price)
                            .font(.title2.weight(.semibold))
                        Text("once, no subscription")
                            .foregroundStyle(.secondary)
                    }
                    Text(terms)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    buyButton
                        .controlSize(.large)
                        .padding(.top, Space.xs)
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Already bought it?")
                        .font(.headline)
                    keyRow
                        .textFieldStyle(.roundedBorder)
                    failureLine
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Each view here is its own row in the surrounding `Form` section.
    @ViewBuilder private var rows: some View {
        if isLicensed {
            success
        } else {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seawall isn't activated on this Mac yet.")
                    Text("\(price) once, for up to 3 Macs. Full refund within 14 days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                buyButton
            }
            keyRow
            failureLine
        }
    }

    // MARK: - Parts

    private var buyButton: some View {
        Button("Buy for \(price)", action: buy)
            .prominent(!hasTypedKey)
            .help("Opens \(buyURL.absoluteString) in your browser. The key arrives by email.")
    }

    private var keyRow: some View {
        HStack(spacing: Space.s) {
            TextField("License key", text: $key, prompt: Text("Paste the key from your purchase email"))
                .autocorrectionDisabled()
                .onSubmit(activate)
                .disabled(isWorking)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Activating")
            }
            Button("Activate", action: activate)
                .prominent(hasTypedKey)
                .disabled(isWorking || !hasTypedKey)
        }
    }

    @ViewBuilder private var failureLine: some View {
        if let failure {
            Label {
                Text(failure)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline)
        }
    }

    private var success: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.sea)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Seawall is activated on this Mac.")
                    .font(.headline)
                if let successDetail {
                    Text(successDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The one filled button, or a plain bordered one.
    @ViewBuilder func prominent(_ isProminent: Bool) -> some View {
        if isProminent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
