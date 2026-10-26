import Testing
@testable import SeawallCore

/// A generator that counts up, so a test can steer `randomElement`.
struct CountingGenerator: RandomNumberGenerator {
    var value: UInt64 = 0
    mutating func next() -> UInt64 {
        defer { value &+= UInt64.max / 7 }
        return value
    }
}

struct BlockedPageTests {
    static let concepts: [BlockedPageChoice] = [.breathe, .why, .stack]

    @Test func randomStaysWithinTheThree() {
        var generator = CountingGenerator()
        var seen = Set<BlockedPageChoice>()
        for _ in 0..<200 {
            let picked = BlockedPage.resolve(.random, using: &generator)
            #expect(Self.concepts.contains(picked))
            seen.insert(picked)
        }
        #expect(seen == Set(Self.concepts))
        #expect(BlockedPage.resolve(.random) != .all)
        #expect(BlockedPage.resolve(.random) != .random)
    }

    @Test func aFixedChoiceStaysPut() {
        for choice in BlockedPageChoice.allCases where choice != .random {
            #expect(BlockedPage.resolve(choice) == choice)
        }
    }

    @Test func eachChoiceHasItsOwnPage() {
        let pages = Self.concepts.map { BlockedPage.html(for: $0) }
        #expect(Set(pages).count == 3)
        #expect(BlockedPage.html(for: .breathe).contains(#"data-name="breathe""#))
        #expect(!BlockedPage.html(for: .breathe).contains(#"data-name="stack""#))
        #expect(BlockedPage.html(for: .why).contains(#"data-name="why""#))
        #expect(!BlockedPage.html(for: .why).contains(#"data-name="breathe""#))
        #expect(BlockedPage.html(for: .stack).contains(#"data-name="stack""#))
        #expect(!BlockedPage.html(for: .stack).contains(#"data-name="why""#))
    }

    @Test func randomServesOneOfTheThree() {
        var generator = CountingGenerator()
        let singles = Set(Self.concepts.map { BlockedPage.html(for: $0) })
        for _ in 0..<30 {
            #expect(singles.contains(BlockedPage.html(for: .random, using: &generator)))
        }
    }

    @Test func allTogetherHasTheSwitcherAndAllThree() {
        let page = BlockedPage.html(for: .all)
        #expect(page.contains(#"role="tablist""#))
        for name in ["breathe", "why", "stack"] {
            #expect(page.contains(#"data-name="\#(name)""#))
            #expect(page.contains(#"role="tab" data-name="\#(name)""#))
        }
        // The single pages carry no switcher.
        for choice in Self.concepts {
            #expect(!BlockedPage.html(for: choice).contains(#"role="tablist""#))
        }
    }

    @Test func noPageUsesFixedPositioningOrWater() {
        for choice in BlockedPageChoice.allCases {
            let page = BlockedPage.html(for: choice).lowercased()
            let squeezed = page.filter { !$0.isWhitespace }
            #expect(!squeezed.contains("position:fixed"), "\(choice)")
            #expect(!squeezed.contains("position:sticky"), "\(choice)")
            #expect(!page.contains("webgl"), "\(choice)")
            #expect(!page.contains("src=\"http"), "\(choice)")
            #expect(!page.contains("<link rel=\"stylesheet\""), "\(choice)")
        }
    }

    @Test func pagesPaintTheirBackgroundAndSupportBothAppearances() {
        for choice in BlockedPageChoice.allCases {
            let page = BlockedPage.html(for: choice)
            #expect(page.contains("html{background:var(--bg)"))
            #expect(page.contains("prefers-color-scheme:dark"))
            #expect(page.contains("prefers-reduced-motion"))
        }
    }

    @Test func choicesRoundTripThroughTheirStoredName() {
        for choice in BlockedPageChoice.allCases {
            #expect(BlockedPageChoice(rawValue: choice.rawValue) == choice)
        }
        #expect(BlockedPageChoice(rawValue: "water") == nil)
    }
}
