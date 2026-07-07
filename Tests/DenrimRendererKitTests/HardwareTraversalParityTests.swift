import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class HardwareTraversalParityTests: XCTestCase {
    func testHardwareTraversalPrimaryAOVsMatchFlatBVH() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }
        guard device.supportsRaytracing else {
            throw XCTSkip("Metal ray tracing is not supported on this device.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = parityScene()
        let settings = RenderSettings(width: 16, height: 16, maxBounces: 1, quality: .final)

        let flatSession = try renderer.makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: .flatBVH
        )
        let hardwareSession = try renderer.makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: .metalRayTracing
        )

        try flatSession.renderNextSample()
        try hardwareSession.renderNextSample()

        XCTAssertFalse(flatSession.metalRayTracingDebugInfo.usesProductionHardwareTraversal)
        XCTAssertTrue(hardwareSession.metalRayTracingDebugInfo.usesProductionHardwareTraversal)
        assertPixelsMatch(
            try flatSession.pixels(for: .depth),
            try hardwareSession.pixels(for: .depth),
            tolerance: 0.0005
        )
        assertPixelsMatch(
            try flatSession.pixels(for: .normal),
            try hardwareSession.pixels(for: .normal),
            tolerance: 0.0005
        )
        assertPixelsMatch(
            try flatSession.pixels(for: .albedo),
            try hardwareSession.pixels(for: .albedo),
            tolerance: 0.0005
        )
    }

    func testHardwareTraversalReferenceSceneAOVsMatchFlatBVH() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }
        guard device.supportsRaytracing else {
            throw XCTSkip("Metal ray tracing is not supported on this device.")
        }

        let renderer = try DenrimRenderer(device: device)
        let cases: [(name: String, scene: RenderScene)] = [
            ("cornell", .cornellBox()),
            ("materials", .materialReference())
        ]

        for testCase in cases {
            let settings = RenderSettings(width: 24, height: 24, maxBounces: 1, quality: .final)
            let flatSession = try renderer.makeSession(
                scene: testCase.scene,
                settings: settings,
                accelerationMode: .flatBVH
            )
            let hardwareSession = try renderer.makeSession(
                scene: testCase.scene,
                settings: settings,
                accelerationMode: .metalRayTracing
            )

            try flatSession.renderNextSample()
            try hardwareSession.renderNextSample()

            for output in [RenderOutput.depth, .normal, .albedo, .materialID, .objectID] {
                assertPixelsMatch(
                    try flatSession.pixels(for: output),
                    try hardwareSession.pixels(for: output),
                    tolerance: 0.0005,
                    context: "\(testCase.name) \(output)"
                )
            }
        }
    }

    func testHardwareTraversalReusedMeshInstancesMatchFlatBVH() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }
        guard device.supportsRaytracing else {
            throw XCTSkip("Metal ray tracing is not supported on this device.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = reusedMeshInstanceScene()
        let settings = RenderSettings(width: 40, height: 40, maxBounces: 1)
        let flatSession = try renderer.makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: .flatBVH
        )
        let hardwareSession = try renderer.makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: .metalRayTracing
        )

        try flatSession.renderNextSample()
        try hardwareSession.renderNextSample()

        for output in [RenderOutput.depth, .normal, .albedo, .materialID, .objectID] {
            assertPixelsMatch(
                try flatSession.pixels(for: output),
                try hardwareSession.pixels(for: output),
                tolerance: 0.0005,
                context: "reused mesh instances \(output)"
            )
        }
    }

    func testHardwareTraversalBeautyMetricsMatchFlatBVH() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }
        guard device.supportsRaytracing else {
            throw XCTSkip("Metal ray tracing is not supported on this device.")
        }

        let renderer = try DenrimRenderer(device: device)
        let cases: [(name: String, scene: RenderScene)] = [
            ("cornell", .cornellBox()),
            ("materials", .materialReference())
        ]

        for testCase in cases {
            let settings = RenderSettings(width: 24, height: 24, maxBounces: 2)
            let flatSession = try renderer.makeSession(
                scene: testCase.scene,
                settings: settings,
                accelerationMode: .flatBVH
            )
            let hardwareSession = try renderer.makeSession(
                scene: testCase.scene,
                settings: settings,
                accelerationMode: .metalRayTracing
            )

            try flatSession.render(samples: 2)
            try hardwareSession.render(samples: 2)

            assertBeautyMetricsMatch(
                try flatSession.pixels(for: .beauty),
                try hardwareSession.pixels(for: .beauty),
                averageTolerance: 0.0005,
                maxTolerance: 0.02,
                context: testCase.name
            )
        }
    }

    private func parityScene() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 2),
                target: SIMD3<Float>(0, 0, 0),
                verticalFieldOfViewDegrees: 34
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.25, 0.5, 0.75)))
        scene.add(mesh: .quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ), material: material)
        return scene
    }

    private func reusedMeshInstanceScene() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0.7, 3.8),
                target: SIMD3<Float>(0, 0.35, 0),
                verticalFieldOfViewDegrees: 42
            )
        )
        let floor = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.45, 0.47, 0.48)))
        let red = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.2, 0.12)))
        let blue = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.16, 0.38, 0.9)))
        let green = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.8, 0.32)))
        let subject = Mesh.box(size: SIMD3<Float>(0.55, 0.7, 0.45))

        scene.add(mesh: .quad(
            SIMD3<Float>(-2.2, 0, 2.0),
            SIMD3<Float>(2.2, 0, 2.0),
            SIMD3<Float>(2.2, 0, -1.5),
            SIMD3<Float>(-2.2, 0, -1.5)
        ), material: floor)
        scene.add(
            mesh: subject,
            material: red,
            transform: Transform.translation(SIMD3<Float>(-0.8, 0.35, 0))
                * Transform.rotationY(radians: -0.25)
        )
        scene.add(
            mesh: subject,
            material: blue,
            transform: Transform.translation(SIMD3<Float>(0, 0.35, 0.02))
                * Transform.rotationY(radians: 0.12)
        )
        scene.add(
            mesh: subject,
            material: green,
            transform: Transform.translation(SIMD3<Float>(0.8, 0.35, -0.04))
                * Transform.rotationY(radians: 0.32)
        )
        return scene
    }

    private func assertPixelsMatch(
        _ lhs: [RenderOutputPixel],
        _ rhs: [RenderOutputPixel],
        tolerance: Float,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, context, file: file, line: line)
        for (index, pair) in zip(lhs, rhs).enumerated() {
            let (left, right) = pair
            XCTAssertEqual(left.r, right.r, accuracy: tolerance, "\(context) r[\(index)]", file: file, line: line)
            XCTAssertEqual(left.g, right.g, accuracy: tolerance, "\(context) g[\(index)]", file: file, line: line)
            XCTAssertEqual(left.b, right.b, accuracy: tolerance, "\(context) b[\(index)]", file: file, line: line)
            XCTAssertEqual(left.a, right.a, accuracy: tolerance, "\(context) a[\(index)]", file: file, line: line)
        }
    }

    private func assertBeautyMetricsMatch(
        _ lhs: [RenderOutputPixel],
        _ rhs: [RenderOutputPixel],
        averageTolerance: Float,
        maxTolerance: Float,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, context, file: file, line: line)
        var totalDifference: Float = 0
        var maxDifference: Float = 0
        var sampleCount: Float = 0

        for (left, right) in zip(lhs, rhs) {
            for difference in [
                abs(left.r - right.r),
                abs(left.g - right.g),
                abs(left.b - right.b)
            ] {
                totalDifference += difference
                maxDifference = max(maxDifference, difference)
                sampleCount += 1
            }
        }

        let averageDifference = totalDifference / max(1, sampleCount)
        XCTAssertLessThanOrEqual(
            averageDifference,
            averageTolerance,
            "\(context) average beauty difference",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            maxDifference,
            maxTolerance,
            "\(context) max beauty difference",
            file: file,
            line: line
        )
    }
}
