// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cooldown",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cooldown",
            path: "Sources/Cooldown"
        )
    ]
)
