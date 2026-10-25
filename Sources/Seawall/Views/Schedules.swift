import SeawallCore
import SwiftUI

/// Every schedule on one week grid, each list in its colour. Drag across days and hours to
/// paint a new one for the chosen list; click a stretch to change it. The editor opens as a
/// sheet, so it shows up wherever the grid is scrolled.
struct SchedulesPane: View {
    @EnvironmentObject private var controller: BlockController
    @State private var paintList: UUID?
    @State private var editing: Schedule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("A schedule locks a list on its own, on the days and hours you paint. Drag across the grid to add one.")
                    .foregroundStyle(.secondary)
                HStack(spacing: Space.s) {
                    Text("Paint with")
                    if let list = controller.config.list(paintBinding.wrappedValue) {
                        ListBadge(symbol: list.symbol, color: list.color, size: 20)
                    }
                    Picker("Paint with", selection: paintBinding) {
                        ForEach(controller.config.lists) { list in
                            Text(list.name).tag(Optional(list.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button("Add a Schedule…") { editing = draft(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 12 * 60) }
                }
                WeekGrid(schedules: shownSchedules, colors: colors, selected: editing?.id,
                         paintColor: controller.config.list(paintBinding.wrappedValue)?.color ?? .sea,
                         onPaint: { days, start, end in editing = draft(days: days, start: start, end: end) },
                         onSelect: { editing = $0 })
                if !controller.config.schedules.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(controller.config.schedules.enumerated()), id: \.element.id) { index, schedule in
                            if index > 0 { Divider() }
                            ScheduleRow(schedule: schedule, showsList: true, onEdit: { editing = schedule })
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
            }
            .padding(Space.xl)
        }
        .navigationTitle("Schedules")
        .sheet(item: $editing) { schedule in
            let isNew = !controller.config.schedules.contains { $0.id == schedule.id }
            VStack(alignment: .leading, spacing: Space.l) {
                Text(isNew ? "New Schedule" : "Edit Schedule")
                    .font(.headline)
                ScheduleEditor(schedule: schedule, lists: controller.config.lists, isNew: isNew,
                               save: {
                                   controller.saveSchedule($0)
                                   editing = nil
                               },
                               delete: {
                                   controller.deleteSchedule($0)
                                   editing = nil
                               },
                               cancel: { editing = nil })
            }
            .padding(Space.xl)
            .frame(width: 400)
        }
    }

    /// The saved schedules, plus one just painted, so it stays on the grid while the sheet is up.
    private var shownSchedules: [Schedule] {
        let saved = controller.config.schedules
        guard let editing, !saved.contains(where: { $0.id == editing.id }) else { return saved }
        return saved + [editing]
    }

    private var colors: [UUID: ListColor] {
        Dictionary(uniqueKeysWithValues: controller.config.lists.map { ($0.id, $0.color) })
    }

    private var paintBinding: Binding<UUID?> {
        Binding(get: { paintList ?? controller.selectedList?.id }, set: { paintList = $0 })
    }

    private func draft(days: Set<Int>, start: Int, end: Int) -> Schedule {
        let list = controller.config.list(paintBinding.wrappedValue) ?? controller.config.lists[0]
        return Schedule(listID: list.id, listName: list.name, days: days,
                        start: TimeOfDay(hour: start / 60, minute: start % 60),
                        end: TimeOfDay(hour: (end / 60) % 24, minute: end % 60))
    }
}

/// Seven columns, Monday first, 24 hours down, in half-hour cells.
private struct WeekGrid: View {
    let schedules: [Schedule]
    let colors: [UUID: ListColor]
    let selected: UUID?
    let paintColor: ListColor
    /// Days as `Calendar` weekday numbers, start and end in minutes from midnight.
    let onPaint: (Set<Int>, Int, Int) -> Void
    let onSelect: (Schedule) -> Void

    @State private var dragStart: (column: Int, slot: Int)?
    @State private var dragEnd: (column: Int, slot: Int)?

    private static let slots = 48
    private static let slotHeight: CGFloat = 9
    private static let gutter: CGFloat = 34
    private static let header: CGFloat = 22
    private static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width - Self.gutter) / 7
            let height = CGFloat(Self.slots) * Self.slotHeight
            ZStack(alignment: .topLeading) {
                // Day names
                ForEach(0..<7, id: \.self) { column in
                    Text(Self.days[column])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: columnWidth, height: Self.header)
                        .offset(x: Self.gutter + CGFloat(column) * columnWidth)
                }
                // Hour lines and labels
                ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                    let y = Self.header + CGFloat(hour * 2) * Self.slotHeight
                    Text(String(format: "%02d", hour))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.gutter - 6, alignment: .trailing)
                        .offset(y: y - 6)
                    Rectangle()
                        .fill(Color.primary.opacity(hour % 12 == 0 ? 0.14 : 0.07))
                        .frame(width: columnWidth * 7, height: 0.5)
                        .offset(x: Self.gutter, y: y)
                }
                ForEach(0...7, id: \.self) { column in
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 0.5, height: height)
                        .offset(x: Self.gutter + CGFloat(column) * columnWidth, y: Self.header)
                }
                // Schedules
                ForEach(schedules) { schedule in
                    ForEach(Array(Timeline.weekCells(schedule).enumerated()), id: \.offset) { _, cell in
                        Stretch(schedule: schedule, color: schedule.listID.flatMap { colors[$0] }?.color ?? .sea,
                                isSelected: selected == schedule.id, onSelect: onSelect)
                            .frame(width: columnWidth - 6, height: max(6, CGFloat(cell.to - cell.from) * height))
                            .offset(x: Self.gutter + CGFloat(cell.column) * columnWidth + 3,
                                    y: Self.header + CGFloat(cell.from) * height)
                    }
                }
                // The stretch being painted
                if let start = dragStart, let end = dragEnd {
                    let columns = min(start.column, end.column)...max(start.column, end.column)
                    let slots = min(start.slot, end.slot)...max(start.slot, end.slot)
                    ForEach(Array(columns), id: \.self) { column in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(paintColor.color.opacity(0.45))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(paintColor.color, lineWidth: 1.5))
                            .frame(width: columnWidth - 6, height: CGFloat(slots.count) * Self.slotHeight)
                            .offset(x: Self.gutter + CGFloat(column) * columnWidth + 3,
                                    y: Self.header + CGFloat(slots.lowerBound) * Self.slotHeight)
                    }
                }
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if dragStart == nil { dragStart = cell(at: value.startLocation, columnWidth: columnWidth) }
                    dragEnd = cell(at: value.location, columnWidth: columnWidth)
                }
                .onEnded { _ in
                    if let start = dragStart, let end = dragEnd {
                        let columns = min(start.column, end.column)...max(start.column, end.column)
                        let days = Set(columns.map { ($0 + 1) % 7 + 1 })
                        let first = min(start.slot, end.slot) * 30
                        let last = (max(start.slot, end.slot) + 1) * 30
                        onPaint(days, first, last)
                    }
                    dragStart = nil
                    dragEnd = nil
                })
        }
        .frame(height: Self.header + CGFloat(Self.slots) * Self.slotHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week of schedules. Use Add a Schedule to add one with the keyboard.")
    }

    private func cell(at point: CGPoint, columnWidth: CGFloat) -> (column: Int, slot: Int) {
        let column = Int(((point.x - Self.gutter) / columnWidth).rounded(.down))
        let slot = Int(((point.y - Self.header) / Self.slotHeight).rounded(.down))
        return (min(max(column, 0), 6), min(max(slot, 0), Self.slots - 1))
    }
}

/// One schedule's block on the grid, in its list's colour. Clicking it, or VoiceOver's
/// default action, opens it.
private struct Stretch: View {
    let schedule: Schedule
    let color: Color
    let isSelected: Bool
    let onSelect: (Schedule) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        shape
            .fill(color.opacity(schedule.enabled ? 0.75 : 0.25))
            .overlay(shape.strokeBorder(Color.primary.opacity(isSelected ? 0.8 : 0), lineWidth: 2))
            .onTapGesture { onSelect(schedule) }
            .help("\(schedule.listName): \(schedule.summary)")
            .accessibilityElement()
            .accessibilityLabel("\(schedule.listName), \(schedule.summary)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect(schedule) }
    }
}

/// One schedule as a row: when it runs, a switch, and Edit.
struct ScheduleRow: View {
    let schedule: Schedule
    var showsList = false
    let onEdit: () -> Void
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        HStack(spacing: Space.s) {
            if showsList, let list = controller.list(for: schedule) {
                ListBadge(symbol: list.symbol, color: list.color, size: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(showsList ? (controller.list(for: schedule)?.name ?? "A deleted list") : Schedule.dayNames(schedule.days))
                Text(showsList ? schedule.summary : "\(schedule.start.text)–\(schedule.end.text)\(schedule.end <= schedule.start ? " next day" : "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", action: onEdit)
                .controlSize(.small)
            Toggle("On", isOn: Binding(get: { schedule.enabled }, set: { on in
                var changed = schedule
                changed.enabled = on
                controller.saveSchedule(changed)
            }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(schedule.enabled ? "On: starts on its own" : "Off: won't start")
        }
    }
}

/// "Work on Mon Tue Wed Thu Fri, from 09:00 to 12:00". Works on its own copy and hands it
/// back on Add or Save.
struct ScheduleEditor: View {
    /// Shown as a list picker when the schedule isn't edited from inside its list.
    let lists: [BlockList]?
    let isNew: Bool
    let save: (Schedule) -> Void
    let delete: (Schedule) -> Void
    let cancel: () -> Void
    @State private var schedule: Schedule

    init(schedule: Schedule, lists: [BlockList]?, isNew: Bool, save: @escaping (Schedule) -> Void,
         delete: @escaping (Schedule) -> Void, cancel: @escaping () -> Void) {
        _schedule = State(initialValue: schedule)
        self.lists = lists
        self.isNew = isNew
        self.save = save
        self.delete = delete
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let lists {
                Picker("Lock", selection: $schedule.listID) {
                    ForEach(lists) { list in
                        Text(list.name).tag(Optional(list.id))
                    }
                }
                .fixedSize()
            }
            DayPicker(days: $schedule.days)
            HStack(spacing: Space.s) {
                Text("From")
                TimeField(time: $schedule.start)
                Text("to")
                TimeField(time: $schedule.end)
                if schedule.end <= schedule.start {
                    Text("the next day")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { delete(schedule) }
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save(schedule) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(schedule.days.isEmpty || schedule.start == schedule.end)
            }
        }
    }
}

/// M T W T F S S, Monday first.
struct DayPicker: View {
    @Binding var days: Set<Int>
    private static let week: [(Int, String, String)] = [(2, "M", "Monday"), (3, "T", "Tuesday"), (4, "W", "Wednesday"), (5, "T", "Thursday"),
                                                        (6, "F", "Friday"), (7, "S", "Saturday"), (1, "S", "Sunday")]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.week, id: \.0) { day, letter, name in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(letter)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A time of day in a standard field.
struct TimeField: View {
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker("Time", selection: Binding(get: {
            Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }), displayedComponents: .hourAndMinute)
        .datePickerStyle(.stepperField)
        .labelsHidden()
        .fixedSize()
    }
}
