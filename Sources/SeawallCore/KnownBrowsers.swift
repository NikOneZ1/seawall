/// The browsers Seawall knows about, in two kinds. Readable ones answer the same "what's in
/// your tabs" question Safari does, so a blocked tab gets the block page. The rest can't be
/// looked into, so "Other browsers" closes them during a block; otherwise the block would be
/// one Firefox launch away from useless.
public enum KnownBrowsers {
    public static let safari = BlockedApp(bundleID: "com.apple.Safari", name: "Safari")

    /// Safari, and the Chromium browsers that share Chrome's scripting.
    public static let readable: [BlockedApp] = [
        safari,
        BlockedApp(bundleID: "com.google.Chrome", name: "Chrome"),
        BlockedApp(bundleID: "company.thebrowser.Browser", name: "Arc"),
        BlockedApp(bundleID: "com.brave.Browser", name: "Brave"),
        BlockedApp(bundleID: "com.microsoft.edgemac", name: "Edge"),
    ]

    /// Closed outright by "Other browsers".
    public static let unreadable: [BlockedApp] = [
        BlockedApp(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta"),
        BlockedApp(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary"),
        BlockedApp(bundleID: "org.chromium.Chromium", name: "Chromium"),
        BlockedApp(bundleID: "org.mozilla.firefox", name: "Firefox"),
        BlockedApp(bundleID: "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition"),
        BlockedApp(bundleID: "org.mozilla.nightly", name: "Firefox Nightly"),
        BlockedApp(bundleID: "company.thebrowser.dia", name: "Dia"),
        BlockedApp(bundleID: "com.operasoftware.Opera", name: "Opera"),
        BlockedApp(bundleID: "com.operasoftware.OperaGX", name: "Opera GX"),
        BlockedApp(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        BlockedApp(bundleID: "ru.yandex.desktop.yandex-browser", name: "Yandex Browser"),
        BlockedApp(bundleID: "app.zen-browser.zen", name: "Zen"),
        BlockedApp(bundleID: "com.kagi.kagimacOS", name: "Orion"),
        BlockedApp(bundleID: "com.duckduckgo.macos.browser", name: "DuckDuckGo"),
        BlockedApp(bundleID: "org.torproject.torbrowser", name: "Tor Browser"),
        BlockedApp(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview"),
    ]
}
