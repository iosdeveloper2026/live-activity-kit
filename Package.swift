// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveActivityKit",
    platforms: [.iOS(.v17)],
    products: [
        // App target: headless runtime, started with one line at launch.
        .library(name: "LiveActivityKit", targets: ["LiveActivityKit"]),
        // Widget extension target: Lock Screen and Dynamic Island layouts.
        .library(name: "LiveActivityKitWidget", targets: ["LiveActivityKitWidget"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", "12.19.2"..<"13.0.0"),
    ],
    targets: [
        .target(name: "LiveActivityKitShared", path: "ios/Sources/LiveActivityKitShared"),
        .target(
            name: "LiveActivityKit",
            dependencies: [
                "LiveActivityKitShared",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),
            ],
            path: "ios/Sources/LiveActivityKit"
        ),
        .target(name: "LiveActivityKitWidget", dependencies: ["LiveActivityKitShared"], path: "ios/Sources/LiveActivityKitWidget"),
    ]
)
