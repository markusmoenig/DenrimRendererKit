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
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1, quality: .final)
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

    func testViewportRendersSpiralTilesBeforeCompletingSample() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let viewport = try renderer.makeViewport(
            scene: .cornellBox(),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 1, quality: .final)
        )

        let first = try viewport.renderNextTile(tileWidth: 16, tileHeight: 16)
        XCTAssertEqual(first.tile, RenderTile(x: 16, y: 16, width: 16, height: 16))
        XCTAssertEqual(first.tileIndex, 0)
        XCTAssertEqual(first.tileCount, 9)
        XCTAssertFalse(first.completedSample)
        XCTAssertEqual(viewport.sampleCount, 0)

        var latest = first
        for _ in 1..<9 {
            latest = try viewport.renderNextTile(tileWidth: 16, tileHeight: 16)
        }

        XCTAssertTrue(latest.completedSample)
        XCTAssertEqual(viewport.sampleCount, 1)

        let next = try viewport.renderNextTile(tileWidth: 16, tileHeight: 16)
        XCTAssertEqual(next.tileIndex, 0)
        XCTAssertEqual(next.tile, RenderTile(x: 16, y: 16, width: 16, height: 16))
        XCTAssertEqual(viewport.sampleCount, 1)
    }

    func testPreviewViewportTileCallRendersFullFrame() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let viewport = try renderer.makeViewport(
            scene: .cornellBox(),
            settings: RenderSettings(width: 48, height: 40, maxBounces: 1, quality: .preview)
        )

        let progress = try viewport.renderNextTile(tileWidth: 16, tileHeight: 16)

        XCTAssertEqual(progress.tile, RenderTile(x: 0, y: 0, width: 48, height: 40))
        XCTAssertEqual(progress.tileIndex, 0)
        XCTAssertEqual(progress.tileCount, 1)
        XCTAssertTrue(progress.completedSample)
        XCTAssertEqual(viewport.sampleCount, 1)
    }

    func testInteractiveViewportTileCallRendersFullFrame() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let viewport = try renderer.makeViewport(
            scene: .cornellBox(),
            settings: RenderSettings(width: 48, height: 40, maxBounces: 1, quality: .interactive)
        )

        let progress = try viewport.renderNextTile(tileWidth: 16, tileHeight: 16)

        XCTAssertEqual(progress.tile, RenderTile(x: 0, y: 0, width: 48, height: 40))
        XCTAssertEqual(progress.tileIndex, 0)
        XCTAssertEqual(progress.tileCount, 1)
        XCTAssertTrue(progress.completedSample)
        XCTAssertEqual(viewport.sampleCount, 1)
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

    func testRenderViewportRebuildsOnFieldReplacementAndRestartsAccumulation() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.38, 0.12), roughness: 0.86, specular: 0.2))
        let initialBundle = RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 12, radius: 0.5),
            fallbackMaterial: material
        )
        let fieldID = scene.add(fieldBundle: initialBundle)
        let renderer = try DenrimRenderer(device: device)
        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try viewport.renderNextSample()
        let previousSession = viewport.session

        let replacementBundle = RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 14, radius: 0.65),
            fallbackMaterial: material
        )
        let replaced = try viewport.replaceField(fieldID, with: replacementBundle)

        XCTAssertTrue(replaced)
        XCTAssertFalse(viewport.session === previousSession)
        XCTAssertEqual(viewport.sampleCount, 0)
        XCTAssertEqual(viewport.scene.volumeInstances[0].volume.dimensions, SIMD3<Int>(14, 14, 14))

        try viewport.renderNextSample()
        XCTAssertEqual(viewport.sampleCount, 1)
    }

    func testRenderViewportUpdatesCameraWithoutRebuildingSession() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.38, 0.12), roughness: 0.86, specular: 0.2))
        scene.add(fieldBundle: RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 12, radius: 0.5),
            fallbackMaterial: material
        ))
        let renderer = try DenrimRenderer(device: device)
        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try viewport.renderNextSample()
        let currentSession = viewport.session
        let updatedCamera = Camera(
            origin: SIMD3<Float>(0.25, 0.1, 3),
            target: SIMD3<Float>(0.25, 0.1, 0),
            projection: .orthographic(verticalScale: 1.8)
        )

        viewport.updateCamera(updatedCamera)

        XCTAssertTrue(viewport.session === currentSession)
        XCTAssertEqual(viewport.sampleCount, 0)
        XCTAssertEqual(viewport.scene.camera.origin, updatedCamera.origin)
        XCTAssertEqual(viewport.scene.camera.target, updatedCamera.target)
        XCTAssertEqual(viewport.session.camera.origin, updatedCamera.origin)
        XCTAssertEqual(viewport.session.previousCamera.origin, scene.camera.origin)

        try viewport.renderNextSample()
        XCTAssertEqual(viewport.sampleCount, 1)
    }

    func testRenderViewportKeepsCurrentSessionWhenFieldHandleIsInvalid() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.38, 0.12), roughness: 0.86, specular: 0.2))
        let fieldID = scene.add(fieldBundle: RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 12, radius: 0.5),
            fallbackMaterial: material
        ))
        XCTAssertEqual(fieldID.storage, .dense)

        let renderer = try DenrimRenderer(device: device)
        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )
        try viewport.renderNextSample()
        let currentSession = viewport.session

        let didReplace = try viewport.replaceField(
            RenderFieldID(storage: .sparse, index: 0),
            with: RenderFieldBundle(
                dense: DistanceVolume.sphere(resolution: 14, radius: 0.65),
                fallbackMaterial: material
            )
        )

        XCTAssertFalse(didReplace)
        XCTAssertTrue(viewport.session === currentSession)
        XCTAssertEqual(viewport.sampleCount, 1)
        XCTAssertEqual(viewport.scene.volumeInstances[0].volume.dimensions, SIMD3<Int>(12, 12, 12))
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

    func testVolumeMaterialFieldsDriveAlbedoAOV() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.75, 0.75, 0.75)))
        let fields = DistanceVolumeMaterialFields(baseColor: SIMD3<Float>(0.12, 0.42, 0.08), roughness: 0.86)
        let model = SDFModel(
            primitives: [
                SDFPrimitive(
                    shape: .sphere(radius: 0.55),
                    material: material,
                    materialFields: fields
                )
            ]
        )
        let volume = try DistanceVolumeBuilder.build(
            model: model,
            settings: DistanceVolumeBuildSettings(
                dimensions: SIMD3<Int>(20, 20, 20),
                boundsMin: SIMD3<Float>(-1, -1, -1),
                boundsMax: SIMD3<Float>(1, 1, 1)
            )
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
            pixel.r > 0.08 && pixel.r < 0.45
                && pixel.g > 0.18 && pixel.g < 0.55
                && pixel.b < 0.12
                && pixel.a > 0.9
        })
    }

    func testSparseVolumeMaterialFieldsDriveAlbedoAOV() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.75, 0.75, 0.75)))
        let fields = DistanceVolumeMaterialFields(baseColor: SIMD3<Float>(0.12, 0.42, 0.08), roughness: 0.86)
        let model = SDFModel(
            primitives: [
                SDFPrimitive(
                    shape: .sphere(radius: 0.55),
                    material: material,
                    materialFields: fields
                )
            ]
        )
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

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.08 && pixel.r < 0.45
                && pixel.g > 0.18 && pixel.g < 0.55
                && pixel.b < 0.12
                && pixel.a > 0.9
        })
    }

    func testGPUResidentProgramCustomAttributesReachAttributeBuffer() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let material = MaterialID(rawValue: 0)
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge"),
            DistanceVolumeAttributeChannel(name: "wetness")
        ])
        let program = DistanceFieldProgram(
            instructions: [
                .loadPosition(.init(0)),
                .length(.init(0), .init(0)),
                .setFloat(.init(1), 0.55),
                .subtractFloat(.init(2), .init(0), .init(1)),
                .setFloat(.init(3), 0.7),
                .writeAttribute(channel: 0, value: .init(3)),
                .setFloat(.init(4), 0.25),
                .writeAttribute(channel: 1, value: .init(4)),
                .emit(distance: .init(2), material: material)
            ],
            attributeLayout: layout
        )

        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.3),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )

        guard case .gpuSparse(let resource) = result.bundle.storage else {
            return XCTFail("Expected GPU-resident sparse storage.")
        }
        let metadata = try XCTUnwrap(resource.metadataBuffers)
        let attributeSampleBuffer = try XCTUnwrap(resource.attributeSampleBuffer)
        let descriptors = metadata.attributeDescriptorBuffer.contents().bindMemory(
            to: GPUVolumeAttributeDescriptor.self,
            capacity: metadata.attributeDescriptorCount
        )
        let samples = attributeSampleBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: max(resource.attributeSampleCount, 1)
        )

        var foundAttributeSample = false
        for descriptorIndex in 0..<metadata.attributeDescriptorCount {
            let descriptor = descriptors[descriptorIndex]
            let offset = Int(descriptor.metadata.x)
            let packedVectorCount = Int(descriptor.metadata.y)
            let sampleCount = Int(descriptor.metadata.z)
            guard packedVectorCount > 0,
                  sampleCount > 0,
                  offset < resource.attributeSampleCount else {
                continue
            }
            XCTAssertEqual(descriptor.reserved0, SIMD4<UInt32>(repeating: 0))
            XCTAssertEqual(samples[offset].x, 0.7, accuracy: 0.0001)
            XCTAssertEqual(samples[offset].y, 0.25, accuracy: 0.0001)
            foundAttributeSample = true
            break
        }
        XCTAssertTrue(foundAttributeSample)
    }

    func testGPUResidentProgramMaterialFieldsReachResidentBuffer() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let material = MaterialID(rawValue: 0)
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .length(.init(0), .init(0)),
            .setFloat(.init(1), 0.55),
            .subtractFloat(.init(2), .init(0), .init(1)),
            .setVector(.init(1), SIMD3<Float>(0.18, 0.42, 0.11)),
            .writeMaterialFieldVector(.baseColor, vector: .init(1)),
            .setFloat(.init(3), 0.73),
            .writeMaterialField(.roughness, scalar: .init(3)),
            .setFloat(.init(4), 0.36),
            .writeMaterialField(.specular, scalar: .init(4)),
            .emit(distance: .init(2), material: material)
        ])

        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.3),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )

        guard case .gpuSparse(let resource) = result.bundle.storage else {
            return XCTFail("Expected GPU-resident sparse storage.")
        }
        let materialFieldSampleBuffer = try XCTUnwrap(resource.materialFieldSampleBuffer)
        XCTAssertEqual(resource.materialFieldSampleCount, resource.sampleCount)

        let samples = materialFieldSampleBuffer.contents().bindMemory(
            to: GPUVolumeMaterialFieldSample.self,
            capacity: max(resource.materialFieldSampleCount, 1)
        )

        let expectedFlags = DistanceVolumeMaterialFields.baseColorFlag
            | DistanceVolumeMaterialFields.roughnessFlag
            | DistanceVolumeMaterialFields.specularFlag
        var foundFieldSample = false
        for sampleIndex in 0..<resource.materialFieldSampleCount {
            let sample = samples[sampleIndex]
            guard sample.materialFieldFlags.x == expectedFlags else {
                continue
            }
            XCTAssertEqual(sample.baseColorOpacity.x, 0.18, accuracy: 0.0001)
            XCTAssertEqual(sample.baseColorOpacity.y, 0.42, accuracy: 0.0001)
            XCTAssertEqual(sample.baseColorOpacity.z, 0.11, accuracy: 0.0001)
            XCTAssertEqual(sample.surface.x, 0.73, accuracy: 0.0001)
            XCTAssertEqual(sample.surface.z, 0.36, accuracy: 0.0001)
            foundFieldSample = true
            break
        }
        XCTAssertTrue(foundFieldSample)
    }

    func testFieldBundleMaterialProgramReachesVolumeDescriptor() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.75, 0.75, 0.75)))
        let volume = DistanceVolume.sphere(resolution: 8, radius: 0.5)
        let materialProgram = DistanceFieldMaterialProgram(instructions: [
            .loadVectorInput(.init(0), .localPosition),
            .extractY(.init(0), .init(0)),
            .writeMask(.a, .init(0)),
            .readMask(.a, .init(1)),
            .writeMaterialField(.roughness, scalar: .init(1))
        ])

        scene.add(fieldBundle: RenderFieldBundle(
            dense: volume,
            fallbackMaterial: material,
            materialProgram: materialProgram
        ))

        let compilation = try scene.compileForGPU()

        XCTAssertEqual(compilation.volumeMaterialPrograms, [materialProgram])
        XCTAssertEqual(compilation.volumes.first?.materialProgram.x, 0)
    }

    func testFieldBundleMaterialProgramOverridesSDFAlbedoAtHitTime() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.75, 0.75, 0.75)))
        let materialProgram = DistanceFieldMaterialProgram(instructions: [
            .setVector(.init(0), SIMD3<Float>(0.12, 0.42, 0.08)),
            .writeMaterialFieldVector(.baseColor, vector: .init(0)),
            .setFloat(.init(0), 0.91),
            .writeMaterialField(.roughness, scalar: .init(0))
        ])
        scene.add(fieldBundle: RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 16, radius: 0.55),
            fallbackMaterial: material,
            materialProgram: materialProgram
        ))

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1, quality: .preview),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        let foundOverride = albedo.contains { pixel in
            let redMatches = pixel.r > 0.08 && pixel.r < 0.2
            let greenMatches = pixel.g > 0.34 && pixel.g < 0.5
            let blueMatches = pixel.b > 0.04 && pixel.b < 0.14
            return redMatches && greenMatches && blueMatches && pixel.a > 0.9
        }
        XCTAssertTrue(foundOverride)
    }

    func testFieldBundleMaterialProgramRunsSharedMathSetAtHitTime() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.75, 0.75, 0.75)))
        let materialProgram = DistanceFieldMaterialProgram(instructions: [
            .setFloat(.init(0), -0.5),
            .negateFloat(.init(1), .init(0)),
            .absFloat(.init(2), .init(0)),
            .setFloat(.init(3), 0),
            .sinFloat(.init(4), .init(3)),
            .cosFloat(.init(5), .init(3)),
            .setFloat(.init(6), 0.6),
            .minFloat(.init(7), .init(5), .init(6)),
            .maxFloat(.init(8), .init(4), .init(3)),
            .setFloat(.init(9), 0.42),
            .addFloat(.init(10), .init(8), .init(9)),
            .setFloat(.init(11), 0),
            .setFloat(.init(12), 1),
            .clampFloat(.init(13), .init(10), .init(11), .init(12)),
            .mixFloat(.init(14), .init(2), .init(7), .init(3)),
            .composeVector(.init(0), x: .init(1), y: .init(14), z: .init(13)),
            .setVector(.init(1), SIMD3<Float>(0.1, 0.2, 0.3)),
            .setVector(.init(2), SIMD3<Float>(0.4, 0.4, 0.12)),
            .addVector(.init(3), .init(1), .init(2)),
            .subtractVector(.init(4), .init(3), .init(1)),
            .absVector(.init(5), .init(4)),
            .setFloat(.init(15), 0.5),
            .multiplyVectorFloat(.init(6), .init(5), .init(15)),
            .maxVectorFloat(.init(7), .init(6), .init(9)),
            .minVectorFloat(.init(8), .init(7), .init(12)),
            .length(.init(16), .init(8)),
            .boxDistance(.init(17), position: .init(8), halfExtents: .init(2), cornerRadius: .init(3)),
            .cylinderDistance(.init(18), position: .init(8), radius: .init(15), halfHeight: .init(12)),
            .taperedCapsuleDistance(.init(19), position: .init(8), start: .init(1), end: .init(2), startRadius: .init(15), endRadius: .init(12)),
            .splineTubeDistance(.init(20), position: .init(8), control0: .init(1), control1: .init(2), control2: .init(3), control3: .init(4), startRadius: .init(15), endRadius: .init(12)),
            .writeMaterialFieldVector(.baseColor, vector: .init(3))
        ])
        scene.add(fieldBundle: RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 16, radius: 0.55),
            fallbackMaterial: material,
            materialProgram: materialProgram
        ))

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1, quality: .preview),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        let foundSharedMathColor = albedo.contains { pixel in
            let redMatches = pixel.r > 0.46 && pixel.r < 0.54
            let greenMatches = pixel.g > 0.56 && pixel.g < 0.64
            let blueMatches = pixel.b > 0.38 && pixel.b < 0.46
            return redMatches && greenMatches && blueMatches && pixel.a > 0.9
        }
        XCTAssertTrue(foundSharedMathColor)
    }

    func testFieldBundleMaterialProgramRunsProceduralNoiseAtHitTime() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.75, 0.75, 0.75)))
        let materialProgram = DistanceFieldMaterialProgram(instructions: [
            .setVector(.init(0), SIMD3<Float>(0.37, 0.59, 0.23)),
            .setFloat(.init(0), 3),
            .setFloat(.init(1), 7),
            .setFloat(.init(2), 4),
            .setFloat(.init(3), 2),
            .setFloat(.init(4), 0.5),
            .valueNoise3D(.init(5), position: .init(0), scale: .init(0), seed: .init(1)),
            .fbm3D(.init(6), position: .init(0), scale: .init(0), octaves: .init(2), lacunarity: .init(3), gain: .init(4), seed: .init(1)),
            .cellular3D(distance: .init(7), secondDistance: .init(8), cellID: .init(9), position: .init(0), scale: .init(0), seed: .init(1)),
            .saturate(.init(10), .init(5)),
            .saturate(.init(11), .init(6)),
            .saturate(.init(12), .init(9)),
            .composeVector(.init(1), x: .init(10), y: .init(11), z: .init(12)),
            .writeMaterialFieldVector(.baseColor, vector: .init(1))
        ])
        scene.add(fieldBundle: RenderFieldBundle(
            dense: DistanceVolume.sphere(resolution: 16, radius: 0.55),
            fallbackMaterial: material,
            materialProgram: materialProgram
        ))

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1, quality: .preview),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        let foundProceduralColor = albedo.contains { pixel in
            let insideUnitRange = pixel.r > 0.02 && pixel.r < 0.98
                && pixel.g > 0.02 && pixel.g < 0.98
                && pixel.b > 0.02 && pixel.b < 0.98
            let differsFromFallback = abs(pixel.r - 0.75) > 0.05
                || abs(pixel.g - 0.75) > 0.05
                || abs(pixel.b - 0.75) > 0.05
            return insideUnitRange && differsFromFallback && pixel.a > 0.9
        }
        XCTAssertTrue(foundProceduralColor)
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
            settings: RenderSettings(
                width: 20,
                height: 20,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        XCTAssertEqual(session.accelerationInfo.activeMode, RenderAccelerationMode.flatBVH)
        XCTAssertFalse(session.accelerationInfo.hasFlatBVH)

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        XCTAssertEqual(session.sampleCount, 1)
        let stats = session.sdfTraversalStats()
        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickTests, 0)
        XCTAssertGreaterThanOrEqual(stats.sparseGridCellsVisited, stats.sparseGridEmptyCells + stats.sparseBrickTests)
        XCTAssertGreaterThan(stats.sparseBrickMarches, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarchSteps, 0)
        XCTAssertGreaterThan(stats.sparseBrickHits, 0)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r < 0.35 && pixel.g > 0.45 && pixel.b > 0.65 && pixel.a > 0.9
        })

        session.resetSDFTraversalStats()
        XCTAssertEqual(session.sdfTraversalStats(), .zero)
    }

    func testSparseBrickWithoutZeroCrossingIsCulledBeforeMarch() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.0)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.2, 0.2)))
        let sample = DistanceVolumeMaterialSample(materialA: material)
        let distances = Array(repeating: Float(0.05), count: 27)
        let sparse = SparseDistanceVolume(
            dimensions: SIMD3<Int>(3, 3, 3),
            brickSize: SIMD3<Int>(3, 3, 3),
            boundsMin: SIMD3<Float>(-1, -1, -1),
            boundsMax: SIMD3<Float>(1, 1, 1),
            defaultDistance: 1,
            defaultMaterial: sample,
            bricks: [
                SparseDistanceVolumeBrick(
                    origin: SIMD3<Int>(0, 0, 0),
                    dimensions: SIMD3<Int>(3, 3, 3),
                    coreOrigin: SIMD3<Int>(0, 0, 0),
                    coreDimensions: SIMD3<Int>(3, 3, 3),
                    distances: distances,
                    materialSamples: Array(repeating: sample, count: distances.count)
                )
            ]
        )
        scene.add(sparseVolume: sparse, material: material)

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 8,
                height: 8,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        try session.renderNextSample()

        let stats = session.sdfTraversalStats()
        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickTests, 0)
        XCTAssertGreaterThanOrEqual(stats.sparseGridCellsVisited, stats.sparseGridEmptyCells + stats.sparseBrickTests)
        XCTAssertGreaterThan(stats.sparseBrickRangeCulls, 0)
        XCTAssertEqual(stats.sparseBrickMarches, 0)
        XCTAssertEqual(stats.sparseBrickMarchSteps, 0)
        XCTAssertEqual(stats.sparseBrickHits, 0)
    }

    func testGPUResidentSparseVolumeOnlySceneRendersThroughBrickPath() throws {
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
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
            ]),
            resolution: 20,
            storage: .sparseBricks(brickSize: 5, narrowBand: 0.3),
            fallbackMaterial: material
        ))
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 20,
                height: 20,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        let stats = session.sdfTraversalStats()
        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickTests, 0)
        XCTAssertGreaterThanOrEqual(stats.sparseGridCellsVisited, stats.sparseGridEmptyCells + stats.sparseBrickTests)
        XCTAssertGreaterThan(stats.sparseBrickMarches, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarchSteps, 0)
        XCTAssertGreaterThan(stats.sparseBrickHits, 0)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r < 0.35 && pixel.g > 0.45 && pixel.b > 0.65 && pixel.a > 0.9
        })
    }

    func testDirectGridGPUResidentSparseVolumeOnlySceneRendersThroughBrickPath() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2), roughness: 0.55))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
                ]),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.3),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 20,
                height: 20,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)

        let stats = session.sdfTraversalStats()
        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickTests, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarches, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarchSteps, 0)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.65 && pixel.g > 0.25 && pixel.g < 0.65 && pixel.b < 0.45 && pixel.a > 0.9
        })
    }

    func testSparseBrickQualityMetricsStayCloseToHigherDensityReference() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let preview = try renderSparseBrickQualityProbe(
            renderer: renderer,
            resolution: 28,
            quality: .preview,
            sampleScale: 1
        )
        let low = try renderSparseBrickQualityProbe(
            renderer: renderer,
            resolution: 28,
            quality: .final,
            sampleScale: 2
        )
        let reference = try renderSparseBrickQualityProbe(
            renderer: renderer,
            resolution: 64,
            quality: .final,
            sampleScale: 1
        )

        let metrics = primaryAOVDifferenceMetrics(
            lhsNormal: low.normal,
            lhsDepth: low.depth,
            rhsNormal: reference.normal,
            rhsDepth: reference.depth
        )
        let previewMetrics = primaryAOVDifferenceMetrics(
            lhsNormal: preview.normal,
            lhsDepth: preview.depth,
            rhsNormal: reference.normal,
            rhsDepth: reference.depth
        )

        XCTAssertGreaterThan(metrics.coverage, 0.20)
        XCTAssertLessThan(metrics.normalRMSE, previewMetrics.normalRMSE - 0.004)
        XCTAssertLessThan(metrics.normalRMSE, 0.30)
        XCTAssertLessThan(metrics.depthRMSE, 0.05)
        XCTAssertLessThan(metrics.silhouetteMismatchRatio, 0.02)
    }

    func testDirectGridGPUResidentSparseVolumeUsesMacroGridSkips() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0.6, 0, 3),
                target: SIMD3<Float>(0.6, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2), roughness: 0.55))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(
                        shape: .sphere(radius: 0.35),
                        material: material,
                        transform: .translation(SIMD3<Float>(0.6, 0, 0))
                    )
                ]),
                resolution: 48,
                boundsMin: SIMD3<Float>(-1.5, -1.5, -1.5),
                boundsMax: SIMD3<Float>(1.5, 1.5, 1.5),
                storage: .sparseBricks(brickSize: 4, narrowBand: 0.18),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 32,
                height: 32,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        try session.renderNextSample()

        let stats = session.sdfTraversalStats()
        XCTAssertGreaterThan(stats.sparseGridMacroSkips, 0)
        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickTests, 0)
    }

    func testDirectGridGPUResidentSparseVolumeClearGlassTransmitsRearEmission() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.2)
            )
        )
        let glass = scene.addMaterial(try XCTUnwrap(BuiltInMaterialLibrary.material(named: "glass.clear")))
        let rear = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.1, 1.0, 0.2),
            emission: SIMD3<Float>(0.1, 1.0, 0.2),
            emissionStrength: 2.0,
            roughness: 0.6
        ))
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.9, -0.9, -0.7),
            SIMD3<Float>(0.9, -0.9, -0.7),
            SIMD3<Float>(0.9, 0.9, -0.7),
            SIMD3<Float>(-0.9, 0.9, -0.7)
        ), material: rear)

        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.5), material: glass)
                ]),
                resolution: 24,
                storage: .sparseBricks(brickSize: 6, narrowBand: 0.35),
                fallbackMaterial: glass
            ),
            metadataMode: .directGridGPU
        )
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 6,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        for _ in 0..<8 {
            try session.renderNextSample()
        }

        let beauty = try session.pixels(for: RenderOutput.beauty)
        let centerWindow = beauty.enumerated().compactMap { index, pixel -> RenderOutputPixel? in
            let x = index % 24
            let y = index / 24
            return x >= 9 && x <= 14 && y >= 9 && y <= 14 ? pixel : nil
        }
        let brightestGreen = centerWindow.map { $0.g }.max() ?? 0
        let luminanceValues = centerWindow.map { pixel -> Float in
            (pixel.r + pixel.g + pixel.b) / 3
        }
        let darkestLuminance = luminanceValues.min() ?? 0
        let stats = session.sdfTraversalStats()

        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarches, 0)
        XCTAssertGreaterThan(brightestGreen, 0.35)
        XCTAssertGreaterThan(darkestLuminance, 0.02)
    }

    func testDirectGridGPUResidentSparseVolumeClearGlassSeesEnvironmentWithTransparentBackground() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.2)
            ),
            environment: Environment(intensity: 2.5, maxRadiance: 8)
        )
        let glass = scene.addMaterial(try XCTUnwrap(BuiltInMaterialLibrary.material(named: "glass.clear")))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.5), material: glass)
                ]),
                resolution: 24,
                storage: .sparseBricks(brickSize: 6, narrowBand: 0.35),
                fallbackMaterial: glass
            ),
            metadataMode: .directGridGPU
        )
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 6,
                transparentBackground: true,
                sampleRadianceClamp: 0,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        for _ in 0..<8 {
            try session.renderNextSample()
        }

        let beauty = try session.pixels(for: RenderOutput.beauty)
        let centerWindow = beauty.enumerated().compactMap { index, pixel -> RenderOutputPixel? in
            let x = index % 24
            let y = index / 24
            return x >= 10 && x <= 13 && y >= 10 && y <= 13 ? pixel : nil
        }
        let centerLuminance = centerWindow.map { pixel -> Float in
            (pixel.r + pixel.g + pixel.b) / 3
        }.max() ?? 0
        let corner = beauty[0]

        XCTAssertGreaterThan(session.sdfTraversalStats().sparseBrickMarches, 0)
        XCTAssertGreaterThan(centerLuminance, 0.08)
        XCTAssertGreaterThan(centerWindow.map { $0.a }.max() ?? 0, 0.9)
        XCTAssertLessThan(corner.a, 0.05)
    }

    func testDirectGridGPUResidentSparseVolumeClearGlassSeesHiddenEnvironmentWithOpaqueBackground() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.2)
            ),
            environment: Environment(intensity: 2.5, maxRadiance: 8)
        )
        let glass = scene.addMaterial(try XCTUnwrap(BuiltInMaterialLibrary.material(named: "glass.clear")))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.5), material: glass)
                ]),
                resolution: 24,
                storage: .sparseBricks(brickSize: 6, narrowBand: 0.35),
                fallbackMaterial: glass
            ),
            metadataMode: .directGridGPU
        )
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 6,
                showsEnvironmentBackground: false,
                sampleRadianceClamp: 0,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        for _ in 0..<8 {
            try session.renderNextSample()
        }

        let beauty = try session.pixels(for: RenderOutput.beauty)
        let centerWindow = beauty.enumerated().compactMap { index, pixel -> RenderOutputPixel? in
            let x = index % 24
            let y = index / 24
            return x >= 10 && x <= 13 && y >= 10 && y <= 13 ? pixel : nil
        }
        let centerLuminance = centerWindow.map { pixel -> Float in
            (pixel.r + pixel.g + pixel.b) / 3
        }.max() ?? 0
        let corner = beauty[0]

        XCTAssertGreaterThan(session.sdfTraversalStats().sparseBrickMarches, 0)
        XCTAssertGreaterThan(centerLuminance, 0.08)
        XCTAssertGreaterThan(centerWindow.map { $0.a }.max() ?? 0, 0.9)
        XCTAssertGreaterThan(corner.a, 0.99)
        XCTAssertEqual(corner.r, 0, accuracy: 0.0001)
        XCTAssertEqual(corner.g, 0, accuracy: 0.0001)
        XCTAssertEqual(corner.b, 0, accuracy: 0.0001)
    }

    func testDirectGridGPUResidentProgramRendersThroughBrickPath() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2), roughness: 0.55))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .extractX(.init(0), .init(0)),
            .extractY(.init(1), .init(0)),
            .extractZ(.init(2), .init(0)),
            .setFloat(.init(3), 2.2),
            .multiplyFloat(.init(4), .init(1), .init(3)),
            .negateFloat(.init(4), .init(4)),
            .cosFloat(.init(5), .init(4)),
            .sinFloat(.init(6), .init(4)),
            .multiplyFloat(.init(7), .init(5), .init(0)),
            .multiplyFloat(.init(8), .init(6), .init(2)),
            .subtractFloat(.init(9), .init(7), .init(8)),
            .multiplyFloat(.init(10), .init(6), .init(0)),
            .multiplyFloat(.init(11), .init(5), .init(2)),
            .addFloat(.init(12), .init(10), .init(11)),
            .composeVector(.init(1), .init(9), .init(1), .init(12)),
            .setVector(.init(2), SIMD3<Float>(0.52, 0.2, 0.28)),
            .setFloat(.init(13), 0.05),
            .boxDistance(.init(14), position: .init(1), halfExtents: .init(2), cornerRadius: .init(13)),
            .emit(distance: .init(14), material: material)
        ])
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 22,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.28),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        scene.add(fieldBundle: result.bundle)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)
        let stats = session.sdfTraversalStats()

        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickTests, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarches, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarchSteps, 0)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.65 && pixel.g > 0.25 && pixel.g < 0.65 && pixel.b < 0.45 && pixel.a > 0.9
        })
    }

    func testDirectGridGPUResidentSparseVolumeRendersWithTransformAndNonzeroVolumeIndex() throws {
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
        let hiddenMaterial = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.05, 0.05, 0.05), roughness: 0.55))
        scene.add(
            volume: DistanceVolume.sphere(resolution: 8, radius: 0.2),
            material: hiddenMaterial,
            transform: .translation(SIMD3<Float>(3, 0, 0))
        )

        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2), roughness: 0.55))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
                ]),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.3),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        scene.add(
            fieldBundle: result.bundle,
            transform: .translation(SIMD3<Float>(0.22, 0, 0)) * .scale(SIMD3<Float>(0.85, 1.05, 0.9))
        )

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 1,
                collectsSDFTraversalStats: true
            ),
            accelerationMode: .automatic
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo)
        let stats = session.sdfTraversalStats()

        XCTAssertGreaterThan(stats.sparseGridCellsVisited, 0)
        XCTAssertGreaterThan(stats.sparseBrickMarches, 0)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.65 && pixel.g > 0.25 && pixel.g < 0.65 && pixel.b < 0.45 && pixel.a > 0.9
        })
    }

    func testViewportDirtyBrickUpdateKeepsGPUResidentSession() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
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
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
            ]),
            resolution: 20,
            storage: .sparseBricks(brickSize: 5, narrowBand: 0.3),
            fallbackMaterial: material
        ))
        let fieldID = scene.add(fieldBundle: result.bundle)
        let resource = scene.gpuSparseVolumeInstances[0].resource
        let brick = try XCTUnwrap(resource.bricks.first)
        let byteCount = brick.sampleCount * RenderGPUSparseFieldResource.packedSampleStride
        guard let source = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw XCTSkip("Could not allocate dirty brick source buffer.")
        }
        memcpy(
            source.contents(),
            resource.sampleBuffer.contents().advanced(by: brick.sampleOffset * RenderGPUSparseFieldResource.packedSampleStride),
            byteCount
        )

        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1)
        )
        try viewport.renderNextSample()
        let originalSession = viewport.session
        XCTAssertEqual(viewport.sampleCount, 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw XCTSkip("Could not create dirty brick command buffer.")
        }
        let updated = try viewport.encodeUpdateGPUSparseFieldBricks(
            fieldID,
            updates: [
                RenderGPUSparseFieldBrickUpdate(
                    brickIndex: 0,
                    sourceBuffer: source,
                    sampleCount: brick.sampleCount
                )
            ],
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        XCTAssertTrue(updated)
        XCTAssertTrue(viewport.session === originalSession)
        XCTAssertEqual(viewport.sampleCount, 0)
        try viewport.renderNextSample()
        XCTAssertEqual(viewport.sampleCount, 1)
    }

    func testViewportProgramDirtyBoundsUpdateKeepsSessionAndUpdatesAttributes() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.38, 0.12), roughness: 0.86, specular: 0.2))
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge"),
            DistanceVolumeAttributeChannel(name: "wetness")
        ])
        func program(growthAge: Float, wetness: Float) -> DistanceFieldProgram {
            DistanceFieldProgram(
                instructions: [
                    .loadPosition(.init(0)),
                    .length(.init(0), .init(0)),
                    .setFloat(.init(1), 0.55),
                    .subtractFloat(.init(2), .init(0), .init(1)),
                    .setFloat(.init(3), growthAge),
                    .writeAttribute(channel: 0, value: .init(3)),
                    .setFloat(.init(4), wetness),
                    .writeAttribute(channel: 1, value: .init(4)),
                    .emit(distance: .init(2), material: material)
                ],
                attributeLayout: layout
            )
        }

        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program(growthAge: 0.2, wetness: 0.1)),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.28),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        let fieldID = scene.add(fieldBundle: result.bundle)
        let resource = scene.gpuSparseVolumeInstances[0].resource
        let dirtyBrickIndices = try resource.directGridBrickIndices(
            overlappingLocalBoundsMin: SIMD3<Float>(repeating: -0.1),
            localBoundsMax: SIMD3<Float>(repeating: 0.1),
            activeOnly: true
        )
        let dirtyBrickIndex = try XCTUnwrap(dirtyBrickIndices.first)

        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1)
        )
        try viewport.renderNextSample()
        let originalSession = viewport.session
        XCTAssertEqual(viewport.sampleCount, 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw XCTSkip("Could not create dirty program command buffer.")
        }
        let updated = try viewport.encodeUpdateGPUResidentProgramBricks(
            fieldID,
            baker: baker,
            program: program(growthAge: 0.85, wetness: 0.65),
            overlappingLocalBoundsMin: SIMD3<Float>(repeating: -0.1),
            localBoundsMax: SIMD3<Float>(repeating: 0.1),
            activeOnly: true,
            narrowBand: 0.28,
            fallbackMaterial: material,
            updatesTopology: false,
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        XCTAssertTrue(updated)
        XCTAssertTrue(viewport.session === originalSession)
        XCTAssertEqual(viewport.sampleCount, 0)

        let updatedResource = viewport.scene.gpuSparseVolumeInstances[0].resource
        let metadata = try XCTUnwrap(updatedResource.metadataBuffers)
        let attributeSampleBuffer = try XCTUnwrap(updatedResource.attributeSampleBuffer)
        let descriptors = metadata.attributeDescriptorBuffer.contents().bindMemory(
            to: GPUVolumeAttributeDescriptor.self,
            capacity: metadata.attributeDescriptorCount
        )
        let descriptor = descriptors[dirtyBrickIndex]
        let samples = attributeSampleBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: max(updatedResource.attributeSampleCount, 1)
        )
        let attributeSampleIndex = Int(descriptor.metadata.x)
        XCTAssertLessThan(attributeSampleIndex, updatedResource.attributeSampleCount)
        XCTAssertEqual(samples[attributeSampleIndex].x, 0.85, accuracy: 0.00001)
        XCTAssertEqual(samples[attributeSampleIndex].y, 0.65, accuracy: 0.00001)
    }

    func testViewportProgramDirtyWorldBoundsUseFieldTransform() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device available.")
        }

        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                projection: .orthographic(verticalScale: 2.4)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.38, 0.12), roughness: 0.86, specular: 0.2))
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge"),
            DistanceVolumeAttributeChannel(name: "wetness")
        ])
        func program(growthAge: Float, wetness: Float) -> DistanceFieldProgram {
            DistanceFieldProgram(
                instructions: [
                    .loadPosition(.init(0)),
                    .length(.init(0), .init(0)),
                    .setFloat(.init(1), 0.55),
                    .subtractFloat(.init(2), .init(0), .init(1)),
                    .setFloat(.init(3), growthAge),
                    .writeAttribute(channel: 0, value: .init(3)),
                    .setFloat(.init(4), wetness),
                    .writeAttribute(channel: 1, value: .init(4)),
                    .emit(distance: .init(2), material: material)
                ],
                attributeLayout: layout
            )
        }

        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program(growthAge: 0.2, wetness: 0.1)),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.28),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        let transform = Transform.translation(SIMD3<Float>(0.35, 0.2, 0))
            * Transform.scale(SIMD3<Float>(repeating: 2))
        let fieldID = scene.add(fieldBundle: result.bundle, transform: transform)
        let resource = scene.gpuSparseVolumeInstances[0].resource
        let dirtyBrickIndex = try XCTUnwrap(try resource.directGridBrickIndices(
            overlappingLocalBoundsMin: SIMD3<Float>(repeating: -0.1),
            localBoundsMax: SIMD3<Float>(repeating: 0.1),
            activeOnly: true
        ).first)

        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 20, height: 20, maxBounces: 1)
        )
        try viewport.renderNextSample()
        let originalSession = viewport.session

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw XCTSkip("Could not create dirty program command buffer.")
        }
        let updated = try viewport.encodeUpdateGPUResidentProgramBricks(
            fieldID,
            baker: baker,
            program: program(growthAge: 0.9, wetness: 0.7),
            overlappingWorldBoundsMin: SIMD3<Float>(0.25, 0.1, -0.2),
            worldBoundsMax: SIMD3<Float>(0.45, 0.3, 0.2),
            padding: 0.02,
            activeOnly: true,
            narrowBand: 0.28,
            fallbackMaterial: material,
            updatesTopology: false,
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        XCTAssertTrue(updated)
        XCTAssertTrue(viewport.session === originalSession)
        XCTAssertEqual(viewport.sampleCount, 0)

        let updatedResource = viewport.scene.gpuSparseVolumeInstances[0].resource
        let metadata = try XCTUnwrap(updatedResource.metadataBuffers)
        let attributeSampleBuffer = try XCTUnwrap(updatedResource.attributeSampleBuffer)
        let descriptors = metadata.attributeDescriptorBuffer.contents().bindMemory(
            to: GPUVolumeAttributeDescriptor.self,
            capacity: metadata.attributeDescriptorCount
        )
        let descriptor = descriptors[dirtyBrickIndex]
        let samples = attributeSampleBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: max(updatedResource.attributeSampleCount, 1)
        )
        let attributeSampleIndex = Int(descriptor.metadata.x)
        XCTAssertLessThan(attributeSampleIndex, updatedResource.attributeSampleCount)
        XCTAssertEqual(samples[attributeSampleIndex].x, 0.9, accuracy: 0.00001)
        XCTAssertEqual(samples[attributeSampleIndex].y, 0.7, accuracy: 0.00001)
    }

    func testViewportGPUSparseTopologyReplacementKeepsSession() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.55, 0.2), roughness: 0.5))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let initial = try baker.bakeGPUResident(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(
                    shape: .box(halfExtents: SIMD3<Float>(0.55, 0.35, 0.35), cornerRadius: 0.12),
                    material: material
                )
            ]),
            resolution: 26,
            storage: .sparseBricks(brickSize: 5, narrowBand: 0.22),
            fallbackMaterial: material
        ))
        let fieldID = scene.add(fieldBundle: initial.bundle)
        let initialResource = scene.gpuSparseVolumeInstances[0].resource
        let updated = try baker.bakeGPUResident(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.35), material: material)
            ]),
            resolution: 18,
            storage: .sparseBricks(brickSize: 6, narrowBand: 0.24),
            fallbackMaterial: material
        ), reusing: initialResource)
        guard case .gpuSparse(let updatedResource) = updated.bundle.storage else {
            return XCTFail("Expected GPU sparse field storage.")
        }
        XCTAssertTrue(updatedResource.sampleBuffer === initialResource.sampleBuffer)
        XCTAssertGreaterThanOrEqual(initialResource.sampleCapacity, updatedResource.sampleCount)

        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1)
        )
        try viewport.renderNextSample()
        let originalSession = viewport.session
        let originalSDFResources = viewport.session.sdfResourceDebugInfo
        XCTAssertEqual(viewport.sampleCount, 1)

        let replaced = try viewport.replaceGPUSparseFieldPreservingSession(fieldID, with: updated.bundle)
        let replacedSDFResources = viewport.session.sdfResourceDebugInfo

        XCTAssertTrue(replaced)
        XCTAssertTrue(viewport.session === originalSession)
        XCTAssertTrue(replacedSDFResources.volumeBuffer === originalSDFResources.volumeBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickBuffer === originalSDFResources.volumeBrickBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickAttributeDescriptorBuffer === originalSDFResources.volumeBrickAttributeDescriptorBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickGridBuffer === originalSDFResources.volumeBrickGridBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickGridIndexBuffer === originalSDFResources.volumeBrickGridIndexBuffer)
        XCTAssertLessThanOrEqual(replacedSDFResources.volumeBrickCount, originalSDFResources.volumeBrickCount)
        XCTAssertLessThanOrEqual(replacedSDFResources.volumeBrickGridIndexCount, originalSDFResources.volumeBrickGridIndexCount)
        XCTAssertEqual(viewport.sampleCount, 0)
        XCTAssertEqual(viewport.scene.gpuSparseVolumeInstances[0].resource.dimensions, SIMD3<Int>(repeating: 18))
        XCTAssertTrue(viewport.scene.gpuSparseVolumeInstances[0].resource.sampleBuffer === initialResource.sampleBuffer)
        try viewport.renderNextSample()
        XCTAssertEqual(viewport.sampleCount, 1)
    }

    func testViewportDirectGridGPUReplacementKeepsSessionAndMetadataBuffers() throws {
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
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.25, 0.8, 0.4), roughness: 0.5))
        let renderer = try DenrimRenderer(device: device)
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let initial = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(
                        shape: .box(halfExtents: SIMD3<Float>(0.55, 0.35, 0.35), cornerRadius: 0.12),
                        material: material
                    )
                ]),
                resolution: 26,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.22),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        let fieldID = scene.add(fieldBundle: initial.bundle)
        let initialResource = scene.gpuSparseVolumeInstances[0].resource
        let initialMetadata = try XCTUnwrap(initialResource.metadataBuffers)
        let updated = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.35), material: material)
                ]),
                resolution: 18,
                storage: .sparseBricks(brickSize: 6, narrowBand: 0.24),
                fallbackMaterial: material
            ),
            reusing: initialResource,
            metadataMode: .directGridGPU
        )
        guard case .gpuSparse(let updatedResource) = updated.bundle.storage else {
            return XCTFail("Expected GPU sparse field storage.")
        }
        let updatedMetadata = try XCTUnwrap(updatedResource.metadataBuffers)
        XCTAssertTrue(updatedResource.sampleBuffer === initialResource.sampleBuffer)
        XCTAssertTrue(updatedMetadata.brickBuffer === initialMetadata.brickBuffer)
        XCTAssertTrue(updatedMetadata.attributeDescriptorBuffer === initialMetadata.attributeDescriptorBuffer)
        XCTAssertTrue(updatedMetadata.gridBuffer === initialMetadata.gridBuffer)
        XCTAssertTrue(updatedMetadata.gridIndexBuffer === initialMetadata.gridIndexBuffer)

        let viewport = try renderer.makeViewport(
            scene: scene,
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1)
        )
        try viewport.renderNextSample()
        let originalSession = viewport.session
        let originalSDFResources = viewport.session.sdfResourceDebugInfo

        let replaced = try viewport.replaceGPUSparseFieldPreservingSession(fieldID, with: updated.bundle)
        let replacedSDFResources = viewport.session.sdfResourceDebugInfo

        XCTAssertTrue(replaced)
        XCTAssertTrue(viewport.session === originalSession)
        XCTAssertTrue(replacedSDFResources.volumeBrickSampleBuffer === originalSDFResources.volumeBrickSampleBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickBuffer === originalSDFResources.volumeBrickBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickAttributeDescriptorBuffer === originalSDFResources.volumeBrickAttributeDescriptorBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickGridBuffer === originalSDFResources.volumeBrickGridBuffer)
        XCTAssertTrue(replacedSDFResources.volumeBrickGridIndexBuffer === originalSDFResources.volumeBrickGridIndexBuffer)
        XCTAssertEqual(viewport.sampleCount, 0)
        try viewport.renderNextSample()
        XCTAssertEqual(viewport.sampleCount, 1)
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

    private struct SparseBrickQualityProbe {
        var normal: [RenderOutputPixel]
        var depth: [RenderOutputPixel]
    }

    private struct PrimaryAOVDifferenceMetrics {
        var coverage: Float
        var normalRMSE: Float
        var depthRMSE: Float
        var silhouetteMismatchRatio: Float
    }

    private func renderSparseBrickQualityProbe(
        renderer: DenrimRenderer,
        resolution: Int,
        quality: RenderQuality,
        sampleScale: Int
    ) throws -> SparseBrickQualityProbe {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0.0, 0.0, 3.0),
                target: SIMD3<Float>(0.0, 0.0, 0.0),
                projection: .orthographic(verticalScale: 1.7)
            )
        )
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.56, 0.22), roughness: 0.42))
        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .sphere(radius: 0.62),
                material: material
            ),
            SDFPrimitive(
                shape: .cylinder(radius: 0.20, halfHeight: 0.92),
                material: material,
                transform: Transform.translation(SIMD3<Float>(-0.20, 0.12, 0.0))
                    * Transform.rotationX(radians: .pi * 0.5),
                operation: .subtract
            ),
            SDFPrimitive(
                shape: .box(halfExtents: SIMD3<Float>(0.85, 0.055, 0.14), cornerRadius: 0.035),
                material: material,
                transform: Transform.translation(SIMD3<Float>(0.18, -0.05, 0.38))
                    * Transform.rotationZ(radians: -0.18),
                operation: .subtract
            )
        ])
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(
                resolution: resolution,
                brickSize: 7,
                boundsMin: SIMD3<Float>(repeating: -0.9),
                boundsMax: SIMD3<Float>(repeating: 0.9),
                narrowBand: 0.32,
                sampleScale: sampleScale
            )
        )
        scene.add(sparseVolume: sparse, material: material)

        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(
                width: 44,
                height: 44,
                maxBounces: 1,
                quality: quality
            ),
            accelerationMode: .flatBVH
        )
        try session.renderNextSample()
        return SparseBrickQualityProbe(
            normal: try session.pixels(for: .normal),
            depth: try session.pixels(for: .depth)
        )
    }

    private func primaryAOVDifferenceMetrics(
        lhsNormal: [RenderOutputPixel],
        lhsDepth: [RenderOutputPixel],
        rhsNormal: [RenderOutputPixel],
        rhsDepth: [RenderOutputPixel]
    ) -> PrimaryAOVDifferenceMetrics {
        XCTAssertEqual(lhsNormal.count, rhsNormal.count)
        XCTAssertEqual(lhsDepth.count, rhsDepth.count)
        XCTAssertEqual(lhsNormal.count, lhsDepth.count)

        var bothHitCount: Float = 0
        var eitherHitCount: Float = 0
        var silhouetteMismatchCount: Float = 0
        var normalSquaredError: Float = 0
        var depthSquaredError: Float = 0

        for index in lhsNormal.indices {
            let lhsHit = lhsNormal[index].a > 0.5
            let rhsHit = rhsNormal[index].a > 0.5
            if lhsHit || rhsHit {
                eitherHitCount += 1
            }
            if lhsHit != rhsHit {
                silhouetteMismatchCount += 1
            }
            guard lhsHit, rhsHit else {
                continue
            }

            bothHitCount += 1
            let lhsVector = SIMD3<Float>(
                lhsNormal[index].r * 2 - 1,
                lhsNormal[index].g * 2 - 1,
                lhsNormal[index].b * 2 - 1
            )
            let rhsVector = SIMD3<Float>(
                rhsNormal[index].r * 2 - 1,
                rhsNormal[index].g * 2 - 1,
                rhsNormal[index].b * 2 - 1
            )
            let normalDelta = lhsVector - rhsVector
            normalSquaredError += simd_dot(normalDelta, normalDelta)

            let depthDelta = lhsDepth[index].r - rhsDepth[index].r
            depthSquaredError += depthDelta * depthDelta
        }

        return PrimaryAOVDifferenceMetrics(
            coverage: bothHitCount / Float(max(1, lhsNormal.count)),
            normalRMSE: sqrt(normalSquaredError / max(1, bothHitCount)),
            depthRMSE: sqrt(depthSquaredError / max(1, bothHitCount)),
            silhouetteMismatchRatio: silhouetteMismatchCount / max(1, eitherHitCount)
        )
    }
}
