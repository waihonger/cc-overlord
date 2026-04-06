// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "cc-overlord",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "cc-overlord",
            path: "Sources"
        ),
    ]
)
