import SeawallCore
import SwiftUI

/// Starting a list when a Focus turns on. macOS doesn't let an app like Seawall join Focus
/// filters, so a Shortcuts automation opens a lock link instead; this walks through it.
struct FocusSetup: View {
    let list: BlockList
    @Environment(\.dismiss) private var dismiss
    @State private var untilTime = true
    @State private var until = TimeOfDay(hour: 18, minute: 0)
    @State private var hours = 2
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start \(list.name) with a Focus")
                    .font(.title2.weight(.semibold))
                Text("A Shortcuts automation opens a Seawall link when your Focus turns on. It takes a minute, once.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step(1, "Open Shortcuts, choose Automation and click +.") {
                Button("Open Shortcuts") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
            step(2, "Pick your Focus, then When Turning On, and Run Immediately.") { EmptyView() }
            step(3, "Add the Open URLs action and paste this link:") {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        Picker("Lock", selection: $untilTime) {
                            Text("Until").tag(true)
                            Text("For").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if untilTime {
                            TimeField(time: $until)
                        } else {
                            Stepper("\(hours) h", value: $hours, in: 1...12)
                                .fixedSize()
                        }
                    }
                    HStack(spacing: Space.s) {
                        Text(link)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        }
                    }
                }
            }

            Text("The same link works from Raycast, Alfred or Terminal. A link never locks for more than 12 hours.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var link: String {
        let name = list.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? list.name
        return untilTime ? "seawall://lock?list=\(name)&until=\(until.text)" : "seawall://lock?list=\(name)&for=\(hours)h"
    }

    private func step(_ number: Int, _ text: String, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.sea))
            VStack(alignment: .leading, spacing: Space.s) {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }
}
