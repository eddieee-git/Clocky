// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clocky",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Clocky", path: "Sources/Clocky"),
        // Xcode 없이 Command Line Tools의 Swift Testing으로 돈다: swift test
        .testTarget(name: "ClockyTests", dependencies: ["Clocky"], path: "Tests/ClockyTests"),
    ]
)
