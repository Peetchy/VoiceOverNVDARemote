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
            dependencies: ["MacRemoteCore"]
        ),
        .executableTarget(
            name: "RelayProbe",
            dependencies: ["MacRemoteCore"]
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
