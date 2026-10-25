import SeawallCore
import SwiftUI

/// One box to add anything: type a few letters and matching categories, apps and sites
/// show up together. Return adds the first one.
struct AddSearch: View {
    enum Result: Hashable, Identifiable {
        case group(SiteGroup)
        case app(ListApp)
        case site(String)

        var id: String {
            switch self {
            case .group(let group): "group:\(group.rawValue)"
            case .app(let app): "app:\(app.bundleID)"
            case .site(let pattern): "site:\(pattern)"
            }
        }
    }

    let placeholder: String
    var allowGroups = true
    var allowApps = true
    var allowSites = true
    /// Smaller, for the menu.
    var compact = false
    /// Takes the keyboard when it appears.
    var autofocus = false
    /// Esc with nothing typed; with something typed, Esc clears it.
    var onEscape: (() -> Void)?
    let onPick: (Result) -> Void

    @ObservedObject private var installed = InstalledApps.shared
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = self.results
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                // The label is for VoiceOver only: shown in a form, it takes the left half and
                // pushes the text to the right.
                TextField(placeholder, text: $query, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .onSubmit { pick(at: highlighted) }
                    .onKeyPress(.escape) {
                        if !query.isEmpty {
                            query = ""
                            return .handled
                        }
                        guard let onEscape else { return .ignored }
                        onEscape()
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: compact ? 26 : 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            // Outlines drawn over controls must let clicks through, or they swallow them.
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(focused ? 0.25 : 0.1)).allowsHitTesting(false))

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button { pick(at: index) } label: {
                            row(result, highlighted: index == highlighted)
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = index } }
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(allowSites ? "Type a site like reddit.com, or the name of an app." : "No app or category by that name.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .onAppear {
            installed.load()
            focused = compact || autofocus
        }
        .onChange(of: query) { highlighted = 0 }
    }

    private func row(_ result: Result, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            switch result {
            case .group(let group):
                GroupIcon(group: group)
                Text(group.title)
                Spacer()
                Text("category").foregroundStyle(.secondary)
            case .app(let app):
                AppIcon(path: app.path)
                Text(app.name)
                Spacer()
                Text("app").foregroundStyle(.secondary)
            case .site(let pattern):
                SiteIcon(pattern: pattern)
                Text(pattern)
                Spacer()
                Text("site").foregroundStyle(.secondary)
            }
        }
        .font(compact ? .subheadline : .body)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: compact ? 24 : 26)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(highlighted ? Color.accentColor.opacity(0.2) : .clear))
        .contentShape(.rect)
    }

    /// Best match first, since Return takes it: a site typed out in full, a category by its
    /// name, apps, then known sites. A category that only mentions the text ("dis" in Video's
    /// Disney+) comes last, so it never beats Discord.
    private var results: [Result] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return [] }
        let groups = allowGroups ? SiteGroup.allCases.filter { $0 != .web } : []
        var results: [Result] = []

        // "reddit.com" as typed, once it looks like a whole address rather than "news.y" on the way to more.
        let typed = allowSites && text.contains(".") ? SiteRule(text) : nil
        let typedIsWhole = typed.map { ($0.host.split(separator: ".").last?.count ?? 0) >= 2 } ?? false
        if let typed, typedIsWhole { results.append(.site(typed.description)) }

        results += groups.filter { $0.title.lowercased().hasPrefix(text) }.map(Result.group)
        if allowApps {
            results += installed.matches(text, limit: 4).map(Result.app)
        }
        if allowSites {
            results += Self.knownSites
                .filter { $0.hasPrefix(text) || $0.contains(".\(text)") || (text.count >= 3 && $0.contains(text)) }
                .filter { $0 != typed?.description }
                .prefix(3)
                .map(Result.site)
            if let typed, !typedIsWhole { results.append(.site(typed.description)) }
        }
        if text.count >= 3 {
            results += groups
                .filter { !$0.title.lowercased().hasPrefix(text) && $0.summary.lowercased().contains(text) }
                .map(Result.group)
        }
        return Array(results.prefix(compact ? 5 : 7))
    }

    private func pick(at index: Int) {
        let results = self.results
        guard results.indices.contains(index) else { return }
        onPick(results[index])
        query = ""
        focused = true
    }

    /// Sites people often block, for suggestions as they type.
    static let knownSites: [String] = {
        var sites = ["youtube.com", "youtube.com/shorts", "instagram.com", "tiktok.com", "x.com", "reddit.com",
                     "facebook.com", "netflix.com", "twitch.tv", "news.ycombinator.com", "linkedin.com", "discord.com",
                     "pinterest.com", "threads.net", "bsky.app", "kick.com"]
        for group in SiteGroup.allCases {
            for site in group.sites where !sites.contains(site) { sites.append(site) }
        }
        return sites
    }()
}
