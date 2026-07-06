// swift-tools-version: 6.1

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
        ),
        .executable(
            name: "denrim",
            targets: ["DenrimCLI"]
        )
    ],
    targets: [
        .target(
            name: "DenrimRendererKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-no-whole-module-optimization",
                    "-enable-incremental-file-hashing",
                    "-enable-incremental-imports"
                ], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("MetalPerformanceShaders")
            ],
            plugins: [
                .plugin(name: "MetalLibraryPlugin")
            ]
        ),
        .executableTarget(
            name: "MetalLibraryGenerator",
            path: "Plugins/MetalLibraryGenerator"
        ),
        .plugin(
            name: "MetalLibraryPlugin",
            capability: .buildTool(),
            dependencies: ["MetalLibraryGenerator"],
            path: "Plugins/MetalLibraryPlugin"
        ),
        .executableTarget(
            name: "DenrimRenderPreview",
            dependencies: ["DenrimRendererKit"]
        ),
        .executableTarget(
            name: "DenrimRenderBenchmark",
            dependencies: ["DenrimRendererKit"]
        ),
        .executableTarget(
            name: "DenrimCLI",
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
