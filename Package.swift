// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MiMoMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MiMoMac", targets: ["MiMoMac"])
    ],
    targets: [
        .executableTarget(
            name: "MiMoMac",
            path: "Sources/MiMoMac"
        )
    ]
)
