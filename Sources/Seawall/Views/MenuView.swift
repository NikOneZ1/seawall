import SeawallCore
import SwiftUI

/// The menu bar panel. Ready to lock it shows the lists and the hold button; while blocks
/// run it shows how long is left.
struct MenuView: View {
    @EnvironmentObject private var controller: BlockController
    /// Setting up one more block while others run.
    @State private var addingBlock = false

    var body: some View {
        let locked = !controller.sessions.isEmpty
        VStack(alignment: .leading, spacing: Space.m) {
            Group {
                if !locked {
                    LockView()
                } else if addingBlock {
                    LockView(back: { addingBlock = false })
                } else {
                    LockedView(onAdd: { addingBlock = true })
                }
            }
            Divider()
                .padding(.horizontal, -Space.l)
            TodayStrip()
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m + 2)
        .padding(.bottom, Space.m)
        .frame(width: 320)
        .onAppear {
            controller.refreshBrowserAccess()
        }
        .background {
            Button("") { Panels.showMain(.settings, controller: controller) }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        .onChange(of: controller.sessions.isEmpty) { addingBlock = false }
    }
}

/// The gear in the corner: everything that isn't starting or watching a block.
struct MoreMenu: View {
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let locked = !controller.sessions.isEmpty
        Menu {
            Button("Edit Lists…") { Panels.showMain(.list(controller.selectedList?.id), controller: controller) }
            Button("New List…") { Panels.showNewList(controller: controller) }
            Button("Schedules…") { Panels.showMain(.schedules, controller: controller) }
            Button("Today…") { Panels.showMain(.today, controller: controller) }
            Divider()
            Button("Settings…") { Panels.showMain(.settings, controller: controller) }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            if locked {
                Text("Quit is off while a block runs")
            }
            Button("Quit Seawall") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .disabled(locked)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Lists, schedules, settings")
        .accessibilityLabel("More")
    }
}
