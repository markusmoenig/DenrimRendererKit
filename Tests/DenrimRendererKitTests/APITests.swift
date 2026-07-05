import Foundation
import simd
import XCTest
@testable import DenrimRendererKit

final class APITests: XCTestCase {
    func testPerspectiveCameraGeneratesPerspectiveGPUCamera() {
        let camera = Camera(
            origin: SIMD3<Float>(0, 0, 3),
            target: SIMD3<Float>(0, 0, 0),
            verticalFieldOfViewDegrees: 90
        )

        let gpu = camera.gpuCamera(width: 200, height: 100)

        XCTAssertEqual(gpu.origin.w, 0, accuracy: 0.0001)
        XCTAssertEqual(gpu.origin.z, 3, accuracy: 0.0001)
        XCTAssertEqual(gpu.lowerLeft.z, 2, accuracy: 0.0001)
        XCTAssertEqual(simd_length(gpu.horizontal.xyz), 4, accuracy: 0.0001)
        XCTAssertEqual(simd_length(gpu.vertical.xyz), 2, accuracy: 0.0001)
    }

    func testOrthographicCameraGeneratesOrthographicGPUCamera() {
        let camera = Camera(
            origin: SIMD3<Float>(0, 0, 3),
            target: SIMD3<Float>(0, 0, 2),
            projection: .orthographic(verticalScale: 6)
        )

        let gpu = camera.gpuCamera(width: 200, height: 100)

        XCTAssertEqual(gpu.origin.w, 1, accuracy: 0.0001)
        XCTAssertEqual(gpu.origin.z, 3, accuracy: 0.0001)
        XCTAssertEqual(gpu.lowerLeft.x, -6, accuracy: 0.0001)
        XCTAssertEqual(gpu.lowerLeft.y, -3, accuracy: 0.0001)
        XCTAssertEqual(gpu.lowerLeft.z, 3, accuracy: 0.0001)
        XCTAssertEqual(simd_length(gpu.horizontal.xyz), 12, accuracy: 0.0001)
        XCTAssertEqual(simd_length(gpu.vertical.xyz), 6, accuracy: 0.0001)
    }

    func testCornellBoxSceneCompiles() throws {
        let scene = RenderScene.cornellBox()

        XCTAssertEqual(scene.materials.count, 4)
        XCTAssertEqual(scene.meshInstances.count, 6)
    }

    func testEmptyRenderSceneDoesNotCreateDefaultLights() {
        let scene = RenderScene()

        XCTAssertTrue(scene.materials.isEmpty)
        XCTAssertTrue(scene.meshInstances.isEmpty)
        XCTAssertTrue(scene.volumeInstances.isEmpty)
        XCTAssertTrue(scene.sparseVolumeInstances.isEmpty)
    }

    func testDistanceVolumeSceneCompiles() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.25, 0.18)))
        scene.add(
            volume: .sphere(resolution: 12, radius: 0.55),
            material: material,
            transform: .translation(SIMD3<Float>(0, 0.5, 0))
        )

        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertTrue(scene.meshInstances.isEmpty)
        XCTAssertEqual(scene.volumeInstances.count, 1)
        XCTAssertTrue(build.triangles.isEmpty)
        XCTAssertEqual(build.volumes.count, 1)
        XCTAssertEqual(build.volumeSamples.count, 12 * 12 * 12)
        XCTAssertEqual(build.volumes[0].dimensions.w, material.rawValue)
        XCTAssertEqual(build.volumes[0].metadata.y, 0)
    }

    func testRenderFieldBundleAddsDenseStorage() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let volume = DistanceVolume.sphere(resolution: 12, radius: 0.55)
        let bundle = RenderFieldBundle(dense: volume, fallbackMaterial: material)
        let field = scene.add(
            fieldBundle: bundle,
            transform: .translation(SIMD3<Float>(0.25, 0.5, 0))
        )

        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

        XCTAssertEqual(field.storage, .dense)
        XCTAssertEqual(field.index, 0)
        XCTAssertEqual(scene.volumeInstances.count, 1)
        XCTAssertTrue(scene.sparseVolumeInstances.isEmpty)
        XCTAssertEqual(scene.volumeInstances[0].material, material)
        XCTAssertEqual(scene.volumeInstances[0].transform.matrix.columns.3.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(bundle.bounds.minimum, volume.boundsMin)
        XCTAssertEqual(bundle.bounds.maximum, volume.boundsMax)
        XCTAssertEqual(build.volumes.count, 1)
        XCTAssertEqual(build.volumeSamples.count, 12 * 12 * 12)
    }

    func testRenderFieldBundleAddsSparseStorageAndReplacesWholeBundle() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let model = SDFModel(primitives: [
            SDFPrimitive(shape: .sphere(radius: 0.48), material: material)
        ])
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 20, brickSize: 5, narrowBand: 0.3)
        )
        let replacement = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 18, brickSize: 6, narrowBand: 0.3)
        )

        let field = scene.add(
            fieldBundle: RenderFieldBundle(sparse: sparse, fallbackMaterial: material),
            transform: .translation(SIMD3<Float>(0.1, 0.2, 0.3))
        )
        let replaced = scene.replaceField(
            field,
            with: RenderFieldBundle(sparse: replacement, fallbackMaterial: material)
        )
        let compiled = try scene.compileForGPU()

        XCTAssertTrue(replaced)
        XCTAssertEqual(field.storage, .sparse)
        XCTAssertEqual(field.index, 0)
        XCTAssertTrue(scene.volumeInstances.isEmpty)
        XCTAssertEqual(scene.sparseVolumeInstances.count, 1)
        XCTAssertEqual(scene.sparseVolumeInstances[0].volume.dimensions, replacement.dimensions)
        XCTAssertEqual(scene.sparseVolumeInstances[0].transform.matrix.columns.3.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(scene.sparseVolumeInstances[0].transform.matrix.columns.3.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(scene.sparseVolumeInstances[0].transform.matrix.columns.3.z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(compiled.volumeBricks.count, replacement.bricks.count)
    }

    func testQuadLightAPIAddsAppAuthoredEmissiveLight() throws {
        var scene = RenderScene()
        scene.addQuadLight(QuadLight(
            SIMD3<Float>(-1, 2, -1),
            SIMD3<Float>(1, 2, -1),
            SIMD3<Float>(1, 2, 1),
            SIMD3<Float>(-1, 2, 1),
            color: SIMD3<Float>(1, 0.8, 0.6),
            intensity: 12
        ))

        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertEqual(scene.meshInstances.count, 1)
        XCTAssertEqual(build.triangles.count, 2)
        XCTAssertEqual(build.lights.count, 2)
        XCTAssertTrue(build.lights.allSatisfy { light in
            light.materialIndex == 0
        })
        let material = try XCTUnwrap(build.materials.first)
        XCTAssertEqual(material.emission.x, 12, accuracy: 0.0001)
        XCTAssertEqual(material.emission.y, 9.6, accuracy: 0.0001)
        XCTAssertEqual(material.emission.z, 7.2, accuracy: 0.0001)
        XCTAssertEqual(material.emission.w, 0, accuracy: 0.0001)
    }

    func testMaterialReferenceSceneCompiles() throws {
        let scene = RenderScene.materialReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 8)
        XCTAssertEqual(scene.meshInstances.count, 8)
        XCTAssertEqual(compiled.triangles.count, 66)
        XCTAssertTrue(scene.materials.contains { $0.metallic > 0 })
        XCTAssertTrue(scene.materials.contains { $0.roughness < 0.2 })
        XCTAssertTrue(scene.materials.contains { $0.sheen > 0 })
    }

    func testMaterialVariantReferenceSceneCompiles() throws {
        let scene = RenderScene.materialVariantReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 8)
        XCTAssertEqual(scene.meshInstances.count, 8)
        XCTAssertEqual(compiled.triangles.count, 66)
        XCTAssertTrue(scene.materials.contains { $0.metallic > 0 })
        XCTAssertTrue(scene.materials.contains { $0.clearcoat > 0 })
        XCTAssertTrue(scene.materials.contains { $0.sheen > 0 })
        XCTAssertTrue(scene.materials.contains { $0.specularAnisotropy > 0 })
    }

    func testSemanticMaterialResolvesArtistEditableStyle() {
        let moss = SemanticMaterial.moss(
            youngColor: SIMD3<Float>(0.6, 0.9, 0.25),
            matureColor: SIMD3<Float>(0.1, 0.42, 0.12),
            dryColor: SIMD3<Float>(0.48, 0.34, 0.18),
            age: 0.5,
            wetness: 0.7
        )

        let material = moss.resolvedMaterial()

        XCTAssertGreaterThan(material.baseColor.y, material.baseColor.x)
        XCTAssertGreaterThan(material.baseColor.y, material.baseColor.z)
        XCTAssertLessThan(material.roughness, 0.7)
        XCTAssertGreaterThan(material.sheen, 0)
        XCTAssertGreaterThan(material.subsurface, 0)
    }

    func testRenderSceneStoresSemanticMaterialsAsSourceOfTruth() throws {
        var scene = RenderScene()
        let moss = SemanticMaterial.moss(
            youngColor: SIMD3<Float>(0.3, 0.8, 0.2),
            matureColor: SIMD3<Float>(0.05, 0.32, 0.08),
            age: 0.25,
            wetness: 0.4
        )
        let material = scene.addMaterial(moss)

        XCTAssertEqual(material.rawValue, 0)
        XCTAssertEqual(scene.materialSources.count, 1)
        XCTAssertEqual(scene.materialSources[0].archetype, .moss)
        XCTAssertEqual(scene.materials.count, 1)

        let compiled = try scene.compileForGPU()
        XCTAssertEqual(compiled.materials.count, 1)
        XCTAssertEqual(compiled.materials[0].baseColor.x, moss.resolvedMaterial().baseColor.x, accuracy: 0.0001)
    }

    func testTransparentMaterialReferenceSceneCompiles() throws {
        let scene = RenderScene.transparentMaterialReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 7)
        XCTAssertEqual(scene.meshInstances.count, 7)
        XCTAssertEqual(compiled.triangles.count, 34)
        XCTAssertTrue(scene.materials.contains { $0.opacity == 0 })
        XCTAssertTrue(scene.materials.contains { $0.opacity > 0 && $0.opacity < 1 })
        XCTAssertTrue(scene.materials.contains { $0.transmission > 0 })
        XCTAssertTrue(scene.materials.contains { $0.transmissionAbsorptionDistance > 0 })
        XCTAssertTrue(scene.materials.contains { $0.emissionStrength > 0 })
    }

    func testDistanceVolumeReferenceSceneCompiles() throws {
        let scene = RenderScene.distanceVolumeReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.volumeInstances.count, 1)
        XCTAssertEqual(compiled.volumes.count, 1)
        XCTAssertEqual(compiled.volumeSamples.count, 48 * 36 * 32)
        XCTAssertFalse(compiled.triangles.isEmpty)
        XCTAssertTrue(scene.materials.contains { $0.opacity > 0 && $0.opacity < 1 })
        XCTAssertTrue(scene.materials.contains { $0.transmission > 0 })
        XCTAssertTrue(scene.materials.contains { $0.metallic > 0 })
    }

    func testSDFModelCompilesMultiplePrimitivesIntoOneMaterialAwareVolume() throws {
        var scene = RenderScene()
        let red = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.1, 0.1)))
        let blue = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.1, 0.2, 0.9)))
        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .sphere(radius: 0.55),
                material: red,
                transform: .translation(SIMD3<Float>(-0.22, 0, 0))
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.55),
                material: blue,
                transform: .translation(SIMD3<Float>(0.22, 0, 0)),
                smoothUnionRadius: 0.22
            )
        ])

        let volume = try DistanceVolumeBuilder.build(
            model: model,
            settings: DistanceVolumeBuildSettings(resolution: 20)
        )
        scene.add(volume: volume, material: red)
        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

        XCTAssertEqual(scene.volumeInstances.count, 1)
        XCTAssertEqual(build.volumes.count, 1)
        XCTAssertEqual(build.volumeSamples.count, 20 * 20 * 20)
        XCTAssertTrue(build.volumeSamples.contains { sample in
            sample.materialA == red.rawValue && sample.materialB == blue.rawValue && sample.materialBlend > 0 && sample.materialBlend < 1
        })
    }

    func testDistanceVolumeMaterialFieldsReachGPUVolumeSamples() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.1, 0.1)))
        let sampleCount = 4 * 4 * 4
        let fields = DistanceVolumeMaterialFields(
            baseColor: SIMD3<Float>(0.1, 0.8, 0.25),
            opacity: 0.42,
            emission: SIMD3<Float>(1.5, 0.2, 0.1),
            roughness: 0.87,
            metallic: 0.23,
            transmission: 0.31
        )
        let volume = DistanceVolume(
            width: 4,
            height: 4,
            depth: 4,
            distances: [Float](repeating: 1, count: sampleCount),
            materialSamples: [DistanceVolumeMaterialSample](
                repeating: DistanceVolumeMaterialSample(materialA: material, fields: fields),
                count: sampleCount
            )
        )
        scene.add(volume: volume, material: material)

        let compiled = try scene.compileForGPU()
        let sample = try XCTUnwrap(compiled.volumeSamples.first)

        XCTAssertEqual(sample.baseColorOpacity.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(sample.baseColorOpacity.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(sample.baseColorOpacity.z, 0.25, accuracy: 0.0001)
        XCTAssertEqual(sample.baseColorOpacity.w, 0.42, accuracy: 0.0001)
        XCTAssertEqual(sample.emissionTransmission.x, 1.5, accuracy: 0.0001)
        XCTAssertEqual(sample.emissionTransmission.w, 0.31, accuracy: 0.0001)
        XCTAssertEqual(sample.surface.x, 0.87, accuracy: 0.0001)
        XCTAssertEqual(sample.surface.y, 0.23, accuracy: 0.0001)
        XCTAssertNotEqual(sample.materialFieldFlags.x & DistanceVolumeMaterialFields.baseColorFlag, 0)
        XCTAssertNotEqual(sample.materialFieldFlags.x & DistanceVolumeMaterialFields.opacityFlag, 0)
        XCTAssertNotEqual(sample.materialFieldFlags.x & DistanceVolumeMaterialFields.emissionFlag, 0)
        XCTAssertNotEqual(sample.materialFieldFlags.x & DistanceVolumeMaterialFields.roughnessFlag, 0)
        XCTAssertNotEqual(sample.materialFieldFlags.x & DistanceVolumeMaterialFields.metallicFlag, 0)
        XCTAssertNotEqual(sample.materialFieldFlags.x & DistanceVolumeMaterialFields.transmissionFlag, 0)
    }

    func testSDFPrimitiveMaterialFieldsBakeIntoDenseAndSparseVolumes() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.1, 0.1)))
        let fields = DistanceVolumeMaterialFields(
            baseColor: SIMD3<Float>(0.15, 0.72, 0.32),
            roughness: 0.91,
            metallic: 0.12
        )
        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .sphere(radius: 0.55),
                material: material,
                materialFields: fields
            )
        ])

        let dense = try DistanceVolumeBuilder.build(
            model: model,
            settings: DistanceVolumeBuildSettings(resolution: 12)
        )
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 12, brickSize: 4, narrowBand: 0.4)
        )
        scene.add(sparseVolume: sparse, material: material)
        let compiled = try scene.compileForGPU()

        XCTAssertTrue(dense.materialSamples.contains { sample in
            sample.fields.baseColor == fields.baseColor
                && sample.fields.roughness == fields.roughness
                && sample.fields.metallic == fields.metallic
        })
        XCTAssertTrue(sparse.bricks.flatMap(\.materialSamples).contains { sample in
            sample.fields.baseColor == fields.baseColor
                && sample.fields.roughness == fields.roughness
                && sample.fields.metallic == fields.metallic
        })
        let bakedColor = try XCTUnwrap(fields.baseColor)
        let bakedRoughness = try XCTUnwrap(fields.roughness)
        let bakedMetallic = try XCTUnwrap(fields.metallic)
        XCTAssertTrue(compiled.volumeBrickSamples.contains { sample in
            sample.baseColorOpacity.x == bakedColor.x
                && sample.baseColorOpacity.y == bakedColor.y
                && sample.baseColorOpacity.z == bakedColor.z
                && sample.surface.x == bakedRoughness
                && sample.surface.y == bakedMetallic
                && sample.materialFieldFlags.x & DistanceVolumeMaterialFields.baseColorFlag != 0
                && sample.materialFieldFlags.x & DistanceVolumeMaterialFields.roughnessFlag != 0
                && sample.materialFieldFlags.x & DistanceVolumeMaterialFields.metallicFlag != 0
        })
    }

    func testSDFPrimitiveAttributesBakeIntoDenseAndSparseVolumes() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.4, 0.8, 0.25)))
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge, defaultValue: 0),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness, defaultValue: 0),
            DistanceVolumeAttributeChannel(name: "mossAmount", semantic: .mossAmount, defaultValue: 0)
        ])
        let model = SDFModel(
            primitives: [
                SDFPrimitive(
                    shape: .sphere(radius: 0.5),
                    material: material,
                    attributes: DistanceVolumeAttributeValues([
                        "growthAge": 0.35,
                        "wetness": 0.72,
                        "mossAmount": 0.9
                    ])
                )
            ],
            attributeLayout: layout
        )

        let dense = try DistanceVolumeBuilder.build(
            model: model,
            settings: DistanceVolumeBuildSettings(resolution: 12)
        )
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 12, brickSize: 4, narrowBand: 0.4)
        )
        let reconstructed = sparse.denseVolume()
        scene.add(sparseVolume: sparse, material: material)
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(dense.attributeLayout, layout)
        XCTAssertEqual(dense.attributeSamples.count, 12 * 12 * 12)
        XCTAssertTrue(dense.attributeSamples.contains { sample in
            sample.x == 0.35 && sample.y == 0.72 && sample.z == 0.9
        })
        XCTAssertEqual(reconstructed.attributeLayout, layout)
        XCTAssertEqual(reconstructed.attributeSamples.count, 12 * 12 * 12)
        XCTAssertTrue(reconstructed.attributeSamples.contains { sample in
            sample.x == 0.35 && sample.y == 0.72 && sample.z == 0.9
        })
        XCTAssertTrue(sparse.bricks.contains { brick in
            brick.attributeSamples.contains { sample in
                sample.x == 0.35 && sample.y == 0.72 && sample.z == 0.9
            }
        })
        XCTAssertEqual(compiled.volumeBrickAttributeDescriptors.count, sparse.bricks.count)
        XCTAssertTrue(compiled.volumeBrickAttributeSamples.contains { sample in
            sample.x == 0.35 && sample.y == 0.72 && sample.z == 0.9
        })
    }

    func testDistanceVolumeAttributesReachGPUAttributeBuffers() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.4, 0.8, 0.25)))
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
            DistanceVolumeAttributeChannel(name: "cavity", semantic: .cavity),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness),
            DistanceVolumeAttributeChannel(name: "polish", semantic: .polish)
        ])
        let sampleCount = 4 * 4 * 4
        let packed = packedAttributeSample(
            values: DistanceVolumeAttributeValues([
                "growthAge": 0.25,
                "cavity": 0.6,
                "wetness": 0.8,
                "polish": 0.1
            ]),
            layout: layout
        )
        var attributeSamples: [SIMD4<Float>] = []
        for _ in 0..<sampleCount {
            attributeSamples.append(contentsOf: packed)
        }
        let volume = DistanceVolume(
            width: 4,
            height: 4,
            depth: 4,
            distances: [Float](repeating: 1, count: sampleCount),
            attributeLayout: layout,
            attributeSamples: attributeSamples
        )
        scene.add(volume: volume, material: material)

        let compiled = try scene.compileForGPU()
        let descriptor = try XCTUnwrap(compiled.volumeAttributeDescriptors.first)

        XCTAssertEqual(compiled.volumeAttributeSamples.count, sampleCount)
        XCTAssertEqual(compiled.volumeAttributeSamples[0], SIMD4<Float>(0.25, 0.6, 0.8, 0.1))
        XCTAssertEqual(descriptor.metadata.x, 0)
        XCTAssertEqual(descriptor.metadata.y, 1)
        XCTAssertEqual(descriptor.metadata.z, UInt32(sampleCount))
        XCTAssertEqual(descriptor.metadata.w, 0)
        XCTAssertEqual(descriptor.semantics0.x, DistanceVolumeAttributeSemantic.growthAge.rawValue)
        XCTAssertEqual(descriptor.semantics0.y, DistanceVolumeAttributeSemantic.cavity.rawValue)
        XCTAssertEqual(descriptor.semantics0.z, DistanceVolumeAttributeSemantic.wetness.rawValue)
        XCTAssertEqual(descriptor.semantics0.w, DistanceVolumeAttributeSemantic.polish.rawValue)
    }

    func testSparseSDFBuildStoresOnlyActiveBricks() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.15, 0.08)))
        let model = SDFModel(primitives: [
            SDFPrimitive(shape: .sphere(radius: 0.45), material: material)
        ])
        let settings = SparseDistanceVolumeBuildSettings(
            denseSettings: DistanceVolumeBuildSettings(
                dimensions: SIMD3<Int>(32, 32, 32),
                boundsMin: SIMD3<Float>(repeating: -4),
                boundsMax: SIMD3<Float>(repeating: 4)
            ),
            brickSize: SIMD3<Int>(repeating: 8),
            narrowBand: 0.35
        )

        let sparse = try DistanceVolumeBuilder.buildSparse(model: model, settings: settings)
        let dense = sparse.denseVolume()

        XCTAssertGreaterThan(sparse.bricks.count, 0)
        XCTAssertLessThan(sparse.bricks.count, 64)
        XCTAssertEqual(dense.dimensions, SIMD3<Int>(32, 32, 32))
        XCTAssertEqual(dense.distances.count, 32 * 32 * 32)
        XCTAssertEqual(dense.materialSamples.count, 32 * 32 * 32)
        XCTAssertTrue(sparse.bricks.flatMap(\.distances).contains { $0 < 0 })
        XCTAssertTrue(dense.distances.contains { $0 < 0 })
    }

    func testSparseSDFBuildPreservesMaterialBlendSamples() throws {
        var scene = RenderScene()
        let red = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.1, 0.1)))
        let blue = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.1, 0.2, 0.9)))
        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .sphere(radius: 0.55),
                material: red,
                transform: .translation(SIMD3<Float>(-0.22, 0, 0))
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.55),
                material: blue,
                transform: .translation(SIMD3<Float>(0.22, 0, 0)),
                smoothUnionRadius: 0.22
            )
        ])

        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 20, brickSize: 5, narrowBand: 1.5)
        )

        XCTAssertTrue(sparse.bricks.flatMap(\.materialSamples).contains { sample in
            sample.materialA == red && sample.materialB == blue && sample.blend > 0 && sample.blend < 1
        })
    }

    func testSparseSDFBuildCanRoundTripThroughDenseVolume() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.25, 0.8, 0.55)))
        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .box(halfExtents: SIMD3<Float>(0.42, 0.32, 0.28), cornerRadius: 0.08),
                material: material,
                transform: .translation(SIMD3<Float>(0.08, -0.04, 0.03))
            )
        ])
        let denseSettings = DistanceVolumeBuildSettings(
            dimensions: SIMD3<Int>(18, 16, 14),
            boundsMin: SIMD3<Float>(repeating: -1),
            boundsMax: SIMD3<Float>(repeating: 1)
        )

        let dense = try DistanceVolumeBuilder.build(model: model, settings: denseSettings)
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(
                denseSettings: denseSettings,
                brickSize: SIMD3<Int>(5, 6, 4),
                narrowBand: 10
            )
        )
        let reconstructed = sparse.denseVolume()

        XCTAssertEqual(sparse.bricks.count, 4 * 3 * 4)
        XCTAssertEqual(reconstructed.dimensions, dense.dimensions)
        XCTAssertEqual(reconstructed.materialSamples, dense.materialSamples)
        XCTAssertEqual(reconstructed.distances.count, dense.distances.count)
        for index in dense.distances.indices {
            XCTAssertEqual(reconstructed.distances[index], dense.distances[index], accuracy: 0.000001)
        }
    }

    func testSparseDistanceVolumeSceneCompilesBrickBuffers() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.85, 0.25, 0.18)))
        let model = SDFModel(primitives: [
            SDFPrimitive(shape: .sphere(radius: 0.48), material: material)
        ])
        let sparse = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(resolution: 24, brickSize: 6, narrowBand: 0.35)
        )

        scene.add(
            sparseVolume: sparse,
            material: material,
            transform: .translation(SIMD3<Float>(0.25, 0.5, 0))
        )
        let compiled = try scene.compileForGPU()

        XCTAssertTrue(scene.volumeInstances.isEmpty)
        XCTAssertEqual(scene.sparseVolumeInstances.count, 1)
        XCTAssertEqual(compiled.volumes.count, 1)
        XCTAssertEqual(compiled.volumeSamples.count, 0)
        XCTAssertEqual(compiled.volumeBricks.count, sparse.bricks.count)
        XCTAssertEqual(
            compiled.volumeBrickSamples.count,
            sparse.bricks.reduce(0) { total, brick in
                total + brick.dimensions.x * brick.dimensions.y * brick.dimensions.z
            }
        )
        XCTAssertEqual(compiled.volumeBricks.first?.gridOriginAndVolume.w, 0)
        XCTAssertEqual(compiled.volumes[0].metadata.w, 1)
        XCTAssertTrue(compiled.volumeBrickSamples.contains { $0.distance < 0 })
    }

    func testMaterialSpecularClearcoatSheenAndIORReachGPUParameters() {
        let material = Material(
            baseColor: .init(0.8, 0.7, 0.6),
            roughness: 0.35,
            metallic: 0.2,
            specular: 0.6,
            specularColor: .init(0.9, 0.7, 0.5),
            indexOfRefraction: 1.8,
            specularAnisotropy: 0.65,
            clearcoat: 0.4,
            clearcoatColor: .init(0.25, 0.8, 0.9),
            clearcoatAttenuationColor: .init(0.5, 0.65, 0.8),
            clearcoatThickness: 0.6,
            clearcoatRoughness: 0.08,
            clearcoatIndexOfRefraction: 1.6,
            thinFilm: 0.8,
            thinFilmThicknessNanometers: 520,
            thinFilmIndexOfRefraction: 1.42,
            sheen: 0.55,
            sheenColor: .init(0.3, 0.4, 0.5),
            sheenRoughness: 0.7,
            subsurface: 0.8,
            subsurfaceColor: .init(0.95, 0.42, 0.28),
            subsurfaceRadius: .init(1.2, 0.45, 0.25),
            subsurfaceScale: 0.32,
            subsurfaceAnisotropy: 0.18,
            transmission: 0.75,
            transmissionColor: .init(0.2, 0.6, 0.9),
            transmissionRoughness: 0.18,
            transmissionIndexOfRefraction: 1.33,
            transmissionAbsorptionColor: .init(0.5, 0.75, 0.95),
            transmissionAbsorptionDistance: 1.25,
            thinWalled: true,
            volumeScattering: 0.7,
            volumeScatteringColor: .init(0.8, 0.85, 0.9),
            volumeScatteringDistance: 0.6,
            volumeAnisotropy: 0.22
        )
        let gpu = material.gpuMaterial()

        XCTAssertEqual(gpu.parameters.x, 0.35, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters2.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters2.y, 1.8, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters2.z, 0.4, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters2.w, 0.08, accuracy: 0.0001)
        XCTAssertEqual(gpu.specularColor.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(gpu.specularColor.y, 0.7, accuracy: 0.0001)
        XCTAssertEqual(gpu.specularColor.z, 0.5, accuracy: 0.0001)
        XCTAssertEqual(gpu.specularColor.w, 1.6, accuracy: 0.0001)
        XCTAssertEqual(gpu.sheenColor.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(gpu.sheenColor.y, 0.4, accuracy: 0.0001)
        XCTAssertEqual(gpu.sheenColor.z, 0.5, accuracy: 0.0001)
        XCTAssertEqual(gpu.sheenColor.w, 0.55, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionColor.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionColor.y, 0.6, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionColor.z, 0.9, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionColor.w, 1, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters3.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters3.y, 0.18, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters3.z, 1.33, accuracy: 0.0001)
        XCTAssertEqual(gpu.parameters3.w, 0.65, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatColor.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatColor.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatColor.z, 0.9, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatColor.w, 0, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.y, 0.65, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.z, 0.8, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.w, 0.6, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionAbsorption.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionAbsorption.y, 0.75, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionAbsorption.z, 0.95, accuracy: 0.0001)
        XCTAssertEqual(gpu.transmissionAbsorption.w, 1.25, accuracy: 0.0001)
        XCTAssertEqual(gpu.thinFilm.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(gpu.thinFilm.y, 520, accuracy: 0.0001)
        XCTAssertEqual(gpu.thinFilm.z, 1.42, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceColor.x, 0.95, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceColor.y, 0.42, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceColor.z, 0.28, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceColor.w, 0.8, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceRadius.x, 1.2, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceRadius.y, 0.45, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceRadius.z, 0.25, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceRadius.w, 0.32, accuracy: 0.0001)
        XCTAssertEqual(gpu.subsurfaceParameters.x, 0.18, accuracy: 0.0001)
        XCTAssertEqual(gpu.volumeScattering.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(gpu.volumeScattering.y, 0.85, accuracy: 0.0001)
        XCTAssertEqual(gpu.volumeScattering.z, 0.9, accuracy: 0.0001)
        XCTAssertEqual(gpu.volumeScattering.w, 0.7, accuracy: 0.0001)
        XCTAssertEqual(gpu.volumeParameters.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(gpu.volumeParameters.y, 0.22, accuracy: 0.0001)
        XCTAssertEqual(gpu.emission.w, 0.75, accuracy: 0.0001)
    }

    func testMaterialTransmissionDefaultsInheritBaseSurfaceControls() {
        let material = Material(
            baseColor: .init(0.35, 0.6, 0.9),
            roughness: 0.42,
            indexOfRefraction: 1.47,
            transmission: 1
        )

        XCTAssertEqual(material.transmissionColor.x, 0.35, accuracy: 0.0001)
        XCTAssertEqual(material.transmissionColor.y, 0.6, accuracy: 0.0001)
        XCTAssertEqual(material.transmissionColor.z, 0.9, accuracy: 0.0001)
        XCTAssertEqual(material.transmissionRoughness, 0.42, accuracy: 0.0001)
        XCTAssertEqual(material.transmissionIndexOfRefraction, 1.47, accuracy: 0.0001)
        XCTAssertFalse(material.thinWalled)
    }

    func testBuiltInMaterialLibraryCanBeQueriedByIdentifierAndCategory() throws {
        XCTAssertGreaterThan(BuiltInMaterialLibrary.presets.count, 12)
        XCTAssertTrue(BuiltInMaterialLibrary.identifiers.contains("glass.thin-pane"))
        XCTAssertTrue(BuiltInMaterialLibrary.identifiers.contains("subsurface.skin-warm"))
        XCTAssertTrue(BuiltInMaterialLibrary.identifiers.contains("coating.iridescent-amber"))
        XCTAssertTrue(BuiltInMaterialLibrary.presets(in: .metal).contains { $0.identifier == "metal.brushed-aluminum" })

        let glass = try XCTUnwrap(BuiltInMaterialLibrary.material(named: "glass.thin_pane"))
        XCTAssertEqual(glass.transmission, 1, accuracy: 0.0001)
        XCTAssertTrue(glass.thinWalled)

        let brushed = try XCTUnwrap(BuiltInMaterialLibrary.preset(named: "METAL.BRUSHED_ALUMINUM"))
        XCTAssertEqual(brushed.category, .metal)
        XCTAssertEqual(brushed.material.metallic, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(brushed.material.specularAnisotropy, 0)

        let iridescent = try XCTUnwrap(BuiltInMaterialLibrary.preset(named: "coating.iridescent-amber"))
        XCTAssertEqual(iridescent.category, .coating)
        XCTAssertGreaterThan(iridescent.material.thinFilm, 0)
        XCTAssertGreaterThan(iridescent.material.clearcoat, 0)

        let skin = try XCTUnwrap(BuiltInMaterialLibrary.preset(named: "subsurface.skin-warm"))
        XCTAssertEqual(skin.category, .subsurface)
        XCTAssertGreaterThan(skin.material.subsurface, 0)
        XCTAssertGreaterThan(skin.material.subsurfaceRadius.x, skin.material.subsurfaceRadius.z)

        let milk = try XCTUnwrap(BuiltInMaterialLibrary.preset(named: "liquid.milk"))
        XCTAssertEqual(milk.category, .liquid)
        XCTAssertGreaterThan(milk.material.transmission, 0)
        XCTAssertGreaterThan(milk.material.volumeScattering, 0)
        XCTAssertGreaterThan(milk.material.transmissionAbsorptionDistance, 0)
    }

    func testBuiltInMaterialPreviewManifestMatchesPresets() throws {
        let previews = BuiltInMaterialLibrary.previews

        XCTAssertEqual(previews.map(\.identifier), BuiltInMaterialLibrary.identifiers)
        XCTAssertEqual(previews.count, BuiltInMaterialLibrary.presets.count)
        XCTAssertEqual(
            BuiltInMaterialLibrary.previews(in: .metal).map(\.identifier),
            BuiltInMaterialLibrary.presets(in: .metal).map(\.identifier)
        )

        let brushed = try XCTUnwrap(BuiltInMaterialLibrary.preview(named: "metal.brushed_aluminum"))
        XCTAssertEqual(brushed.displayName, "Brushed Aluminum")
        XCTAssertEqual(brushed.category, .metal)
        XCTAssertEqual(brushed.thumbnailPath, "Examples/Renders/Materials/metal.brushed-aluminum.png")
        XCTAssertEqual(
            BuiltInMaterialLibrary.thumbnailPath(for: "glass.clear"),
            "Examples/Renders/Materials/glass.clear.png"
        )
    }

    func testBuiltInMaterialPreviewThumbnailsExist() {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        for preview in BuiltInMaterialLibrary.previews {
            let thumbnailURL = repositoryRoot.appendingPathComponent(preview.thumbnailPath)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: thumbnailURL.path),
                "Missing material preview thumbnail for \(preview.identifier): \(thumbnailURL.path)"
            )
        }
    }

    func testClearcoatAttenuationDefaultsToClearcoatColor() {
        let material = Material(
            baseColor: .init(0.4, 0.5, 0.6),
            clearcoat: 0.7,
            clearcoatColor: .init(0.72, 0.86, 1),
            clearcoatThickness: 0.4
        )
        let gpu = material.gpuMaterial()

        XCTAssertNil(material.clearcoatAttenuationColor)
        XCTAssertEqual(gpu.clearcoatAttenuation.x, 0.72, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.y, 0.86, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.z, 1, accuracy: 0.0001)
        XCTAssertEqual(gpu.clearcoatAttenuation.w, 0.4, accuracy: 0.0001)
    }

    func testSettingsDefaultsAreSmallAndProgressive() {
        let settings = RenderSettings()

        XCTAssertEqual(settings.width, 512)
        XCTAssertEqual(settings.height, 512)
        XCTAssertEqual(settings.maxBounces, 4)
        XCTAssertEqual(settings.quality, .preview)
        XCTAssertFalse(settings.transparentBackground)
        XCTAssertEqual(settings.denoise.denoiser, .none)
        XCTAssertNil(settings.sampleRadianceClamp)
        XCTAssertEqual(settings.resolvedSampleRadianceClamp, RenderQuality.preview.defaultSampleRadianceClamp)
    }

    func testSettingsCanOverrideOrDisableSampleRadianceClamp() {
        let finalSettings = RenderSettings(quality: .final)
        let disabledSettings = RenderSettings(sampleRadianceClamp: 0)
        let customSettings = RenderSettings(sampleRadianceClamp: 18)

        XCTAssertEqual(RenderQuality.preview.defaultSampleRadianceClamp, 10)
        XCTAssertEqual(RenderQuality.interactive.defaultSampleRadianceClamp, 24)
        XCTAssertEqual(finalSettings.resolvedSampleRadianceClamp, 64)
        XCTAssertEqual(disabledSettings.resolvedSampleRadianceClamp, 0)
        XCTAssertEqual(customSettings.resolvedSampleRadianceClamp, 18)
    }
}
