/// Browsers other than Safari. Only Safari tabs are filtered, so during a block these
/// are closed outright — otherwise the block is one Chrome launch away from useless.
public enum KnownBrowsers {
    public static let all: [BlockedApp] = [
        BlockedApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
        BlockedApp(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta"),
        BlockedApp(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary"),
        BlockedApp(bundleID: "org.chromium.Chromium", name: "Chromium"),
        BlockedApp(bundleID: "org.mozilla.firefox", name: "Firefox"),
        BlockedApp(bundleID: "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition"),
        BlockedApp(bundleID: "org.mozilla.nightly", name: "Firefox Nightly"),
        BlockedApp(bundleID: "company.thebrowser.Browser", name: "Arc"),
        BlockedApp(bundleID: "company.thebrowser.dia", name: "Dia"),
        BlockedApp(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        BlockedApp(bundleID: "com.brave.Browser", name: "Brave"),
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
