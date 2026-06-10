// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PRTracker", path: "Sources/PRTracker")
    ]
)
