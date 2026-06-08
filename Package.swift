// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PastePilot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PastePilot", targets: ["PastePilot"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "PastePilot",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PastePilot",
            resources: [.copy("Resources/zh-Hans.lproj")]
        ),
        .testTarget(
            name: "PastePilotTests",
            dependencies: ["PastePilot"],
            path: "Tests/PastePilotTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
