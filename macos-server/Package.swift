// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayMacServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DisplayMacServer",
            targets: ["DisplayMacServer"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DisplayMacProtocol",
            dependencies: [],
            path: "Sources/DisplayMacProtocol"
        ),
        .executableTarget(
            name: "DisplayMacServer",
            dependencies: ["DisplayMacProtocol"],
            path: "Sources/DisplayMacServer",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Network"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "DisplayMacProtocolTests",
            dependencies: ["DisplayMacProtocol"],
            path: "Tests/DisplayMacProtocolTests"
        )
    ]
)
