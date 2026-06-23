// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CopyEmSearch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CopyEmSearch",
            path: "Sources/CopyEmSearch",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
