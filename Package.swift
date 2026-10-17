// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hyena",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Hyena", targets: ["Hyena"])],
    targets: [
        .target(name: "HyenaCore"),
        .executableTarget(name: "Hyena", dependencies: ["HyenaCore"]),
        .testTarget(name: "HyenaCoreTests", dependencies: ["HyenaCore"])
    ]
)
