// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidKeeper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LidKeeper",
            dependencies: ["LidKeeperArt"],
            path: "Sources/LidKeeper"
        ),
        // The logo, drawn in code: the app icon and the menu-bar glyph.
        .target(
            name: "LidKeeperArt",
            path: "Sources/LidKeeperArt"
        ),
        // Renders the app icon's .iconset for Scripts/make-app.sh.
        .executableTarget(
            name: "make-icon",
            dependencies: ["LidKeeperArt"],
            path: "Sources/make-icon"
        ),
    ]
)
