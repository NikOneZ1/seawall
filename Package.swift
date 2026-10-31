// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Seawall",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (rules, timers, wording) — no AppKit, fully unit-tested.
        .target(name: "SeawallCore"),
        // The crash handler, in C so it only makes calls that are safe inside a signal handler.
        .target(name: "CrashCatcher"),
        // The menu bar app itself.
        .executableTarget(name: "Seawall", dependencies: ["SeawallCore", "CrashCatcher"]),
        .testTarget(name: "SeawallCoreTests", dependencies: ["SeawallCore"]),
    ],
    swiftLanguageModes: [.v5]
)
