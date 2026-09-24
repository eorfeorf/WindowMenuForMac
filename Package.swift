// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowsMenuForMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WindowsMenuForMac", targets: ["WindowsMenuForMac"])],
    targets: [
        .target(name: "WindowMenuCore"),
        .executableTarget(name: "WindowsMenuForMac", dependencies: ["WindowMenuCore"]),
        .testTarget(name: "WindowMenuCoreTests", dependencies: ["WindowMenuCore"])
    ]
)
