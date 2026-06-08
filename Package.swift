// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EnterpriseTelemetryLocationQA",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TelemetryLocationKit",
            targets: ["TelemetryLocationKit"]
        ),
        .executable(
            name: "TelemetryScenarioStudio",
            targets: ["TelemetryScenarioStudio"]
        ),
        .executable(
            name: "TelemetryQAConsole",
            targets: ["TelemetryQAConsole"]
        )
    ],
    targets: [
        .target(
            name: "TelemetryLocationKit"
        ),
        .executableTarget(
            name: "TelemetryScenarioStudio",
            dependencies: ["TelemetryLocationKit"]
        ),
        .executableTarget(
            name: "TelemetryQAConsole",
            dependencies: ["TelemetryLocationKit"]
        ),
        .testTarget(
            name: "TelemetryLocationKitTests",
            dependencies: ["TelemetryLocationKit"]
        )
    ]
)
