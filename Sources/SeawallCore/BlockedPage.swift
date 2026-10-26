import Foundation

/// Which page a blocked tab lands on, as chosen in Settings.
public enum BlockedPageChoice: String, CaseIterable, Identifiable, Sendable {
    /// One of the three, picked again on every page load.
    case random
    case breathe
    case why
    case stack
    /// All three on one page, with a small switcher at the top.
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .random: "Random"
        case .breathe: "Breathe"
        case .why: "What brought you here"
        case .stack: "Stack"
        case .all: "All together"
        }
    }

    /// What it does, in a line.
    public var detail: String {
        switch self {
        case .random: "A different one each time a blocked page opens."
        case .breathe: "Follow one slow breath."
        case .why: "Name what brought you here and get a small thing to do instead."
        case .stack: "A 30-second game of stacking blocks."
        case .all: "All three on one page, with a switcher at the top."
        }
    }
}

/// The page a blocked tab lands on: flat, light and dark, one self-contained HTML document
/// with no external files. It reads `until` (unix seconds), `url` and `n` (tries in this block)
/// from its address and keeps its own small counters in the browser.
public enum BlockedPage {
    /// What Random picks from.
    public static let singles: [BlockedPageChoice] = [.breathe, .why, .stack]

    /// The page a choice means right now: Random becomes one of `singles`, the rest stay as they are.
    public static func resolve<G: RandomNumberGenerator>(_ choice: BlockedPageChoice, using generator: inout G) -> BlockedPageChoice {
        choice == .random ? (singles.randomElement(using: &generator) ?? .breathe) : choice
    }

    public static func resolve(_ choice: BlockedPageChoice) -> BlockedPageChoice {
        var generator = SystemRandomNumberGenerator()
        return resolve(choice, using: &generator)
    }

    public static func html(for choice: BlockedPageChoice) -> String {
        var generator = SystemRandomNumberGenerator()
        return html(for: choice, using: &generator)
    }

    public static func html<G: RandomNumberGenerator>(for choice: BlockedPageChoice, using generator: inout G) -> String {
        switch resolve(choice, using: &generator) {
        case .breathe: page([.breathe])
        case .why: page([.why])
        case .stack: page([.stack])
        default: page(singles)
        }
    }

    private static func page(_ concepts: [BlockedPageChoice]) -> String {
        let parts = BlockedPageParts.self
        func pieces(_ concept: BlockedPageChoice) -> (css: String, body: String, js: String) {
            switch concept {
            case .why: (parts.whyCSS, parts.whyBody, parts.whyJS)
            case .stack: (parts.stackCSS, parts.stackBody, parts.stackJS)
            default: (parts.breatheCSS, parts.breatheBody, parts.breatheJS)
            }
        }
        let used = concepts.map(pieces)
        let together = concepts.count > 1
        let switcher = together
            ? #"<div class="seg" id="seg" role="tablist" aria-label="Blocked page">"#
                + concepts.map { #"<button role="tab" data-name="\#($0.rawValue)" aria-selected="false">\#($0.title)</button>"# }.joined()
                + "</div>"
            : "<span></span>"
        let title = together ? "all" : (concepts.first?.rawValue ?? "breathe")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="color-scheme" content="light dark"><link rel="icon" href="data:,"><title>Blocked</title>
        <style>\(parts.shellCSS)\(used.map(\.css).joined())</style></head>
        <body data-page="\(title)">
        <header class="top"><div class="brand">\(parts.icon)<span>Seawall</span></div>\(switcher)<span class="pill" id="pill"></span></header>
        <main>
        \(used.map(\.body).joined(separator: "\n"))
        <section class="c" id="over" data-name="over" hidden><h1>Block is over</h1><p class="sub">You can go back now.</p><a class="btn open" id="openLink" hidden></a></section>
        </main>
        <footer class="foot" id="foot"></footer>
        <script>
        \(parts.shellJS)
        \(used.map(\.js).joined(separator: "\n"))
        SW.boot();
        </script></body></html>
        """
    }
}
