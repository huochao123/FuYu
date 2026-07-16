// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MiMoMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MiMoMac", targets: ["MiMoMac"])
    ],
    dependencies: [
        .package(path: "Vendor/DustyCleanerEngine")
    ],
    targets: [
        .executableTarget(
            name: "MiMoMac",
            dependencies: [
                .product(name: "CleanerEngine", package: "DustyCleanerEngine")
            ],
            path: "Sources/MiMoMac"
        )
    ]
)
