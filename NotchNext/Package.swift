// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Atoll",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Atoll",
            dependencies: [],
            path: "Sources/Atoll",
            exclude: [
                "Features/Agents",
                "Features/AgentsUI",
                "Features/CalendarWidget/INTEGRATION.md",
                "Features/HUD/INTEGRATION.md",
                "Features/Media/INTEGRATION.md",
                "Features/Mirror/INTEGRATION.md",
                "Features/Notes/INTEGRATION.md",
                "Features/Shelf/INTEGRATION.md",
                "Features/ShortcutsRunner",
                "Features/SystemEvents/INTEGRATION.md",
                "Features/Timers/INTEGRATION.md",
                "Features/Todos/INTEGRATION.md"
            ],
            resources: [
                .copy("Resources/Adapters")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
