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
        .executableTarget(
            name: "DisplayMacServer",
            dependencies: [],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Network")
            ]
        )
    ]
)
