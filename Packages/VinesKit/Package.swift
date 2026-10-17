// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VinesKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "VinesKit", targets: ["VinesKit"]),
    ],
    targets: [
        .target(
            name: "VinesKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
