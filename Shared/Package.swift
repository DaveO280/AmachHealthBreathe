// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AmachBreatheShared",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AmachBreatheShared", targets: ["AmachBreatheShared"]),
    ],
    targets: [
        .target(
            name: "AmachBreatheShared",
            path: "Sources/AmachBreatheShared"
        ),
        .testTarget(
            name: "AmachBreatheSharedTests",
            dependencies: ["AmachBreatheShared"],
            path: "Tests/AmachBreatheSharedTests"
        ),
    ]
)
