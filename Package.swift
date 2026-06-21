// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DenrimRendererKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DenrimRendererKit",
            targets: ["DenrimRendererKit"]
        ),
        .executable(
            name: "denrim-render-preview",
            targets: ["DenrimRenderPreview"]
        ),
        .executable(
            name: "denrim-render-benchmark",
            targets: ["DenrimRenderBenchmark"]
        )
    ],
    targets: [
        .target(
            name: "DenrimRendererKit",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "DenrimRenderPreview",
            dependencies: ["DenrimRendererKit"]
        ),
        .executableTarget(
            name: "DenrimRenderBenchmark",
            dependencies: ["DenrimRendererKit"]
        ),
        .testTarget(
            name: "DenrimRendererKitTests",
            dependencies: ["DenrimRendererKit"]
        ),
        .testTarget(
            name: "RenderReferenceTests",
            dependencies: ["DenrimRendererKit"],
            resources: [
                .process("ReferenceMetrics")
            ]
        )
    ]
)
