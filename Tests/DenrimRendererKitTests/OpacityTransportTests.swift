import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class OpacityTransportTests: XCTestCase {
    func testFullyTransparentPrimarySurfaceRevealsRearSurfaceAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: cutoutScene(),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 2),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }

        XCTAssertTrue(albedo.contains { pixel in
            pixel.r < 0.1
                && pixel.g > 0.8
                && pixel.b < 0.1
                && pixel.a > 0.99
        })
        XCTAssertFalse(albedo.contains { pixel in
            pixel.r > 0.8
                && pixel.g < 0.1
                && pixel.b < 0.1
                && pixel.a < 0.01
        })
    }

    func testFullyTransparentPrimarySurfaceRevealsRearEmission() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: cutoutScene(),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 2),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let beauty = try session.pixels(for: .beauty)

        XCTAssertTrue(beauty.contains { pixel in
            pixel.g > 0.8 && pixel.r < 0.2 && pixel.b < 0.2
        })
    }

    private func cutoutScene() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                verticalFieldOfViewDegrees: 34
            )
        )
        let cutout = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 0, 0),
            roughness: 0.8,
            opacity: 0
        ))
        let rear = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0, 1, 0),
            emission: SIMD3<Float>(0, 1, 0),
            emissionStrength: 1,
            roughness: 0.8
        ))

        scene.add(mesh: .quad(
            SIMD3<Float>(-0.9, -0.9, 0),
            SIMD3<Float>(0.9, -0.9, 0),
            SIMD3<Float>(0.9, 0.9, 0),
            SIMD3<Float>(-0.9, 0.9, 0)
        ), material: cutout)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.9, -0.9, -0.25),
            SIMD3<Float>(0.9, -0.9, -0.25),
            SIMD3<Float>(0.9, 0.9, -0.25),
            SIMD3<Float>(-0.9, 0.9, -0.25)
        ), material: rear)

        return scene
    }
}
