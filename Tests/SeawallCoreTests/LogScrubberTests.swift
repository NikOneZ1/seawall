import Foundation
import Testing
@testable import SeawallCore

struct LogScrubberTests {
    let plain = LogScrubber()

    @Test(arguments: [
        ("Opened https://www.reddit.com/r/swift?x=1#top in Safari", "Opened <url> in Safari"),
        ("http://127.0.0.1:47321/blocked?site=twitch.tv", "<url>"),
        ("seawall://lock?list=Evening&for=2h", "<url>"),
        ("file:///Users/nikita/Desktop/notes.txt", "<url>"),
        ("chrome-extension://abcdef/page.html", "<url>"),
        // Brackets can be part of an address, so the closing one goes with it.
        ("(see HTTPS://Example.COM/Path)", "(see <url>"),
    ])
    func urlsWithScheme(_ text: String, _ expected: String) {
        #expect(plain.scrub(text) == expected)
    }

    @Test(arguments: [
        ("Blocked reddit.com", "Blocked <domain>"),
        ("youtube.com/shorts is locked", "<domain> is locked"),
        ("m.twitch.tv:443 refused", "<domain> refused"),
        ("www.youtube.com/shorts/abc?x=1", "<domain>"),
        ("REDDIT.COM", "<domain>"),
        ("Closed com.valvesoftware.steam", "Closed <domain>"),
        ("Opened пример.рф", "Opened <domain>"),
        ("Open xn--e1afmkfd.xn--p1ai", "Open <domain>"),
        ("“Fortnite.app” is damaged", "“<domain>” is damaged"),
        ("site news.ycombinator.com, then bbc.co.uk.", "site <domain>, then <domain>."),
    ])
    func bareDomains(_ text: String, _ expected: String) {
        #expect(plain.scrub(text) == expected)
    }

    @Test(arguments: [
        ("connect to 192.168.1.20 failed", "connect to <ip> failed"),
        ("10.0.0.1:8080", "<ip>"),
        ("listening on ::1", "listening on <ip>"),
        ("peer fe80::1c2b:3aff:fe4d:5e6f", "peer <ip>"),
        ("[2001:db8::7]:443", "<ip>"),
        ("2001:0db8:85a3:0000:0000:8a2e:0370:7334", "<ip>"),
    ])
    func ipAddresses(_ text: String, _ expected: String) {
        #expect(plain.scrub(text) == expected)
    }

    @Test(arguments: [
        ("from nikita@example.com today", "from <email> today"),
        ("<first.last+tag@sub.mail.co>", "<<email>>"),
        ("mailto:hello@seawall.work", "mailto:<email>"),
    ])
    func emails(_ text: String, _ expected: String) {
        #expect(plain.scrub(text) == expected)
    }

    @Test func pathsUnderHomeLoseTheUserName() {
        let scrubber = LogScrubber(home: "/Users/nikita", userName: "nikita")
        #expect(scrubber.scrub("Can't write /Users/nikita/Library/Seawall/config.json") == "Can't write <path>")
        #expect(scrubber.scrub("in ~/Library/Logs") == "in <path>")
        #expect(scrubber.scrub("user nikita logged in") == "user <user> logged in")
        // A home folder with a space: the whole thing goes, and so does the rest after the space.
        let spaced = LogScrubber(home: "/Users/Nikita Verba", userName: "nikitaverba")
        #expect(spaced.scrub("/Users/Nikita Verba/Library/Application Support/Seawall/x.json") == "<path> <path>")
        #expect(!spaced.scrub("/Users/Nikita Verba/Desktop").contains("Nikita"))
    }

    @Test func otherPathsGoToo() {
        // App and folder names say what's installed and blocked.
        #expect(plain.scrub("Couldn't open /Applications/Steam.app/Contents") == "Couldn't open <path>")
        #expect(plain.scrub("/Volumes/Games/Fortnite") == "<path>")
        #expect(plain.scrub("Games/Fortnite Launcher") == "<path> Launcher")
    }

    @Test func secretsGoWhereverTheyAppear() {
        let scrubber = LogScrubber(secrets: ["Evening", "Steam", "News feed", "x"])
        #expect(scrubber.scrub("Locked Evening until 18:00") == "Locked <list item> until 18:00")
        #expect(scrubber.scrub("steam quit, STEAM again") == "<list item> quit, <list item> again")
        #expect(scrubber.scrub("News feed is on") == "<list item> is on")
        // Whole words only, and a one-letter secret is left alone.
        #expect(scrubber.scrub("Steamboat x") == "Steamboat x")
    }

    @Test func secretsComeFromListsAndBlocks() {
        let list = BlockList(name: "Late night", groups: [Toggled(.social)], sites: [Toggled("youtube.com/shorts")],
                             apps: [ListApp(bundleID: "com.example.game", name: "Space Game", path: "/Applications/Space Game.app")],
                             allowed: ["docs.example.org"])
        let secrets = LogScrubber.secrets(lists: [list], sessions: [], scheduleNames: ["Mornings"])
        for word in ["Late night", "youtube.com/shorts", "com.example.game", "Space Game", "docs.example.org", "Mornings", "Social"] {
            #expect(secrets.contains(word))
        }
        let scrubber = LogScrubber(secrets: secrets)
        #expect(scrubber.scrub("Closed Space Game during Late night") == "Closed <list item> during <list item>")
    }

    @Test(arguments: [
        "Seawall 0.1.0 (build 1) started",
        "Can't read config.json: The data couldn’t be read because it isn’t in the correct format.",
        "Safari read failed: -1743",
        "Block page server on 47321: Address already in use",
        "launchctl bootstrap exited with 5",
        "at 10:23:45 the tick ran",
        "3   libswiftCore.dylib   0x000000018f3c2e10 $ss17_assertionFailure + 244",
        "Signal: 5 (SIGTRAP)",
    ])
    func ordinaryLinesStay(_ text: String) {
        #expect(plain.scrub(text) == text)
    }

    @Test func prefersTooMuchOverTooLittle() {
        // Odd text that only looks like a domain still goes.
        #expect(plain.scrub("e.g. this") == "<domain>. this")
        #expect(plain.scrub("and/or") == "<path>")
    }

    @Test func nothingLeftOfAMixedLine() {
        let scrubber = LogScrubber(secrets: ["Work"], home: "/Users/sam", userName: "sam")
        let line = "Work: tab https://twitch.tv/x at 1.2.3.4 by sam@example.com saved /Users/sam/a.txt, also reddit.com"
        let scrubbed = scrubber.scrub(line)
        for leak in ["Work", "twitch", "1.2.3.4", "sam", "example", "reddit", "/Users"] {
            #expect(!scrubbed.contains(leak), "\(leak) left in \(scrubbed)")
        }
    }
}
