// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Stash",
            path: "Sources/Stash",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
