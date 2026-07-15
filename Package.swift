// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppleMusicDiscordRPC",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "apple-music-discord-rpc",
            targets: ["AppleMusicDiscordRPC"]
        )
    ],
    targets: [
        .target(
            name: "AppleMusicDiscordRPCCore"
        ),
        .executableTarget(
            name: "AppleMusicDiscordRPC",
            dependencies: ["AppleMusicDiscordRPCCore"]
        ),
        .testTarget(
            name: "AppleMusicDiscordRPCCoreTests",
            dependencies: ["AppleMusicDiscordRPCCore"]
        ),
    ]
)
