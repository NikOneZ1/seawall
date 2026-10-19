// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Seawall",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (rules, timers, wording) — no AppKit, fully unit-tested.
        .target(name: "SeawallCore"),
        // The menu bar app itself.
        .executableTarget(name: "Seawall", dependencies: ["SeawallCore"]),
        .testTarget(name: "SeawallCoreTests", dependencies: ["SeawallCore"]),
    ],
    swiftLanguageModes: [.v5]
)
