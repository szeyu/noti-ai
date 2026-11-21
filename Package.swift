// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotiAI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "NotiAI", path: "Sources/NotiAI"),
    ]
)
