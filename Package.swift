// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AILimiter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AILimiter", targets: ["AILimiter"])
    ],
    targets: [
        .executableTarget(
            name: "AILimiter",
            dependencies: []
        ),
        .testTarget(
            name: "AILimiterTests",
            dependencies: ["AILimiter"]
        ),
    ]
)
