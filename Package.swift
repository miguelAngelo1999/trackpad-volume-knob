// swift-tools-version: 6.0
// TrackpadVolumeKnob — lightweight macOS menu bar app
// Rotate two fingers on the trackpad to control system volume.
import PackageDescription

let package = Package(
    name: "TrackpadVolumeKnob",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "TrackpadVolumeKnob",
            targets: ["TrackpadVolumeKnobApp"]
        ),
        .library(
            name: "TrackpadVolumeKnobCore",
            targets: ["TrackpadVolumeKnobCore"]
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
            name: "TrackpadVolumeKnobApp",
            dependencies: [
                "TrackpadVolumeKnobCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "TrackpadVolumeKnob/App",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // All logic lives here — importable by tests
        .target(
            name: "TrackpadVolumeKnobCore",
            path: "TrackpadVolumeKnob/Sources",
            swiftSettings: [
                // Swift 5 language mode: relaxes strict concurrency checks while
                // keeping Swift 6 toolchain features. FlingEngine uses GCD timers
                // with DispatchQueue.main.async hops — safe by construction but
                // Swift 6 strict mode can't prove it statically.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "TrackpadVolumeKnobTests",
            dependencies: ["TrackpadVolumeKnobCore"],
            path: "TrackpadVolumeKnobTests"
        ),
        .executableTarget(
            name: "GestureTest",
            path: "GestureTest",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
