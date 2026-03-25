// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexAuthMacOSBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "CodexAuthMacOSBar", targets: ["CodexAuthMacOSBar"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexAuthMacOSBar",
            path: "Sources"
        ),
        .testTarget(
            name: "CodexAuthMacOSBarTests",
            dependencies: ["CodexAuthMacOSBar"],
            path: "Tests"
        ),
    ]
)
