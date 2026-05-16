// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HaYaku",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HaYaku", targets: ["HaYaku"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0")
    ],
    targets: [
        .executableTarget(
            name: "HaYaku",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/HaYaku",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
