// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MascotKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MascotKit", targets: ["MascotKit"]),
    ],
    targets: [
        .target(
            name: "MascotKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "MascotKitTests", dependencies: ["MascotKit"]),
    ],
    swiftLanguageModes: [.v6]
)
