// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidKeeper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LidKeeper",
            path: "Sources/LidKeeper"
        )
    ]
)
