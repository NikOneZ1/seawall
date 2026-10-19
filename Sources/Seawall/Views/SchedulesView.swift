import SeawallCore
import SwiftUI

/// Settings' list of schedules, each a saved list on certain days and hours, and the editor
/// for adding or changing one.
struct SchedulesSection: View {
    @EnvironmentObject private var controller: BlockController
    /// The schedule being added or changed; `nil` when the editor is closed.
    @State private var draft: Schedule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Deep.label("Schedules")

            ForEach(controller.config.schedules) { schedule in
                if draft?.id == schedule.id {
                    editor
                } else {
                    row(schedule)
                }
            }

            if let draft, !controller.config.schedules.contains(where: { $0.id == draft.id }) {
                editor
            } else if draft == nil {
                if controller.config.lists.isEmpty {
                    Text("A schedule locks one of your saved lists. Save one first: in the menu, open + Add and choose “Save what's on as a list…”.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    QuietButton(title: "+ Add a schedule") {
                        draft = Schedule(listName: controller.config.lists[0].name, days: [2, 3, 4, 5, 6],
                                         start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0))
                    }
                }
            }
        }
    }

    private func row(_ schedule: Schedule) -> some View {
        let missing = !controller.config.lists.contains { $0.name == schedule.listName }
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.listName)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(missing ? "Its list was deleted, so it does nothing." : schedule.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(missing ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 12)
            QuietButton(title: "Edit") { draft = schedule }
                .padding(.trailing, 8)
            Toggle(schedule.listName, isOn: Binding(
                get: { schedule.enabled },
                set: { on in
                    var changed = schedule
                    changed.enabled = on
                    controller.saveSchedule(changed)
                }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let binding = Binding($draft) {
            ScheduleEditor(schedule: binding, lists: controller.config.lists.map(\.name),
                           isNew: !controller.config.schedules.contains { $0.id == binding.wrappedValue.id },
                           save: {
                               controller.saveSchedule(binding.wrappedValue)
                               draft = nil
                           },
                           delete: {
                               controller.deleteSchedule(binding.wrappedValue)
                               draft = nil
                           },
                           cancel: { draft = nil })
        }
    }
}

/// "Work on Mon Tue Wed Thu Fri, from 10:00 to 18:00".
private struct ScheduleEditor: View {
    @Binding var schedule: Schedule
    let lists: [String]
    let isNew: Bool
    let save: () -> Void
    let delete: () -> Void
    let cancel: () -> Void

    /// Monday first, as `Calendar` weekday numbers.
    private static let week: [(Int, String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lock").foregroundStyle(.secondary)
                Picker("List", selection: $schedule.listName) {
                    ForEach(lists, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            HStack(spacing: 6) {
                ForEach(Self.week, id: \.0) { day, letter in
                    let on = schedule.days.contains(day)
                    Button {
                        if on { schedule.days.remove(day) } else { schedule.days.insert(day) }
                    } label: {
                        Text(letter)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Deep.ink : Color.white.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
                                .strokeBorder(Color.white.opacity(on ? 0 : 0.18)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Text("from").foregroundStyle(.secondary)
                TimePicker(time: $schedule.start)
                Text("to").foregroundStyle(.secondary)
                TimePicker(time: $schedule.end)
            }

            HStack(spacing: 8) {
                Button("Save", action: save)
                    .buttonStyle(PillButtonStyle(primary: true))
                    .disabled(schedule.days.isEmpty || schedule.start == schedule.end)
                Button("Cancel", action: cancel)
                    .buttonStyle(PillButtonStyle())
                Spacer()
                if !isNew {
                    QuietButton(title: "Delete", destructive: true, action: delete)
                }
            }
        }
        .font(.system(size: 13))
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// "10 ⌄ : 00 ⌄", in quiet text menus.
private struct TimePicker: View {
    @Binding var time: TimeOfDay

    var body: some View {
        HStack(spacing: 2) {
            menu(String(format: "%02d", time.hour), Array(0..<24)) { time.hour = $0 }
            Text(":").foregroundStyle(.secondary)
            menu(String(format: "%02d", time.minute), Array(stride(from: 0, to: 60, by: 5))) { time.minute = $0 }
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
    }

    private func menu(_ title: String, _ values: [Int], set: @escaping (Int) -> Void) -> some View {
        Menu(title) {
            ForEach(values, id: \.self) { value in
                Button(String(format: "%02d", value)) { set(value) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
