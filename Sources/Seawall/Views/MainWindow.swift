import SeawallCore
import SwiftUI

/// The Seawall window: your lists in a sidebar, then Schedules, Today and Settings. Everything
/// that needs more room than the menu lives here.
struct MainWindowView: View {
    @ObservedObject var model: MainWindowModel
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Lists") {
                    ForEach(controller.config.lists) { list in
                        Label {
                            Text(list.name)
                        } icon: {
                            ListBadge(symbol: list.symbol, color: list.color, size: 18)
                        }
                        .tag(MainSection.list(list.id))
                        .contextMenu {
                            Button("Duplicate") { model.selection = .list(controller.duplicate(list)) }
                            Button("Delete…", role: .destructive) {
                                model.deleting = list.id
                                model.selection = .list(list.id)
                            }
                            .disabled(controller.config.lists.count < 2)
                        }
                    }
                    // Not "New List": that's what a new list is called, right above.
                    Button {
                        let id = controller.addList()
                        model.focusName = id
                        model.selection = .list(id)
                    } label: {
                        Label("Add List", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Section("Seawall") {
                    Label("Schedules", systemImage: "calendar").tag(MainSection.schedules)
                    Label("Today", systemImage: "chart.bar.fill").tag(MainSection.today)
                    Label("Settings", systemImage: "gearshape").tag(MainSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch model.selection {
                case .list(let id?):
                    if controller.config.list(id) != nil {
                        // A list of its own each time, so it opens at the top rather than where the last one was scrolled.
                        ListEditor(listID: id, model: model, onDeleted: { model.selection = .list(controller.config.lists.first?.id) })
                            .id(id)
                    } else {
                        ContentUnavailableView("No List", systemImage: "list.bullet", description: Text("Pick a list on the left."))
                    }
                case .schedules:
                    SchedulesPane()
                case .today:
                    TodayPane()
                case .settings:
                    SettingsPane()
                default:
                    ContentUnavailableView("Seawall", systemImage: "lock", description: Text("Pick a list on the left."))
                }
            }
            .frame(minWidth: 460)
        }
        .onChange(of: controller.config.lists.map(\.id)) {
            if case .list(let id?) = model.selection, controller.config.list(id) == nil {
                model.selection = .list(controller.config.lists.first?.id)
            }
        }
        .background {
            // ⌘, from anywhere in the window.
            Button("") { model.selection = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
    }
}
