import SeawallCore
import SwiftUI

/// Ready to lock. Reads as a sentence: Lock [Work] for [2h], then hold.
struct LockView: View {
    /// Back to the running blocks; `nil` when nothing is blocked yet.
    var back: (() -> Void)?
    @EnvironmentObject private var controller: BlockController
    @State private var pickingTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            Group {
                cards
                if let list = controller.selectedList {
                    contents(of: list)
                }
                LengthRow(pickingTime: $pickingTime)
                if pickingTime {
                    UntilField(done: { pickingTime = false })
                }
                breaks
            }

            VStack(spacing: Space.s) {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .help(controller.selectedList?.itemNames.joined(separator: ", ") ?? "")
                HoldButton(title: holdTitle, isEnabled: controller.canStart) {
                    controller.startBlock()
                    back?()
                }
                StrictnessMenu()
            }
            deniedNotice
        }
        // Esc steps back one level: out of the time field, back to the running blocks, then out of the menu.
        .onEscape {
            if pickingTime {
                pickingTime = false
            } else if let back {
                back()
            } else {
                MenuShortcut.closeMenu()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            if let back {
                Button(action: back) {
                    Label("Running blocks", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Back to what's locked")
            } else {
                Text("Lock")
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            MoreMenu()
        }
    }

    // MARK: - Which list

    /// Two to a row. A plain grid, not a lazy one: a lazy grid sizes its later rows only once
    /// they're drawn, after the menu has been placed, and the menu then grew up past the top
    /// of the screen.
    private var cards: some View {
        var slots = controller.config.lists.map(CardSlot.list)
        // Only where there's room in the last row; the gear menu always has New List.
        if slots.count % 2 != 0 { slots.append(.add) }
        let rows = stride(from: 0, to: slots.count, by: 2).map { Array(slots[$0..<min($0 + 2, slots.count)]) }
        return Grid(horizontalSpacing: Space.s, verticalSpacing: Space.s) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { slot in
                        card(slot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ slot: CardSlot) -> some View {
        switch slot {
        case .list(let list):
            ListCard(list: list, detail: detail(for: list), isSelected: list.id == controller.selectedList?.id) {
                controller.select(list)
            }
            .contextMenu {
                Button("Edit \(list.name)…") { Panels.showMain(.list(list.id), controller: controller) }
            }
        case .add:
            NewListCard { Panels.showNewList(controller: controller) }
        }
    }

    /// When the list starts on its own, or else how much it holds.
    private func detail(for list: BlockList) -> String {
        if let schedule = controller.schedules(of: list).first(where: \.enabled) {
            return schedule.shortSummary
        }
        if list.mode == .allExcept { return "Whole web" }
        let count = list.enabledGroups.count + list.enabledSites.count + list.enabledApps.count
        return count == 0 ? "Empty" : Format.count(count, "item", "items")
    }

    /// "Social, Games, YouTube Shorts and 3 more", and the way into the editor.
    private func contents(of list: BlockList) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            ViewThatFits(in: .horizontal) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { count in
                    Text(Self.names(list.itemNames, fitting: count))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Edit…") { Panels.showMain(.list(list.id), controller: controller) }
                .font(.subheadline)
                .buttonStyle(.link)
                .help("Change what \(list.name) locks")
        }
    }

    /// The first few names, then how many more.
    static func names(_ names: [String], fitting count: Int) -> String {
        guard !names.isEmpty else { return "Nothing in this list yet" }
        guard names.count > count else { return Format.list(names) }
        return names.prefix(count).joined(separator: ", ") + " and \(names.count - count) more"
    }

    // MARK: - Breaks

    @ViewBuilder
    private var breaks: some View {
        if let rounds = controller.availableRounds {
            Toggle(isOn: $controller.config.next.breaks) {
                Text("Breaks: \(rounds.count) rounds of 25 min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Sites open during the breaks, then lock again")
        }
    }

    // MARK: - Start

    private var summary: String {
        guard let list = controller.selectedList else { return "" }
        guard !list.isEmpty(otherBrowsersInstalled: controller.otherBrowsersInstalled) else {
            return "\(list.name) is empty. Add sites or apps with Edit."
        }
        let what = list.summary(otherBrowsersInstalled: controller.otherBrowsersInstalled)
        let end = Format.clockTime(controller.plannedEnd, relativeTo: controller.now)
        if let rounds = controller.plannedRounds {
            return "\(what), in \(rounds.count) rounds until \(end)"
        }
        return "\(what), until \(end)"
    }

    private var holdTitle: String {
        guard let list = controller.selectedList,
              !list.isEmpty(otherBrowsersInstalled: controller.otherBrowsersInstalled) else { return "Add something to lock" }
        guard controller.plannedEnd > controller.now else { return "That time has passed" }
        return "Hold to lock"
    }

    @ViewBuilder
    private var deniedNotice: some View {
        let denied = controller.deniedBrowsers.map(\.name)
        if let list = controller.selectedList, list.mode == .allExcept || list.blockedSiteCount > 0, !denied.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Label("\(Format.list(denied)) can't be checked, so \(denied.count == 1 ? "it" : "they") will be closed during the block.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Button("Fix…") { controller.openAutomationSettings() }
                    .controlSize(.small)
            }
        }
    }
}

/// A place in the grid of lists: a list, or the card that adds one.
private enum CardSlot: Identifiable {
    case list(BlockList)
    case add

    var id: String {
        switch self {
        case .list(let list): list.id.uuidString
        case .add: "add"
        }
    }
}

/// "for [25m | 1h | 2h] [More ⌄]": the three usual lengths, and everything else in a menu.
private struct LengthRow: View {
    @Binding var pickingTime: Bool
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        HStack(spacing: Space.s) {
            Text("for")
                .font(.title3.weight(.semibold))
            Picker("Length", selection: preset) {
                ForEach(BlockLength.presets, id: \.self) { length in
                    Text(length.short).tag(Optional(length))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Menu {
                Section("For") {
                    ForEach(BlockLength.more, id: \.self) { length in
                        Button(length.title) { set(length) }
                    }
                }
                Section("Until") {
                    ForEach(UntilPreset.allCases, id: \.self) { preset in
                        if let until = preset.until(from: controller.now) {
                            Button("\(preset.title(for: until)), \(preset.time.text)") { set(.until(until)) }
                        }
                    }
                    Button("Custom…") { pickingTime = true }
                }
            } label: {
                Text(moreTitle)
            }
            .fixedSize()
            .help("Other lengths, or until a set time")
        }
    }

    /// The segmented control's choice; none when the length came from the menu.
    private var preset: Binding<BlockLength?> {
        Binding(get: {
            BlockLength.presets.contains(controller.config.next.length) ? controller.config.next.length : nil
        }, set: { length in
            if let length { set(length) }
        })
    }

    private var moreTitle: String {
        let length = controller.config.next.length
        guard !BlockLength.presets.contains(length) else { return "More" }
        switch length {
        case .minutes: return length.short
        case .until: return "Until \(Format.shortClockTime(length.end(from: controller.now), relativeTo: controller.now))"
        }
    }

    private func set(_ length: BlockLength) {
        controller.config.next.length = length
        pickingTime = false
    }
}

/// "until [Tomorrow ⌄] [09:00] Set": a day from the next week, then a time.
private struct UntilField: View {
    let done: () -> Void
    @EnvironmentObject private var controller: BlockController
    @State private var day = 0
    @State private var time = TimeOfDay(hour: 18, minute: 0)

    var body: some View {
        let now = controller.now
        HStack(spacing: Space.s) {
            Text("until")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Day", selection: $day) {
                ForEach(Array(UntilTime.days), id: \.self) { offset in
                    Text(Format.day(offset, from: now)).tag(offset)
                }
            }
            .labelsHidden()
            .fixedSize()
            TimeField(time: $time)
            Spacer(minLength: 0)
            Button("Set") { apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(until.date(from: now) <= now)
                .help(until.date(from: now) <= now ? "That time has passed" : "")
        }
        .onAppear {
            // Starts from the end already picked, or an hour from now, on a 5-minute mark.
            let calendar = Calendar.current
            let step = TimeInterval(UntilTime.minuteStep * 60)
            let start = max(controller.plannedEnd, now + 3600)
            let rounded = Date(timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: rounded)).day ?? 0
            day = min(max(days, 0), UntilTime.days.upperBound)
            let parts = calendar.dateComponents([.hour, .minute], from: rounded)
            time = TimeOfDay(hour: parts.hour ?? 18, minute: parts.minute ?? 0)
        }
    }

    private var until: UntilTime {
        UntilTime(day: day, hour: time.hour, minute: time.minute)
    }

    private func apply() {
        controller.config.next.length = .until(until)
        done()
    }
}

/// "Flexible · leave after a 10-minute wait ⌄": how hard this block will be to leave, picked
/// right where it's locked. The default lives in Settings; a change here is for this block only.
struct StrictnessMenu: View {
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let current = controller.nextStrictness
        Menu {
            Picker("Strictness", selection: Binding(get: { current }, set: { level in
                controller.strictness = level == Preferences.shared.earlyExit ? nil : level
            })) {
                ForEach(EarlyExit.allCases) { level in
                    Text("\(level.name): \(level.detail)").tag(level)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text("\(current.name) · \(current.detail)")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity)
        .help(controller.strictness == nil ? "How this block can be left early. The default is in Settings." : "Just for this block")
        .accessibilityLabel("Strictness: \(current.name), \(current.detail)")
    }
}
