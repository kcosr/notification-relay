// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "notification-relay",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "notification-relay"
        ),
        .testTarget(name: "notification-relayTests", dependencies: ["notification-relay"]),
    ],
    swiftLanguageModes: [.v6]
)
