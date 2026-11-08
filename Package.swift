// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clocky",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Clocky", path: "Sources/Clocky")
    ]
)
