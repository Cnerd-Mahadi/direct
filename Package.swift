// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Direct",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DirectCore"),
        .executableTarget(name: "Direct", dependencies: ["DirectCore"]),
        .testTarget(name: "DirectCoreTests", dependencies: ["DirectCore"]),
    ]
)
