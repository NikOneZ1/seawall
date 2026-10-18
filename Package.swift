// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FocusLock",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (rules, timers, wording) — no AppKit, fully unit-tested.
        .target(name: "FocusLockCore"),
        // The menu bar app itself.
        .executableTarget(name: "FocusLock", dependencies: ["FocusLockCore"]),
        .testTarget(name: "FocusLockCoreTests", dependencies: ["FocusLockCore"]),
    ],
    swiftLanguageModes: [.v5]
)
