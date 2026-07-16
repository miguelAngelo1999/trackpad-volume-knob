// swift-tools-version: 6.0
// Mac Trackpad Fix — lightweight macOS menu bar app
// Use trackpad gestures (rotate, pinch) to control system volume and brightness.
import PackageDescription

let package = Package(
    name: "MacTrackpadFix",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacTrackpadFix",
            targets: ["MacTrackpadFixApp"]
        ),
        .library(
            name: "MacTrackpadFixCore",
            targets: ["MacTrackpadFixCore"]
        ),
        .executable(
            name: "GestureTest",
            targets: ["GestureTest"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Thin executable — just the entry point
        .executableTarget(
            name: "MacTrackpadFixApp",
            dependencies: [
                "MacTrackpadFixCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "MacTrackpadFix/App",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // All logic lives here — importable by tests
        .target(
            name: "MacTrackpadFixCore",
            path: "MacTrackpadFix/Sources",
            swiftSettings: [
                // Swift 5 language mode: relaxes strict concurrency checks while
                // keeping Swift 6 toolchain features. FlingEngine uses GCD timers
                // with DispatchQueue.main.async hops — safe by construction but
                // Swift 6 strict mode can't prove it statically.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MacTrackpadFixTests",
            dependencies: ["MacTrackpadFixCore"],
            path: "MacTrackpadFixTests"
        ),
        .executableTarget(
            name: "GestureTest",
            path: "GestureTest",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
