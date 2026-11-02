// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PingFlow",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PingFlowKit",
            path: "Sources/PingFlowKit",
            swiftSettings: [
                // Swift 5 mode: the app leans on AppKit's historically non-Sendable APIs
                // (NSStatusItem, NSViewRepresentable, CALayer). Correctness is enforced by
                // confining UI to the main actor and the tap to its own thread instead.
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "PingFlow",
            dependencies: ["PingFlowKit"],
            path: "Sources/PingFlow",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PingFlowTests",
            dependencies: ["PingFlowKit"],
            path: "Tests/PingFlowTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
