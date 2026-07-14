// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RTXConfigMaker",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "RTXConfigMaker",
            path: "Sources/RTXConfigMaker"
        )
    ]
)
