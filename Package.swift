// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hummingbird-wallet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HummingbirdWalletPasses", targets: ["HummingbirdWalletPasses"]),
        .library(name: "HummingbirdWalletOrders", targets: ["HummingbirdWalletOrders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.7.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-fluent.git", from: "2.0.0"),
        .package(url: "https://github.com/fpseverino/fluent-wallet.git", from: "0.1.0"),
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "6.0.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.3"),
        // used in tests
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
    ],
    targets: [
        .target(
            name: "HummingbirdWallet",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdFluent", package: "hummingbird-fluent"),
                .product(name: "APNS", package: "apnswift"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: swiftSettings
        ),
        // MARK: - Wallet Passes
        .target(
            name: "HummingbirdWalletPasses",
            dependencies: [
                .target(name: "HummingbirdWallet"),
                .product(name: "FluentWalletPasses", package: "fluent-wallet"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HummingbirdWalletPassesTests",
            dependencies: [
                .target(name: "HummingbirdWalletPasses"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            resources: [
                .copy("SourceFiles")
            ],
            swiftSettings: swiftSettings
        ),
        // MARK: - Wallet Orders
        .target(
            name: "HummingbirdWalletOrders",
            dependencies: [
                .target(name: "HummingbirdWallet"),
                .product(name: "FluentWalletOrders", package: "fluent-wallet"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HummingbirdWalletOrdersTests",
            dependencies: [
                .target(name: "HummingbirdWalletOrders"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            resources: [
                .copy("SourceFiles")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny")
    ]
}
