import SeawallCore
import SwiftUI

/// While blocks run: how long is left, what's locked, and the honest way out. A running block
/// can be made stricter (more time, more sites) but never looser, except through the wait.
struct LockedView: View {
    let onAdd: () -> Void
    @EnvironmentObject private var controller: BlockController
    /// The block whose "Leave early" explanation is showing.
    @State private var leaving: Session.ID?
    /// The block getting another site or app.
    @State private var adding: Session.ID?

    var body: some View {
        let sessions = controller.sessions
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                MoreMenu()
            }
            if sessions.count == 1, let session = sessions.first {
                single(session)
            } else {
                many(sessions)
            }
        }
        // Esc closes whatever is open inside first, then the menu.
        .onEscape {
            if adding != nil {
                adding = nil
            } else if leaving != nil {
                leaving = nil
            } else {
                MenuShortcut.closeMenu()
            }
        }
    }

    private var headline: String {
        let now = controller.now
        let sessions = controller.sessions
        guard sessions.count == 1, let session = sessions.first else {
            let until = controller.blockedUntil.map { Format.when($0, relativeTo: now) } ?? ""
            return "Everything opens \(until)"
        }
        guard let rounds = session.rounds, let phase = session.phase(at: now) else {
            return "\(session.title) · locked until \(Format.clockTime(session.endsAt, relativeTo: now))"
        }
        switch phase {
        case .locked(let round, let endsAt):
            return "\(session.title) · round \(round) of \(rounds.count) · until \(Format.clockTime(endsAt, relativeTo: now))"
        case .resting(let next, let until):
            return "\(session.title) · break · round \(next) at \(Format.clockTime(until, relativeTo: now))"
        }
    }

    // MARK: - One block

    private func single(_ session: Session) -> some View {
        let now = controller.now
        let phaseEnd = session.phase(at: now).map(Self.phaseEnd) ?? session.endsAt
        return VStack(alignment: .leading, spacing: Space.m) {
            CountdownText(seconds: phaseEnd.timeIntervalSince(now))
                .font(.timer)
            ProgressBar(value: progress(session), segments: session.rounds?.count ?? 1)
            BlockedNames(session: session)
            Text(session.attempts == 0 ? "No tries yet" : "\(Format.count(session.attempts, "try", "tries")) caught")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            controls(for: session, wide: true)
        }
    }

    // MARK: - Several blocks

    private func many(_ sessions: [Session]) -> some View {
        let now = controller.now
        return VStack(alignment: .leading, spacing: Space.m) {
            CountdownText(seconds: (controller.blockedUntil ?? now).timeIntervalSince(now))
                .font(.timer)
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider() }
                    SessionRow(session: session, onLeave: { leaving = session.id }, onAddSite: { adding = session.id })
                    if leaving == session.id || adding == session.id || session.unlockState(at: now) != .locked {
                        controls(for: session, wide: false)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)).allowsHitTesting(false))
            Button(action: onAdd) {
                Label("Lock Another List", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Actions

    /// "＋ Add" and "Leave early…", or whichever stage of leaving early this block is in.
    @ViewBuilder
    private func controls(for session: Session, wide: Bool) -> some View {
        let state = session.unlockState(at: controller.now)
        if adding == session.id {
            AddToBlock(session: session, done: { adding = nil })
        } else if case .waiting(let remaining) = state {
            WaitPanel(session: session, remaining: remaining)
            HStack(spacing: Space.s) {
                // Waiting to leave doesn't stop the block getting stricter.
                if wide {
                    AddMenu(session: session, onAddSite: { adding = session.id }, onAddList: onAdd)
                }
                Button {
                    controller.cancelUnlock(session.id)
                } label: {
                    Text("Stay Locked").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        } else if case .ready(let expiresIn) = state {
            ReadyPanel(session: session, expiresIn: expiresIn)
        } else if leaving == session.id {
            LeaveExplainer(session: session, close: { leaving = nil })
        } else if wide {
            HStack(spacing: Space.s) {
                AddMenu(session: session, onAddSite: { adding = session.id }, onAddList: onAdd)
                if session.earlyExit.wait != nil {
                    Button { leaving = session.id } label: {
                        Text("Leave Early…").frame(maxWidth: .infinity)
                    }
                    .help("Ending this block early takes a \(Int((session.earlyExit.wait ?? 0) / 60))-minute wait")
                } else {
                    Label("No way out", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .help("This block was locked with no way to end it early")
                }
            }
        }
    }

    private func progress(_ session: Session) -> Double {
        let total = session.endsAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 1 }
        return min(max(controller.now.timeIntervalSince(session.startedAt) / total, 0), 1)
    }

    private static func phaseEnd(_ phase: Phase) -> Date {
        switch phase {
        case .locked(_, let endsAt): endsAt
        case .resting(_, let until): until
        }
    }
}

/// "YouTube Shorts, Twitch, Social and 3 more", with the first few icons beside it.
private struct BlockedNames: View {
    let session: Session

    var body: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: -4) {
                ForEach(Array(icons.prefix(3).enumerated()), id: \.offset) { _, icon in
                    icon
                }
            }
            Text(LockView.names(names, fitting: 3))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(names.joined(separator: ", "))
    }

    private var names: [String] {
        var names = session.groups.filter { $0 != .web }.map(\.title) + session.sites.map { SiteRule($0)?.displayName ?? $0 } + session.apps.map(\.name)
        if session.blocksWholeWeb {
            let open = session.allowedSites.map { SiteRule($0)?.displayName ?? $0 }
            names.insert(open.isEmpty ? "The whole web" : "The whole web except \(Format.list(open))", at: 0)
        }
        if session.blocksOtherBrowsers { names.append("other browsers") }
        return names
    }

    private var icons: [AnyView] {
        session.groups.map { AnyView(GroupIcon(group: $0)) }
            + session.sites.map { AnyView(SiteIcon(pattern: $0)) }
            + session.apps.map { AnyView(AppIcon(bundleID: $0.bundleID)) }
    }
}

/// One block in a stack of several: its list, its end, its time left, and its own actions.
private struct SessionRow: View {
    let session: Session
    let onLeave: () -> Void
    let onAddSite: () -> Void
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let now = controller.now
        HStack(spacing: Space.s) {
            if let label = session.label {
                ListBadge(symbol: label.symbol, color: label.color, size: 18)
            } else {
                Image(systemName: "lock.fill").frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("until \(Format.clockTime(session.endsAt, relativeTo: now))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.s)
            Text(Format.duration(session.endsAt.timeIntervalSince(now)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Menu {
                Button(session.rounds == nil ? "30 More Minutes" : "One More Round") { controller.extend(session.id, by: 30 * 60) }
                Button("Add a Site or App…", action: onAddSite)
                Divider()
                if session.earlyExit.wait != nil {
                    Button("Leave Early…", action: onLeave)
                } else {
                    Text("No way out of this block")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More for \(session.title)")
            .accessibilityLabel("Actions for \(session.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// "＋ Add": the ways a running block can get stricter.
private struct AddMenu: View {
    let session: Session
    let onAddSite: () -> Void
    let onAddList: () -> Void
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        Menu {
            if session.rounds == nil {
                Button("30 More Minutes") { controller.extend(session.id, by: 30 * 60) }
                Button("1 More Hour") { controller.extend(session.id, by: 3600) }
            } else {
                Button("One More Round") { controller.extend(session.id, by: 30 * 60) }
            }
            Divider()
            Button("A Site or App…", action: onAddSite)
            Button("Another List…", action: onAddList)
        } label: {
            Label("Add", systemImage: "plus")
        }
        .fixedSize()
        .help("Make this block stricter: more time, or more to block")
    }
}

/// Adding to a running block: the same search box as the list editor, minus the Undo.
private struct AddToBlock: View {
    let session: Session
    let done: () -> Void
    @EnvironmentObject private var controller: BlockController
    @State private var added: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(session.blocksWholeWeb ? "Every site is blocked already. Add an app or a category:" : "Add to \(session.title) until it ends:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AddSearch(placeholder: session.blocksWholeWeb ? "App or category" : "Site, app or category",
                      allowSites: !session.blocksWholeWeb, compact: true, onEscape: done) { result in
                switch result {
                case .site(let pattern):
                    if controller.add(site: pattern, to: session.id) { added.append(SiteRule(pattern)?.displayName ?? pattern) }
                case .app(let app):
                    controller.add(app: app, to: session.id)
                    added.append(app.name)
                case .group(let group):
                    controller.add(group: group, to: session.id)
                    added.append(group.title)
                }
            }
            HStack {
                if !added.isEmpty {
                    Label("Added \(Format.list(added))", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                // Esc is handled by the block view, so the menu's own Esc doesn't fight it.
                Button("Done", action: done)
            }
        }
    }
}

/// Before the wait starts: the deal, up front. Staying is the easy, big choice.
private struct LeaveExplainer: View {
    let session: Session
    let close: () -> Void
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let minutes = Int((session.earlyExit.wait ?? 0) / 60)
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Leaving early takes a \(minutes)-minute wait.")
                .font(.headline)
            Text("When it's over you'll have 2 minutes to end the block. Do nothing and it keeps going.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Button {
                    controller.requestUnlock(session.id)
                    close()
                } label: {
                    Text("Start the Wait").frame(maxWidth: .infinity)
                }
                Button(action: close) {
                    Text("Stay Locked").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// During the wait: a ring for how much is left. Staying is one tap, right under it.
private struct WaitPanel: View {
    let session: Session
    let remaining: TimeInterval
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let wait = session.earlyExit.wait ?? 1
        HStack(spacing: Space.m) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle().trim(from: 0, to: 1 - remaining / wait)
                    .stroke(Color.sea, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Format.countdown(remaining))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .frame(width: 44, height: 44)
            .accessibilityElement()
            .accessibilityLabel("\(Format.duration(remaining)) left to wait")
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting to leave early")
                    .font(.headline)
                Text("At \(Format.clockTime(controller.now + remaining, relativeTo: controller.now)) you'll get 2 minutes to end it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// The two minutes to decide.
private struct ReadyPanel: View {
    let session: Session
    let expiresIn: TimeInterval
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(Format.countdown(expiresIn)) to decide")
                .font(.headline.monospacedDigit())
            Text("End \(session.title) now, or stay until \(Format.clockTime(session.endsAt, relativeTo: controller.now)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: Space.s) {
                Button(role: .destructive) {
                    controller.confirmUnlock(session.id)
                } label: {
                    Text("End Now").frame(maxWidth: .infinity)
                }
                Button {
                    controller.cancelUnlock(session.id)
                } label: {
                    Text("Stay Locked").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
