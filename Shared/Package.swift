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
    dependencies: [
        .package(url: "https://github.com/privy-io/privy-ios", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "AmachBreatheShared",
            dependencies: [
                .product(name: "Privy", package: "privy-ios", condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/AmachBreatheShared"
        ),
        .testTarget(
            name: "AmachBreatheSharedTests",
            dependencies: ["AmachBreatheShared"],
            path: "Tests/AmachBreatheSharedTests"
        ),
    ]
)
