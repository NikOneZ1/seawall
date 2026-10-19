import SeawallCore
import SwiftUI

/// The menu while blocks run: each block's countdown, what it holds, and its way out (a wait,
/// or none at all). No stop button.
struct ActiveView: View {
    let onAdd: () -> Void
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The menu bar window sizes to the smallest height its content allows, and a
            // flexible ScrollView allows zero — so the list only scrolls, at a fixed height,
            // once there are more blocks than fit on a small screen.
            if controller.sessions.count <= 3 {
                sessionList
            } else {
                ScrollView { sessionList }
                    .frame(height: 480)
            }

            Divider().padding(.vertical, 14)

            HStack {
                QuietButton(title: "+  Lock something else", action: onAdd)
                Spacer()
                QuietButton(title: "Settings") { Panels.showSettings(controller: controller) }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(controller.sessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 {
                    Divider().padding(.vertical, 18)
                }
                SessionView(session: session)
            }
        }
    }
}

private struct SessionView: View {
    let session: Session
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        let now = controller.now

        let phase = session.phase(at: now)

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Deep.label(label(phase, now: now))
                CountdownText(seconds: (phase.map(Self.phaseEnd) ?? session.endsAt).timeIntervalSince(now))
                    .font(.system(size: 42, weight: .semibold))
                    .tracking(-1.2)
                    .shadow(color: Deep.depth.opacity(0.45), radius: 12, y: 1)
                HStack(spacing: 5) {
                    ForEach(session.groups) { GroupIcon(group: $0) }
                    ForEach(session.sites, id: \.self) { SiteIcon(pattern: $0) }
                    ForEach(session.apps, id: \.bundleID) { AppIcon(bundleID: $0.bundleID) }
                    if session.blocksOtherBrowsers, !InstalledBrowsers.unreadable.isEmpty { BrowsersIcon() }
                }
                .help(session.names)
                .padding(.top, 2)
            }

            ProgressHairline(value: progress(at: now))
                .padding(.vertical, 4)

            UnlockRow(session: session, state: session.unlockState(at: now))
        }
    }

    /// "until 18:00", or for a block in rounds "round 2 of 4 · until 10:50" and "break · round 3 at 10:55".
    private func label(_ phase: Phase?, now: Date) -> String {
        guard let phase, let rounds = session.rounds else {
            return "until \(Format.clockTime(session.endsAt, relativeTo: now))"
        }
        switch phase {
        case .locked(let round, let endsAt):
            return "round \(round) of \(rounds.count) · until \(Format.clockTime(endsAt, relativeTo: now))"
        case .resting(let next, let until):
            return "break · round \(next) at \(Format.clockTime(until, relativeTo: now))"
        }
    }

    private static func phaseEnd(_ phase: Phase) -> Date {
        switch phase {
        case .locked(_, let endsAt): endsAt
        case .resting(_, let until): until
        }
    }

    /// The whole block's progress, rounds and breaks included.
    private func progress(at now: Date) -> Double {
        let total = session.endsAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(session.startedAt) / total, 0), 1)
    }
}

/// Attempts while locked, then the way out once asked for.
private struct UnlockRow: View {
    let session: Session
    let state: UnlockState
    @EnvironmentObject private var controller: BlockController

    var body: some View {
        HStack(spacing: 14) {
            switch state {
            case .locked:
                Text(session.attempts == 0 ? "No attempts yet" : "\(Format.attempts(session.attempts)) caught")
                    .foregroundStyle(.secondary)
                Spacer()
                if let wait = session.earlyExit.wait {
                    QuietButton(title: "End early…") { controller.requestUnlock(session.id) }
                        .help("Ending this block early takes a \(Int(wait / 60))-minute wait")
                } else {
                    Text("No way out")
                        .foregroundStyle(.tertiary)
                        .help("This block was locked with no way to end it early")
                }

            case .waiting(let remaining):
                Text("Opens in \(Format.countdown(remaining)). Still want out?")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                QuietButton(title: "Stay") { controller.cancelUnlock(session.id) }

            case .ready(let expiresIn):
                Text("\(Format.countdown(expiresIn)) to decide")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                QuietButton(title: "Stay") { controller.cancelUnlock(session.id) }
                QuietButton(title: "End now", destructive: true) { controller.confirmUnlock(session.id) }
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}
