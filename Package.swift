// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Seawall",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Updates. Only the app links it; SeawallCore stays free of AppKit and of Sparkle.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure logic (rules, timers, wording) — no AppKit, fully unit-tested.
        .target(name: "SeawallCore"),
        // The menu bar app itself.
        .executableTarget(
            name: "Seawall",
            dependencies: ["SeawallCore", .product(name: "Sparkle", package: "Sparkle")],
            // scripts/build-app.sh puts Sparkle.framework in Contents/Frameworks; this lets the
            // binary find it there. Unsafe flags are fine in a root package nobody depends on.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SeawallCoreTests", dependencies: ["SeawallCore"]),
    ],
    swiftLanguageModes: [.v5]
)
