import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class RenderSessionTests: XCTestCase {
    func testSessionPreparesAccelerationBuffers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1)
        )

        XCTAssertEqual(session.metalRayTracingDebugInfo.supportsRayTracing, device.supportsRaytracing)
        XCTAssertEqual(session.accelerationInfo.requestedMode, .automatic)
        XCTAssertEqual(session.accelerationInfo.supportsMetalRayTracing, device.supportsRaytracing)

        if device.supportsRaytracing {
            XCTAssertEqual(session.accelerationInfo.activeMode, .metalRayTracing)
            XCTAssertTrue(session.accelerationInfo.hasMetalTLAS)
            XCTAssertFalse(session.accelerationInfo.hasFlatBVH)
            XCTAssertEqual(session.accelerationInfo.flatBVHNodeCount, 0)
            XCTAssertEqual(session.accelerationDebugInfo.nodeCount, 0)
            XCTAssertFalse(session.accelerationDebugInfo.hasNodeBuffer)
            XCTAssertFalse(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
            XCTAssertTrue(session.metalRayTracingDebugInfo.hasTLAS)
            XCTAssertTrue(session.metalRayTracingDebugInfo.hasSceneBuffers)
            XCTAssertTrue(session.metalRayTracingDebugInfo.usesProductionHardwareTraversal)
        } else {
            XCTAssertEqual(session.accelerationInfo.activeMode, .flatBVH)
            XCTAssertFalse(session.accelerationInfo.hasMetalTLAS)
            XCTAssertTrue(session.accelerationInfo.hasFlatBVH)
            XCTAssertGreaterThan(session.accelerationInfo.flatBVHNodeCount, 0)
            XCTAssertGreaterThan(session.accelerationDebugInfo.nodeCount, 0)
            XCTAssertTrue(session.accelerationDebugInfo.hasNodeBuffer)
            XCTAssertTrue(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
        }
    }

    func testForcedFlatBVHSessionPreparesFallbackAccelerationBuffers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        XCTAssertEqual(session.accelerationInfo.requestedMode, .flatBVH)
        XCTAssertEqual(session.accelerationInfo.activeMode, .flatBVH)
        XCTAssertEqual(session.accelerationInfo.supportsMetalRayTracing, device.supportsRaytracing)
        XCTAssertTrue(session.accelerationInfo.hasFlatBVH)
        XCTAssertGreaterThan(session.accelerationInfo.flatBVHNodeCount, 0)
        XCTAssertGreaterThan(session.accelerationDebugInfo.nodeCount, 0)
        XCTAssertTrue(session.accelerationDebugInfo.hasNodeBuffer)
        XCTAssertTrue(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
        XCTAssertFalse(session.metalRayTracingDebugInfo.usesProductionHardwareTraversal)
    }

    func testDeepFlatBVHRenderUsesEnergyPreservingTerminationPath() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 20, height: 20, maxBounces: 6),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let pixels = try session.pixels(for: .beauty)

        XCTAssertEqual(session.sampleCount, 1)
        XCTAssertTrue(pixels.contains { pixel in
            pixel.r.isFinite && pixel.g.isFinite && pixel.b.isFinite
                && (pixel.r > 0 || pixel.g > 0 || pixel.b > 0)
        })
    }

    func testSimpleSpatialDenoiserFiltersBeautyOutput() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = RenderScene.materialReference()
        let rawSession = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 32, height: 32, maxBounces: 2),
            accelerationMode: .flatBVH
        )
        let denoisedSession = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 32,
                height: 32,
                maxBounces: 2,
                denoise: DenoiseSettings(
                    denoiser: .simpleSpatial,
                    radius: 2,
                    normalSigma: 0.25,
                    depthSigma: 0.04,
                    albedoSigma: 0.35,
                    colorSigma: 8
                )
            ),
            accelerationMode: .flatBVH
        )

        XCTAssertEqual(denoisedSession.denoisingDebugInfo.requested, .simpleSpatial)
        XCTAssertTrue(denoisedSession.denoisingDebugInfo.hasSimpleSpatialPipeline)
        XCTAssertTrue(denoisedSession.denoisingDebugInfo.hasDenoisedBeautyTexture)

        try rawSession.renderNextSample()
        try denoisedSession.renderNextSample()

        let rawPixels = try rawSession.pixels(for: .beauty)
        let denoisedPixels = try denoisedSession.pixels(for: .beauty)

        XCTAssertEqual(rawPixels.count, denoisedPixels.count)
        XCTAssertTrue(denoisedPixels.allSatisfy { pixel in
            pixel.r.isFinite && pixel.g.isFinite && pixel.b.isFinite && pixel.a.isFinite
        })

        let averageDifference = zip(rawPixels, denoisedPixels).reduce(Float(0)) { partial, pair in
            partial
                + abs(pair.0.r - pair.1.r)
                + abs(pair.0.g - pair.1.g)
                + abs(pair.0.b - pair.1.b)
        } / Float(max(1, rawPixels.count * 3))
        XCTAssertGreaterThan(averageDifference, 0.000001)
    }

    func testAppleSVGFDenoiserFiltersBeautyOutput() throws {
        #if canImport(MetalPerformanceShaders)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = RenderScene.materialReference()
        let rawSession = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 32, height: 32, maxBounces: 2),
            accelerationMode: .flatBVH
        )
        let denoisedSession = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 32,
                height: 32,
                maxBounces: 2,
                denoise: .appleSVGF
            ),
            accelerationMode: .flatBVH
        )

        XCTAssertEqual(denoisedSession.denoisingDebugInfo.requested, .appleSVGF)
        XCTAssertTrue(denoisedSession.denoisingDebugInfo.hasAppleSVGFPipelines)
        XCTAssertTrue(denoisedSession.denoisingDebugInfo.hasDenoisedBeautyTexture)

        try rawSession.renderNextSample()
        try denoisedSession.renderNextSample()

        let rawPixels = try rawSession.pixels(for: .beauty)
        let denoisedPixels = try denoisedSession.pixels(for: .beauty)

        XCTAssertEqual(rawPixels.count, denoisedPixels.count)
        XCTAssertTrue(denoisedPixels.allSatisfy { pixel in
            pixel.r.isFinite && pixel.g.isFinite && pixel.b.isFinite && pixel.a.isFinite
        })

        let averageDifference = zip(rawPixels, denoisedPixels).reduce(Float(0)) { partial, pair in
            partial
                + abs(pair.0.r - pair.1.r)
                + abs(pair.0.g - pair.1.g)
                + abs(pair.0.b - pair.1.b)
        } / Float(max(1, rawPixels.count * 3))
        XCTAssertGreaterThan(averageDifference, 0.000001)
        #else
        throw XCTSkip("MetalPerformanceShaders is not available.")
        #endif
    }
}
