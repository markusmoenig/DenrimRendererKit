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

    func testAutomaticSessionRendersWithEmptyOptionalShaderResources() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1)
        )

        try session.renderNextSample()

        XCTAssertEqual(session.sampleCount, 1)
        let texture = session.liveMetalTexture(for: .beauty)
        XCTAssertEqual(texture.width, 16)
        XCTAssertEqual(texture.height, 16)
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

    func testVolumeOnlySceneRendersOnFlatPath() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.85, 0.18, 0.12), roughness: 0.7))
        scene.add(volume: DistanceVolume.sphere(resolution: 20, radius: 0.55), material: material)

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1),
            accelerationMode: .automatic
        )

        XCTAssertEqual(session.accelerationInfo.activeMode, RenderAccelerationMode.flatBVH)
        XCTAssertFalse(session.accelerationInfo.hasFlatBVH)

        try session.renderNextSample()
        let beauty = try session.pixels(for: RenderOutput.beauty)
        let albedo = try session.pixels(for: RenderOutput.albedo)
        let normal = try session.pixels(for: RenderOutput.normal)

        XCTAssertEqual(session.sampleCount, 1)
        let hasBeauty = beauty.contains { pixel in
            pixel.r.isFinite && pixel.g.isFinite && pixel.b.isFinite
                && (pixel.r > 0 || pixel.g > 0 || pixel.b > 0)
        }
        let hasVolumeAlbedo = albedo.contains { pixel in
            pixel.r > 0.5 && pixel.g < 0.3 && pixel.b < 0.25 && pixel.a > 0.9
        }
        let hasVolumeNormal = normal.contains { pixel in
            pixel.a > 0.9
                && (abs(pixel.r - 0.5) > 0.01
                    || abs(pixel.g - 0.5) > 0.01
                    || abs(pixel.b - 0.5) > 0.01)
        }
        XCTAssertTrue(hasBeauty)
        XCTAssertTrue(hasVolumeAlbedo)
        XCTAssertTrue(hasVolumeNormal)
    }

    func testVolumeMaterialFieldsOverrideAlbedoAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.05, 0.05), roughness: 0.7))
        var volume = DistanceVolume.sphere(resolution: 20, radius: 0.55)
        volume.materialSamples = [DistanceVolumeMaterialSample](
            repeating: DistanceVolumeMaterialSample(
                materialA: material,
                fields: DistanceVolumeMaterialFields(
                    baseColor: SIMD3<Float>(0.08, 0.82, 0.24),
                    opacity: 0.64
                )
            ),
            count: volume.distances.count
        )
        scene.add(volume: volume, material: material)

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        XCTAssertTrue(albedo.contains { pixel in
            pixel.r < 0.2 && pixel.g > 0.7 && pixel.b > 0.15 && pixel.b < 0.35 && pixel.a > 0.55 && pixel.a < 0.75
        })
    }

    func testSemanticVolumeAttributesDriveAlbedoAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let moss = scene.addMaterial(SemanticMaterial.moss(
            youngColor: SIMD3<Float>(0.9, 0.95, 0.12),
            matureColor: SIMD3<Float>(0.04, 0.34, 0.04),
            dryColor: SIMD3<Float>(0.52, 0.36, 0.12),
            age: 0,
            wetness: 0
        ))
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness),
            DistanceVolumeAttributeChannel(name: "mossAmount", semantic: .mossAmount),
            DistanceVolumeAttributeChannel(name: "cavity", semantic: .cavity)
        ])
        let model = SDFModel(
            primitives: [
                SDFPrimitive(
                    shape: .sphere(radius: 0.55),
                    material: moss,
                    attributes: DistanceVolumeAttributeValues([
                        "growthAge": 0.92,
                        "wetness": 0.8,
                        "mossAmount": 1,
                        "cavity": 0.35
                    ])
                )
            ],
            attributeLayout: layout
        )
        let volume = try DistanceVolumeBuilder.build(
            model: model,
            settings: DistanceVolumeBuildSettings(
                dimensions: SIMD3<Int>(20, 20, 20),
                boundsMin: SIMD3<Float>(-1, -1, -1),
                boundsMax: SIMD3<Float>(1, 1, 1)
            )
        )
        scene.add(volume: volume, material: moss)

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.08 && pixel.r < 0.45
                && pixel.g > 0.18 && pixel.g < 0.55
                && pixel.b < 0.12
                && pixel.a > 0.9
        })
    }

    func testSemanticSparseVolumeAttributesDriveAlbedoAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let moss = scene.addMaterial(SemanticMaterial.moss(
            youngColor: SIMD3<Float>(0.9, 0.95, 0.12),
            matureColor: SIMD3<Float>(0.04, 0.34, 0.04),
            dryColor: SIMD3<Float>(0.52, 0.36, 0.12),
            age: 0,
            wetness: 0
        ))
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness),
            DistanceVolumeAttributeChannel(name: "mossAmount", semantic: .mossAmount),
            DistanceVolumeAttributeChannel(name: "cavity", semantic: .cavity)
        ])
        let model = SDFModel(
            primitives: [
                SDFPrimitive(
                    shape: .sphere(radius: 0.55),
                    material: moss,
                    attributes: DistanceVolumeAttributeValues([
                        "growthAge": 0.92,
                        "wetness": 0.8,
                        "mossAmount": 1,
                        "cavity": 0.35
                    ])
                )
            ],
            attributeLayout: layout
        )
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 20, brickSize: 5, narrowBand: 0.3)
        )
        scene.add(sparseVolume: sparse, material: moss)

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.08 && pixel.r < 0.45
                && pixel.g > 0.18 && pixel.g < 0.55
                && pixel.b < 0.12
                && pixel.a > 0.9
        })
    }

    func testSparseVolumeOnlySceneRendersThroughBrickPathOnFlatPath() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9), roughness: 0.55))
        let model = SDFModel(primitives: [
            SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
        ])
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 20, brickSize: 5, narrowBand: 0.3)
        )
        scene.add(sparseVolume: sparse, material: material)

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1),
            accelerationMode: .automatic
        )

        XCTAssertEqual(session.accelerationInfo.activeMode, RenderAccelerationMode.flatBVH)
        XCTAssertFalse(session.accelerationInfo.hasFlatBVH)

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        XCTAssertEqual(session.sampleCount, 1)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r < 0.35 && pixel.g > 0.45 && pixel.b > 0.65 && pixel.a > 0.9
        })
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

    func testMetalTextureOutputExposesLiveAccumulationTexture() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 18, height: 14, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let texture = try session.metalTexture(for: .beauty)
        let liveTexture = session.liveMetalTexture(for: .beauty)

        XCTAssertEqual(session.sampleCount, 1)
        XCTAssertEqual(texture.width, 18)
        XCTAssertEqual(texture.height, 14)
        XCTAssertEqual(texture.pixelFormat, .rgba32Float)
        XCTAssertEqual(liveTexture.width, 18)
        XCTAssertEqual(liveTexture.height, 14)
        XCTAssertEqual(liveTexture.pixelFormat, .rgba32Float)
    }

    func testEncodeNextSampleUsesApplicationCommandBuffer() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 18, height: 14, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.encodeNextSample(into: commandBuffer)
        let liveTexture = session.liveMetalTexture(for: .beauty)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            XCTFail("Command buffer failed: \(error.localizedDescription)")
        }
        XCTAssertEqual(session.sampleCount, 1)
        XCTAssertEqual(liveTexture.width, 18)
        XCTAssertEqual(liveTexture.height, 14)

        let pixels = try session.pixels(for: .beauty)
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
