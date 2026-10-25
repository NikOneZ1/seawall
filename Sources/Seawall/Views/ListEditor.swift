import SeawallCore
import SwiftUI

/// One list, edited in the Seawall window: its name and look, what it blocks (ticked is
/// blocked), when it starts on its own, and how a Focus can start it.
struct ListEditor: View {
    let listID: UUID
    @ObservedObject var model: MainWindowModel
    let onDeleted: () -> Void
    @EnvironmentObject private var controller: BlockController
    @State private var toast: Toast?
    @State private var editingSchedule: Schedule?
    @State private var confirmingDelete = false
    @State private var settingUpFocus = false
    @State private var pickingLook = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let current = controller.config.list(listID) {
            let list = Binding(get: { controller.config.list(listID) ?? current }, set: { controller.update($0) })
            VStack(spacing: 0) {
                Form {
                    header(list)
                    Section {
                        // A new list's name takes the keyboard first.
                        AddSearch(placeholder: list.wrappedValue.mode == .only ? "Add a site, app or category" : "Add a site to keep open, or an app",
                                  autofocus: model.focusName != listID) { result in
                            add(result)
                        }
                    }
                    websites(list)
                    apps(list)
                    schedules(list.wrappedValue)
                    focus(list.wrappedValue)
                    Section {
                        Button("Delete List…", role: .destructive) { confirmingDelete = true }
                            .disabled(controller.config.lists.count < 2)
                            .help(controller.config.lists.count < 2 ? "Seawall needs at least one list" : "Delete \(list.wrappedValue.name) and its schedules")
                    }
                }
                .formStyle(.grouped)
                // Under the form, not over it: a button floating over a form never gets the
                // click, it goes to the row underneath.
                ToastView(toast: $toast)
            }
            .confirmationDialog("Delete \(list.wrappedValue.name)?", isPresented: $confirmingDelete) {
                Button("Delete List", role: .destructive) {
                    controller.delete(list.wrappedValue)
                    onDeleted()
                }
            } message: {
                Text("Its schedules are deleted too. Blocks already running keep going.")
            }
            .sheet(isPresented: $settingUpFocus) {
                FocusSetup(list: list.wrappedValue)
            }
            .navigationTitle(list.wrappedValue.name)
            .task {
                if model.focusName == listID {
                    nameFocused = true
                    model.focusName = nil
                }
                askToDeleteIfAsked()
            }
            .onChange(of: model.deleting) { askToDeleteIfAsked() }
        }
    }

    /// "Delete…" in the sidebar asks here, where the list is.
    private func askToDeleteIfAsked() {
        guard model.deleting == listID else { return }
        model.deleting = nil
        confirmingDelete = true
    }

    // MARK: - Name and look

    private func header(_ list: Binding<BlockList>) -> some View {
        Section {
            HStack(spacing: Space.m) {
                Button { pickingLook = true } label: {
                    ListBadge(symbol: list.wrappedValue.symbol, color: list.wrappedValue.color, size: 40)
                }
                .buttonStyle(.plain)
                .help("Change the icon and colour")
                .accessibilityLabel("Icon and colour")
                .popover(isPresented: $pickingLook, arrowEdge: .bottom) {
                    LookPicker(list: list)
                }
                VStack(alignment: .leading, spacing: 2) {
                    TextField("List name", text: list.name, prompt: Text("List name"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .focused($nameFocused)
                    Text(list.wrappedValue.summary(otherBrowsersInstalled: controller.otherBrowsersInstalled))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Duplicate List") { _ = controller.duplicate(list.wrappedValue) }
                    Divider()
                    Button("Delete List…", role: .destructive) { confirmingDelete = true }
                        .disabled(controller.config.lists.count < 2)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More for this list")
                .accessibilityLabel("More for this list")
            }
        }
    }

    // MARK: - Websites

    private func websites(_ list: Binding<BlockList>) -> some View {
        Section {
            Picker("Block", selection: list.mode) {
                Text("Only these sites").tag(BlockList.Mode.only)
                Text("Every site except these").tag(BlockList.Mode.allExcept)
            }
            .pickerStyle(.segmented)

            switch list.wrappedValue.mode {
            case .only:
                ForEach(list.wrappedValue.groups, id: \.value) { item in
                    if item.value != .games, item.value != .web {
                        ItemRow(isOn: isOn(group: item.value, in: list), title: item.value.title, detail: item.value.summary,
                                hold: controller.hold(group: item.value),
                                onRemove: { remove(item.value.title, from: \.groups) { $0.value == item.value } }) {
                            GroupIcon(group: item.value, size: 18)
                        }
                    }
                }
                ForEach(list.wrappedValue.sites, id: \.value) { item in
                    let name = SiteRule(item.value)?.displayName ?? item.value
                    ItemRow(isOn: isOn(site: item.value, in: list), title: name, detail: name == item.value ? nil : item.value,
                            hold: controller.hold(site: item.value),
                            onRemove: { remove(name, from: \.sites) { $0.value == item.value } }) {
                        SiteIcon(pattern: item.value, size: 18)
                    }
                }
                if list.wrappedValue.sites.isEmpty && !list.wrappedValue.groups.contains(where: { $0.value != .games }) {
                    Text("No sites yet. Search above for a site like youtube.com/shorts, or a category like Social.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .allExcept:
                Text("Every site is blocked in Safari, Chrome, Arc, Brave and Edge, except the ones below. Pages on your own Mac always open.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(list.wrappedValue.allowed, id: \.self) { pattern in
                    let name = SiteRule(pattern)?.displayName ?? pattern
                    ItemRow(isOn: nil, title: name, detail: name == pattern ? nil : pattern,
                            onRemove: { remove(name, from: \.allowed) { $0 == pattern } }) {
                        SiteIcon(pattern: pattern, size: 18)
                    }
                }
                if list.wrappedValue.allowed.isEmpty {
                    Text("Nothing is kept open yet. Search above to add a site, like docs.google.com.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Websites")
        }
    }

    // MARK: - Apps

    private func apps(_ list: Binding<BlockList>) -> some View {
        Section {
            ItemRow(isOn: gamesBinding(list), title: "All games",
                    detail: "Any app macOS files as a game, Steam and Epic libraries, launchers and game sites",
                    hold: controller.hold(group: .games), onRemove: nil) {
                GroupIcon(group: .games, size: 18)
            }
            ForEach(list.wrappedValue.apps) { app in
                ItemRow(isOn: isOn(app: app.bundleID, in: list), title: app.name, detail: nil,
                        hold: controller.hold(app: app.bundleID),
                        onRemove: { remove(app.name, from: \.apps) { $0.bundleID == app.bundleID } }) {
                    AppIcon(path: app.path, size: 18)
                }
            }
            Button("Choose from Applications…") {
                let apps = controller.pickApps()
                guard !apps.isEmpty else { return }
                controller.mutateList(listID) { list in
                    for app in apps { list.addApp(app) }
                }
                toast = Toast(message: "Added \(Format.list(apps.map(\.name)))", undo: nil)
            }
            if controller.otherBrowsersInstalled {
                Toggle(isOn: list.otherBrowsers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Close other browsers")
                        Text("\(Format.list(InstalledBrowsers.unreadable.map(\.name))) can't be checked, so they're closed during the block.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Apps")
        }
    }

    private func isOn(group: SiteGroup, in list: Binding<BlockList>) -> Binding<Bool> {
        Binding(get: { list.wrappedValue.groups.first { $0.value == group }?.isOn ?? false }, set: { on in
            if let index = list.wrappedValue.groups.firstIndex(where: { $0.value == group }) { list.wrappedValue.groups[index].isOn = on }
        })
    }

    private func isOn(site pattern: String, in list: Binding<BlockList>) -> Binding<Bool> {
        Binding(get: { list.wrappedValue.sites.first { $0.value == pattern }?.isOn ?? false }, set: { on in
            if let index = list.wrappedValue.sites.firstIndex(where: { $0.value == pattern }) { list.wrappedValue.sites[index].isOn = on }
        })
    }

    private func isOn(app bundleID: String, in list: Binding<BlockList>) -> Binding<Bool> {
        Binding(get: { list.wrappedValue.apps.first { $0.bundleID == bundleID }?.isOn ?? false }, set: { on in
            if let index = list.wrappedValue.apps.firstIndex(where: { $0.bundleID == bundleID }) { list.wrappedValue.apps[index].isOn = on }
        })
    }

    /// "All games" is the Games category: on, off, or not in the list yet.
    private func gamesBinding(_ list: Binding<BlockList>) -> Binding<Bool> {
        Binding(get: {
            list.wrappedValue.groups.contains { $0.value == .games && $0.isOn }
        }, set: { on in
            if on {
                list.wrappedValue.addGroup(.games)
            } else if let index = list.wrappedValue.groups.firstIndex(where: { $0.value == .games }) {
                list.wrappedValue.groups[index].isOn = false
            }
        })
    }

    // MARK: - Schedules

    private func schedules(_ list: BlockList) -> some View {
        let schedules = controller.schedules(of: list)
        return Section {
            ForEach(schedules) { schedule in
                if editingSchedule?.id == schedule.id {
                    editor(for: schedule, isNew: false)
                } else {
                    ScheduleRow(schedule: schedule, onEdit: { editingSchedule = schedule })
                }
            }
            if let draft = editingSchedule, !schedules.contains(where: { $0.id == draft.id }) {
                editor(for: draft, isNew: true)
            }
            if editingSchedule == nil {
                Button("Add a Time…") {
                    editingSchedule = Schedule(listID: list.id, listName: list.name, days: [2, 3, 4, 5, 6],
                                               start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 12, minute: 0))
                }
            }
        } header: {
            Text("Starts on its own")
        } footer: {
            Text("Each stretch starts once, so ending it early doesn't bring it back. All your schedules are under Schedules in the sidebar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Edits a copy, so closing the editor never pulls the schedule out from under it.
    private func editor(for schedule: Schedule, isNew: Bool) -> some View {
        ScheduleEditor(schedule: schedule, lists: nil, isNew: isNew,
                       save: {
                           controller.saveSchedule($0)
                           editingSchedule = nil
                       },
                       delete: {
                           controller.deleteSchedule($0)
                           editingSchedule = nil
                       },
                       cancel: { editingSchedule = nil })
            .id(schedule.id)
    }

    // MARK: - Focus

    private func focus(_ list: BlockList) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with a Focus")
                    Text("Lock \(list.name) when a Focus like Work turns on, through a Shortcuts automation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Set Up…") { settingUpFocus = true }
            }
        }
    }

    // MARK: - Adding and removing

    /// Adds what was picked in the search box and says so, with Undo: the new row can land
    /// below the fold. Undo puts back exactly what was there, even if other things changed since.
    private func add(_ result: AddSearch.Result) {
        let controller = self.controller, id = listID
        guard let before = controller.config.list(id) else { return }
        switch result {
        case .group(let group):
            let old = before.groups.first { $0.value == group }
            controller.mutateList(id) { $0.addGroup(group) }
            confirmAdd(group.title, wasOn: old?.isOn == true) {
                controller.mutateList(id) { $0.groups.putBack(old) { $0.value == group } }
            }
        case .app(let app):
            let old = before.apps.first { $0.bundleID == app.bundleID }
            controller.mutateList(id) { $0.addApp(app) }
            confirmAdd(app.name, wasOn: old?.isOn == true) {
                controller.mutateList(id) { $0.apps.putBack(old) { $0.bundleID == app.bundleID } }
            }
        case .site(let pattern):
            guard let normal = SiteRule(pattern)?.description else { return }
            let name = SiteRule(normal)?.displayName ?? normal
            if before.mode == .allExcept {
                let had = before.allowed.contains(normal)
                controller.mutateList(id) { $0.addSite(normal) }
                confirmAdd(name, wasOn: had) {
                    controller.mutateList(id) { $0.allowed.removeAll { $0 == normal } }
                }
            } else {
                let old = before.sites.first { $0.value == normal }
                controller.mutateList(id) { $0.addSite(normal) }
                confirmAdd(name, wasOn: old?.isOn == true) {
                    controller.mutateList(id) { $0.sites.putBack(old) { $0.value == normal } }
                }
            }
        }
    }

    private func confirmAdd(_ name: String, wasOn: Bool, undo: @escaping () -> Void) {
        toast = wasOn ? Toast(message: "\(name) is already in this list", undo: nil) : Toast(message: "Added \(name)", undo: undo)
    }

    /// Takes something out of the list; Undo puts it back where it was.
    private func remove<Item>(_ name: String, from items: WritableKeyPath<BlockList, [Item]>, where matches: @escaping (Item) -> Bool) {
        let controller = self.controller, id = listID
        guard let list = controller.config.list(id), let index = list[keyPath: items].firstIndex(where: matches) else { return }
        let item = list[keyPath: items][index]
        controller.mutateList(id) { $0[keyPath: items].remove(at: index) }
        toast = Toast(message: "Removed \(name)") {
            controller.mutateList(id) { list in
                guard !list[keyPath: items].contains(where: matches) else { return }
                list[keyPath: items].insert(item, at: min(index, list[keyPath: items].count))
            }
        }
    }
}

private extension Array {
    /// Undoes an add: the item as it was, if it was there (switched off, say), or nothing.
    mutating func putBack(_ old: Element?, where matches: (Element) -> Bool) {
        if let old {
            if let index = firstIndex(where: matches) { self[index] = old }
        } else {
            removeAll(where: matches)
        }
    }
}

/// Something in a list: a checkbox (ticked is blocked), its icon and name, and an × that
/// shows up on hover. A small lock says a running block holds it right now; unticked, the row
/// says what still holds it, since unticking only counts from the next block.
struct ItemRow<Icon: View>: View {
    let isOn: Binding<Bool>?
    let title: String
    let detail: String?
    var hold: Hold?
    let onRemove: (() -> Void)?
    @ViewBuilder let icon: Icon
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.s) {
            if let isOn {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(isOn.wrappedValue ? "Blocked. Untick to leave it open." : "Not blocked. Tick to block it.")
            }
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if let line = detailLine {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s)
            if let hold {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help(Self.explain(hold))
                    .accessibilityLabel(Self.explain(hold))
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.25)
                .help("Remove \(title) from this list")
                .accessibilityLabel("Remove \(title)")
            }
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }

    /// The row's second line: what still holds it while unticked, or else its detail.
    private var detailLine: String? {
        guard let hold, isOn?.wrappedValue == false else { return detail }
        let until = Format.clockTime(hold.until, relativeTo: Date())
        return "Still locked until \(until) by \(hold.by ?? "a running block")"
    }

    /// "Locked until 18:00: a running block covers YouTube. Changes here apply to the next block."
    static func explain(_ hold: Hold) -> String {
        let until = Format.clockTime(hold.until, relativeTo: Date())
        let why = hold.by.map { "a running block covers \($0)" } ?? "a running block holds it"
        return "Locked until \(until): \(why). Changes here apply to the next block."
    }
}

/// A list's symbol and colour.
private struct LookPicker: View {
    @Binding var list: BlockList

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 6), spacing: 6) {
                ForEach(BlockList.symbols, id: \.self) { symbol in
                    Button { list.symbol = symbol } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(list.symbol == symbol ? list.color.color.opacity(0.25) : Color.primary.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(list.symbol == symbol ? list.color.color : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                }
            }
            HStack(spacing: 8) {
                ForEach(ListColor.allCases, id: \.self) { color in
                    Button { list.color = color } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(list.color == color ? 0.9 : 0), lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(list.color == color ? .isSelected : [])
                }
            }
        }
        .padding(Space.l)
    }
}

/// "Removed Twitch · Undo", for a few seconds.
struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
}

struct ToastView: View {
    @Binding var toast: Toast?

    var body: some View {
        if let current = toast {
            HStack(spacing: Space.m) {
                Text(current.message)
                    .lineLimit(1)
                if let undo = current.undo {
                    Button("Undo") {
                        undo()
                        toast = nil
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                }
            }
            .padding(.leading, Space.l)
            .padding(.trailing, current.undo == nil ? Space.l : Space.m)
            .padding(.vertical, Space.s)
            // Solid: it sits in its own band under the form, with nothing behind it to see through.
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            // Over the Undo button: an outline that took clicks is what kept Undo from working.
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .padding(.vertical, Space.m)
            .task(id: current.id) {
                try? await Task.sleep(for: .seconds(8))
                if toast?.id == current.id {
                    withAnimation { toast = nil }
                }
            }
        }
    }
}
