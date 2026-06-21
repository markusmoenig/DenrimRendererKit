import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class TextureMaterialTests: XCTestCase {
    func testBaseColorTextureFeedsAlbedoAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = texturedQuadScene(material: Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            roughness: 0.8,
            baseColorTexture: .checker(
                SIMD4<Float>(1, 0, 0, 1),
                SIMD4<Float>(0, 0, 1, 1)
            )
        ))
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }

        XCTAssertTrue(albedo.contains { $0.r > 0.9 && $0.g < 0.1 && $0.b < 0.1 })
        XCTAssertTrue(albedo.contains { $0.r < 0.1 && $0.g < 0.1 && $0.b > 0.9 })
    }

    func testNormalMapFeedsNormalAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = texturedQuadScene(material: Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            roughness: 0.8,
            normalMap: .solid(SIMD4<Float>(1, 0.5, 0.5, 1))
        ))
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let normals = try session.pixels(for: .normal).filter { $0.a > 0 }

        XCTAssertTrue(normals.contains { pixel in
            pixel.r > 0.9
                && pixel.g > 0.4 && pixel.g < 0.6
                && pixel.b > 0.4 && pixel.b < 0.6
        })
    }

    func testLinearTextureSamplingBlendsAlbedo() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let blended = Texture2D(
            width: 2,
            height: 2,
            pixels: [
                SIMD4<Float>(1, 0, 0, 1), SIMD4<Float>(0, 0, 1, 1),
                SIMD4<Float>(1, 0, 0, 1), SIMD4<Float>(0, 0, 1, 1)
            ],
            samplingMode: .linear
        )
        let scene = texturedQuadScene(material: Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            roughness: 0.8,
            baseColorTexture: blended
        ))
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 32, height: 32, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }

        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.25 && pixel.r < 0.75
                && pixel.g < 0.05
                && pixel.b > 0.25 && pixel.b < 0.75
        })
    }

    func testTexturedMaterialsMatchHardwareTraversalWhenAvailable() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }
        guard device.supportsRaytracing else {
            throw XCTSkip("Metal ray tracing is not supported on this device.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = texturedQuadScene(material: Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            roughness: 0.8,
            baseColorTexture: .checker(
                SIMD4<Float>(1, 0, 0, 1),
                SIMD4<Float>(0, 0, 1, 1)
            ),
            normalMap: .solid(SIMD4<Float>(1, 0.5, 0.5, 1))
        ))
        let settings = RenderSettings(width: 16, height: 16, maxBounces: 1)
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

        assertPixelsMatch(try flatSession.pixels(for: .albedo), try hardwareSession.pixels(for: .albedo))
        assertPixelsMatch(try flatSession.pixels(for: .normal), try hardwareSession.pixels(for: .normal))
    }

    private func texturedQuadScene(material: Material) -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                verticalFieldOfViewDegrees: 34
            )
        )
        let materialID = scene.addMaterial(material)
        scene.add(mesh: .quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ), material: materialID)
        return scene
    }

    private func assertPixelsMatch(
        _ lhs: [RenderOutputPixel],
        _ rhs: [RenderOutputPixel],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (index, pair) in zip(lhs, rhs).enumerated() {
            let (left, right) = pair
            XCTAssertEqual(left.r, right.r, accuracy: 0.0005, "r[\(index)]", file: file, line: line)
            XCTAssertEqual(left.g, right.g, accuracy: 0.0005, "g[\(index)]", file: file, line: line)
            XCTAssertEqual(left.b, right.b, accuracy: 0.0005, "b[\(index)]", file: file, line: line)
            XCTAssertEqual(left.a, right.a, accuracy: 0.0005, "a[\(index)]", file: file, line: line)
        }
    }
}
