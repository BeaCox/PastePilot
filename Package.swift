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
    targets: [
        .executableTarget(
            name: "PastePilot",
            path: "Sources/PastePilot",
            resources: [.copy("Resources/zh-Hans.lproj")]
        )
    ],
    swiftLanguageModes: [.v5]
)
