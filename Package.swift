// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Seawall",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates. The framework is copied into the app by scripts/build-app.sh.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // Pure logic (rules, timers, wording) — no AppKit, fully unit-tested.
        .target(name: "SeawallCore"),
        // The menu bar app itself.
        .executableTarget(
            name: "Seawall",
            dependencies: ["SeawallCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SeawallCoreTests", dependencies: ["SeawallCore"]),
    ],
    swiftLanguageModes: [.v5]
)
