// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PastePilot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PastePilot", targets: ["PastePilot"]),
        .executable(name: "PastePilotCLI", targets: ["PastePilotCLI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.11.1"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "PastePilot",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PastePilot",
            resources: [.copy("Resources/zh-Hans.lproj")]
        ),
        .target(
            name: "PastePilotCLIKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/PastePilotCLIKit"
        ),
        .executableTarget(
            name: "PastePilotCLI",
            dependencies: ["PastePilotCLIKit"],
            path: "Sources/PastePilotCLI"
        ),
        .testTarget(
            name: "PastePilotTests",
            dependencies: [
                "PastePilot",
                "PastePilotCLIKit",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/PastePilotTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
