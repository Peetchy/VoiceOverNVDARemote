// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vo-nvda-remote",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "RemoteProtocol", targets: ["RemoteProtocol"]),
        .library(name: "MacRemoteCore", targets: ["MacRemoteCore"]),
        .library(name: "WindowsCompanionContract", targets: ["WindowsCompanionContract"]),
        .executable(name: "VONVDARemote", targets: ["VONVDARemote"]),
        .executable(name: "RelayProbe", targets: ["RelayProbe"]),
        .executable(name: "KeyCaptureProbe", targets: ["KeyCaptureProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.7.3"),
    ],
    targets: [
        .target(
            name: "RemoteProtocol"
        ),
        .target(
            name: "WindowsCompanionContract",
            dependencies: ["RemoteProtocol"]
        ),
        .target(
            name: "MacRemoteCore",
            dependencies: ["RemoteProtocol", "WindowsCompanionContract"]
        ),
        .executableTarget(
            name: "VONVDARemote",
            dependencies: [
                "MacRemoteCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "RelayProbe",
            dependencies: ["MacRemoteCore"]
        ),
        .executableTarget(
            name: "KeyCaptureProbe",
            dependencies: ["MacRemoteCore", "RemoteProtocol"]
        ),
        .testTarget(
            name: "RemoteProtocolTests",
            dependencies: ["RemoteProtocol"]
        ),
        .testTarget(
            name: "MacRemoteCoreTests",
            dependencies: ["MacRemoteCore", "RemoteProtocol", "WindowsCompanionContract"]
        ),
    ]
)
