import Foundation
import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class APITests: XCTestCase {
    private static func macroGridCount(dimensions: SIMD3<Int>, brickSize: SIMD3<Int>) -> Int {
        let gridDimensions = SIMD3<Int>(
            (dimensions.x + brickSize.x - 1) / brickSize.x,
            (dimensions.y + brickSize.y - 1) / brickSize.y,
            (dimensions.z + brickSize.z - 1) / brickSize.z
        )
        let macroSize = SIMD3<Int>(repeating: 4)
        let macroDimensions = SIMD3<Int>(
            (gridDimensions.x + macroSize.x - 1) / macroSize.x,
            (gridDimensions.y + macroSize.y - 1) / macroSize.y,
            (gridDimensions.z + macroSize.z - 1) / macroSize.z
        )
        return macroDimensions.x * macroDimensions.y * macroDimensions.z
    }

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
        XCTAssertTrue(scene.gpuSparseVolumeInstances.isEmpty)
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
        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

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
        XCTAssertEqual(build.volumeBrickBVH.primitiveIndices.count, build.volumeBricks.count)
        XCTAssertGreaterThan(build.volumeBrickBVH.nodes.count, 0)
        XCTAssertEqual(build.volumeBrickGrids.count, 1)
        let grid = build.volumeBrickGrids[0]
        let fineGridOffset = Int(grid.dimensionsAndIndexOffset.w)
        let fineGridCount = Int(grid.dimensionsAndIndexOffset.x * grid.dimensionsAndIndexOffset.y * grid.dimensionsAndIndexOffset.z)
        XCTAssertEqual(
            build.volumeBrickGridIndices[fineGridOffset..<(fineGridOffset + fineGridCount)].filter { $0 != UInt32.max }.count,
            build.volumeBricks.count
        )
    }

    func testDistanceFieldBakerProducesSparseFieldBundle() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.6, 0.2)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material),
                SDFPrimitive(
                    shape: .box(halfExtents: SIMD3<Float>(0.18, 0.18, 0.18)),
                    material: material,
                    transform: .translation(SIMD3<Float>(0.3, 0, 0)),
                    operation: .subtract
                )
            ]),
            resolution: 18,
            storage: .sparseBricks(brickSize: 6, narrowBand: 0.25),
            fallbackMaterial: material
        ))

        XCTAssertEqual(result.backend, .metalCompute)
        scene.add(fieldBundle: result.bundle)
        XCTAssertTrue(scene.volumeInstances.isEmpty)
        XCTAssertEqual(scene.sparseVolumeInstances.count, 1)
        XCTAssertEqual(scene.sparseVolumeInstances[0].volume.dimensions, SIMD3<Int>(18, 18, 18))
        XCTAssertGreaterThan(scene.sparseVolumeInstances[0].volume.bricks.count, 0)
    }

    func testDistanceFieldProgramSphereMatchesPrimitiveModel() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let modelResult = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
            ]),
            resolution: 12,
            storage: .dense,
            fallbackMaterial: material
        ))
        let programResult = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(program: DistanceFieldProgram(operations: [
                .sphere(radius: 0.55, material: material)
            ])),
            resolution: 12,
            storage: .dense,
            fallbackMaterial: material
        ))

        guard case .dense(let modelVolume) = modelResult.bundle.storage,
              case .dense(let programVolume) = programResult.bundle.storage else {
            return XCTFail("Expected dense field bundles.")
        }
        XCTAssertEqual(modelVolume.distances.count, programVolume.distances.count)
        let maxError = zip(modelVolume.distances, programVolume.distances).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxError, 0.00001)
    }

    func testDistanceFieldProgramTransformMatchesPrimitiveModel() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9)))
        let transform = Transform.translation(SIMD3<Float>(0.24, -0.1, 0.08))
            * .scale(SIMD3<Float>(0.85, 1.1, 0.95))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let modelResult = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material, transform: transform)
            ]),
            resolution: 12,
            storage: .dense,
            fallbackMaterial: material
        ))
        let programResult = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(program: DistanceFieldProgram(operations: [
                .transform(transform),
                .sphere(radius: 0.55, material: material)
            ])),
            resolution: 12,
            storage: .dense,
            fallbackMaterial: material
        ))

        guard case .dense(let modelVolume) = modelResult.bundle.storage,
              case .dense(let programVolume) = programResult.bundle.storage else {
            return XCTFail("Expected dense field bundles.")
        }
        let maxError = zip(modelVolume.distances, programVolume.distances).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxError, 0.00001)
    }

    func testDistanceFieldProgramInstructionsCanDefineSphere() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let modelResult = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
            ]),
            resolution: 12,
            storage: .dense,
            fallbackMaterial: material
        ))
        let programResult = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(program: DistanceFieldProgram(instructions: [
                .loadPosition(.init(0)),
                .length(.init(0), .init(0)),
                .setFloat(.init(1), 0.55),
                .subtractFloat(.init(2), .init(0), .init(1)),
                .emit(distance: .init(2), material: material)
            ])),
            resolution: 12,
            storage: .dense,
            fallbackMaterial: material
        ))

        guard case .dense(let modelVolume) = modelResult.bundle.storage,
              case .dense(let programVolume) = programResult.bundle.storage else {
            return XCTFail("Expected dense field bundles.")
        }
        let maxError = zip(modelVolume.distances, programVolume.distances).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxError, 0.00001)
    }

    func testDistanceFieldProgramInstructionsCanDefineTaperedCapsule() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.4, 0.85, 0.35)))
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .setVector(.init(1), SIMD3<Float>(0, -0.5, 0)),
            .setVector(.init(2), SIMD3<Float>(0, 0.5, 0)),
            .setFloat(.init(0), 0.2),
            .setFloat(.init(1), 0.4),
            .taperedCapsuleDistance(
                .init(2),
                position: .init(0),
                start: .init(1),
                end: .init(2),
                startRadius: .init(0),
                endRadius: .init(1)
            ),
            .emit(distance: .init(2), material: material)
        ])

        func distance(at position: SIMD3<Float>) -> Float {
            DistanceFieldProgramEvaluator.sample(
                program: program,
                at: position,
                fallbackMaterial: material
            ).distance
        }

        XCTAssertEqual(distance(at: SIMD3<Float>(0, -0.5, 0)), -0.2, accuracy: 0.00001)
        XCTAssertEqual(distance(at: SIMD3<Float>(0, 0.5, 0)), -0.4, accuracy: 0.00001)
        XCTAssertEqual(distance(at: SIMD3<Float>(0.3, 0, 0)), 0, accuracy: 0.00001)
        XCTAssertEqual(distance(at: SIMD3<Float>(0.6, 0.5, 0)), 0.2, accuracy: 0.00001)
    }

    func testDistanceFieldProgramTaperedCapsuleRunsOnGPUResidentBaker() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.4, 0.85, 0.35)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .setVector(.init(1), SIMD3<Float>(0, -0.55, 0)),
            .setVector(.init(2), SIMD3<Float>(0, 0.55, 0)),
            .setFloat(.init(0), 0.18),
            .setFloat(.init(1), 0.34),
            .taperedCapsuleDistance(
                .init(2),
                position: .init(0),
                start: .init(1),
                end: .init(2),
                startRadius: .init(0),
                endRadius: .init(1)
            ),
            .emit(distance: .init(2), material: material)
        ])
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 24,
                storage: .sparseBricks(brickSize: 6, narrowBand: 0.28, sampleScale: 2),
                fallbackMaterial: material,
                backend: .metalCompute
            ),
            metadataMode: .directGridGPU
        )

        guard case .gpuSparse(let resource) = result.bundle.storage else {
            return XCTFail("Expected GPU-resident sparse field storage.")
        }
        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertGreaterThan(resource.sampleCount, 0)
        XCTAssertEqual(resource.dimensions, SIMD3<Int>(repeating: 47))
    }

    func testDistanceFieldProgramInstructionsCanDefineSplineTube() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.3, 0.75, 0.55)))
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .setVector(.init(1), SIMD3<Float>(0, -0.5, 0)),
            .setVector(.init(2), SIMD3<Float>(0, -0.16666667, 0)),
            .setVector(.init(3), SIMD3<Float>(0, 0.16666667, 0)),
            .setVector(.init(4), SIMD3<Float>(0, 0.5, 0)),
            .setFloat(.init(0), 0.2),
            .setFloat(.init(1), 0.4),
            .splineTubeDistance(
                .init(2),
                position: .init(0),
                control0: .init(1),
                control1: .init(2),
                control2: .init(3),
                control3: .init(4),
                startRadius: .init(0),
                endRadius: .init(1)
            ),
            .emit(distance: .init(2), material: material)
        ])

        func distance(at position: SIMD3<Float>) -> Float {
            DistanceFieldProgramEvaluator.sample(
                program: program,
                at: position,
                fallbackMaterial: material
            ).distance
        }

        XCTAssertEqual(distance(at: SIMD3<Float>(0, -0.5, 0)), -0.2, accuracy: 0.00001)
        XCTAssertEqual(distance(at: SIMD3<Float>(0, 0.5, 0)), -0.4, accuracy: 0.00001)
        XCTAssertEqual(distance(at: SIMD3<Float>(0.3, 0, 0)), 0, accuracy: 0.01)
    }

    func testDistanceFieldProgramSplineTubeRunsOnGPUResidentBaker() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.3, 0.75, 0.55)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .setVector(.init(1), SIMD3<Float>(-0.42, -0.55, 0)),
            .setVector(.init(2), SIMD3<Float>(0.35, -0.18, 0.2)),
            .setVector(.init(3), SIMD3<Float>(-0.35, 0.18, -0.2)),
            .setVector(.init(4), SIMD3<Float>(0.42, 0.55, 0)),
            .setFloat(.init(0), 0.16),
            .setFloat(.init(1), 0.3),
            .splineTubeDistance(
                .init(2),
                position: .init(0),
                control0: .init(1),
                control1: .init(2),
                control2: .init(3),
                control3: .init(4),
                startRadius: .init(0),
                endRadius: .init(1)
            ),
            .emit(distance: .init(2), material: material)
        ])
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 24,
                storage: .sparseBricks(brickSize: 6, narrowBand: 0.28, sampleScale: 2),
                fallbackMaterial: material,
                backend: .metalCompute
            ),
            metadataMode: .directGridGPU
        )

        guard case .gpuSparse(let resource) = result.bundle.storage else {
            return XCTFail("Expected GPU-resident sparse field storage.")
        }
        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertGreaterThan(resource.sampleCount, 0)
        XCTAssertEqual(resource.dimensions, SIMD3<Int>(repeating: 47))
    }

    func testDistanceFieldProgramInstructionsCanDefineTwistedBox() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let operationProgram = DistanceFieldProgram(operations: [
            .twistY(strength: 2.4),
            .box(halfExtents: SIMD3<Float>(0.55, 0.18, 0.28), cornerRadius: 0.04, material: material)
        ])
        let instructionProgram = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .extractX(.init(0), .init(0)),
            .extractY(.init(1), .init(0)),
            .extractZ(.init(2), .init(0)),
            .setFloat(.init(3), 2.4),
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
            .setVector(.init(2), SIMD3<Float>(0.55, 0.18, 0.28)),
            .setFloat(.init(13), 0.04),
            .boxDistance(.init(14), position: .init(1), halfExtents: .init(2), cornerRadius: .init(13)),
            .emit(distance: .init(14), material: material)
        ])

        func denseDistances(_ program: DistanceFieldProgram) throws -> [Float] {
            let result = try baker.bake(DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 14,
                storage: .dense,
                fallbackMaterial: material
            ))
            guard case .dense(let volume) = result.bundle.storage else {
                throw DenrimRendererError.invalidScene("Expected dense program result.")
            }
            return volume.distances
        }

        let operationDistances = try denseDistances(operationProgram)
        let instructionDistances = try denseDistances(instructionProgram)
        let maxError = zip(operationDistances, instructionDistances).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxError, 0.00001)
    }

    func testDistanceFieldProgramOptimizerFoldsConstantsWithoutChangingSamples() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9)))
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .setFloat(.init(0), 0.25),
            .setFloat(.init(1), 0.3),
            .addFloat(.init(2), .init(0), .init(1)),
            .length(.init(3), .init(0)),
            .subtractFloat(.init(4), .init(3), .init(2)),
            .emit(distance: .init(4), material: material)
        ])
        let optimized = program.optimized()

        XCTAssertTrue(optimized.instructions.contains { instruction in
            if case .setFloat(let register, let value) = instruction {
                return register == .init(2) && abs(value - 0.55) < 0.00001
            }
            return false
        })

        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        func distances(_ program: DistanceFieldProgram) throws -> [Float] {
            let result = try baker.bake(DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 10,
                storage: .dense,
                fallbackMaterial: material
            ))
            guard case .dense(let volume) = result.bundle.storage else {
                throw DenrimRendererError.invalidScene("Expected dense program result.")
            }
            return volume.distances
        }
        let unoptimized = try distances(program)
        let folded = try distances(optimized)
        let maxError = zip(unoptimized, folded).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxError, 0.00001)
    }

    func testDistanceFieldProgramInstructionsWriteCompactAttributes() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness)
        ])
        let program = DistanceFieldProgram(
            instructions: [
                .loadPosition(.init(0)),
                .length(.init(0), .init(0)),
                .setFloat(.init(1), 0.55),
                .subtractFloat(.init(2), .init(0), .init(1)),
                .setFloat(.init(3), 0.75),
                .writeAttribute(channel: 0, value: .init(3)),
                .setFloat(.init(4), 0.35),
                .writeAttribute(channel: 1, value: .init(4)),
                .emit(distance: .init(2), material: material)
            ],
            attributeLayout: layout
        )
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let result = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(program: program),
            resolution: 10,
            storage: .dense,
            fallbackMaterial: material
        ))

        guard case .dense(let volume) = result.bundle.storage else {
            return XCTFail("Expected dense field bundle.")
        }
        XCTAssertEqual(volume.attributeLayout, layout)
        XCTAssertEqual(volume.attributeSamples.count, 10 * 10 * 10)
        XCTAssertTrue(volume.attributeSamples.contains { sample in
            abs(sample.x - 0.75) < 0.00001 && abs(sample.y - 0.35) < 0.00001
        })
    }

    func testDistanceFieldProgramSparseSampleScalePreservesCompactAttributes() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness)
        ])
        let program = DistanceFieldProgram(
            instructions: [
                .loadPosition(.init(0)),
                .length(.init(0), .init(0)),
                .setFloat(.init(1), 0.55),
                .subtractFloat(.init(2), .init(0), .init(1)),
                .setFloat(.init(3), 0.75),
                .writeAttribute(channel: 0, value: .init(3)),
                .setFloat(.init(4), 0.35),
                .writeAttribute(channel: 1, value: .init(4)),
                .emit(distance: .init(2), material: material)
            ],
            attributeLayout: layout
        )
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let result = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(program: program),
            resolution: 10,
            storage: .sparseBricks(brickSize: 3, narrowBand: 0.3, sampleScale: 2),
            fallbackMaterial: material
        ))

        guard case .sparse(let sparse) = result.bundle.storage else {
            return XCTFail("Expected sparse field bundle.")
        }

        XCTAssertEqual(sparse.dimensions, SIMD3<Int>(repeating: 19))
        XCTAssertEqual(sparse.brickSize, SIMD3<Int>(repeating: 6))
        XCTAssertEqual(sparse.attributeLayout, layout)
        XCTAssertGreaterThan(sparse.bricks.count, 0)
        XCTAssertTrue(sparse.bricks.contains { brick in
            brick.attributeSamples.contains { sample in
                abs(sample.x - 0.75) < 0.00001 && abs(sample.y - 0.35) < 0.00001
            }
        })
    }

    func testDistanceFieldProgramGPUResidentDirectGridBakesCompactAttributes() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let program = DistanceFieldProgram(
            instructions: [
                .loadPosition(.init(0)),
                .length(.init(0), .init(0)),
                .setFloat(.init(1), 0.55),
                .subtractFloat(.init(2), .init(0), .init(1)),
                .setFloat(.init(3), 0.75),
                .writeAttribute(channel: 0, value: .init(3)),
                .setFloat(.init(4), 0.35),
                .writeAttribute(channel: 1, value: .init(4)),
                .emit(distance: .init(2), material: material)
            ],
            attributeLayout: DistanceVolumeAttributeLayout(channels: [
                DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
                DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness)
            ])
        )
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)

        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 10,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.2),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        guard case .gpuSparse(let resource) = result.bundle.storage,
              let metadata = resource.metadataBuffers,
              let attributeSampleBuffer = resource.attributeSampleBuffer else {
            return XCTFail("Expected GPU sparse resource with resident attribute samples.")
        }
        scene.add(fieldBundle: result.bundle)
        let build = try LinearTriangleAccelerationBackend(buildsVolumeBrickBVH: false).build(scene: scene)

        XCTAssertEqual(resource.attributeSampleCount, resource.sampleCount)
        XCTAssertNotNil(build.gpuVolumeBrickAttributeSampleBuffer)
        XCTAssertEqual(build.gpuVolumeBrickAttributeSampleCount, resource.attributeSampleCount)
        let descriptors = metadata.attributeDescriptorBuffer.contents().bindMemory(
            to: GPUVolumeAttributeDescriptor.self,
            capacity: metadata.attributeDescriptorCount
        )
        XCTAssertTrue((0..<metadata.attributeDescriptorCount).contains { index in
            descriptors[index].metadata.y == 1
                && descriptors[index].semantics0.x == DistanceVolumeAttributeSemantic.growthAge.rawValue
                && descriptors[index].semantics0.y == DistanceVolumeAttributeSemantic.wetness.rawValue
        })

        let samples = attributeSampleBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: max(resource.attributeSampleCount, 1)
        )
        XCTAssertTrue((0..<resource.attributeSampleCount).contains { index in
            abs(samples[index].x - 0.75) < 0.00001 && abs(samples[index].y - 0.35) < 0.00001
        })
    }

    func testDistanceFieldProgramTwistZeroIsStableAndNonzeroChangesBox() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .cpuReference)
        let baseProgram = DistanceFieldProgram(operations: [
            .box(halfExtents: SIMD3<Float>(0.55, 0.18, 0.28), cornerRadius: 0.04, material: material)
        ])
        let zeroTwistProgram = DistanceFieldProgram(operations: [
            .twistY(strength: 0),
            .box(halfExtents: SIMD3<Float>(0.55, 0.18, 0.28), cornerRadius: 0.04, material: material)
        ])
        let twistedProgram = DistanceFieldProgram(operations: [
            .twistY(strength: 2.4),
            .box(halfExtents: SIMD3<Float>(0.55, 0.18, 0.28), cornerRadius: 0.04, material: material)
        ])

        func denseDistances(_ program: DistanceFieldProgram) throws -> [Float] {
            let result = try baker.bake(DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 14,
                storage: .dense,
                fallbackMaterial: material
            ))
            guard case .dense(let volume) = result.bundle.storage else {
                throw DenrimRendererError.invalidScene("Expected dense program result.")
            }
            return volume.distances
        }

        let base = try denseDistances(baseProgram)
        let zero = try denseDistances(zeroTwistProgram)
        let twisted = try denseDistances(twistedProgram)
        let zeroError = zip(base, zero).map { abs($0 - $1) }.max() ?? 0
        let twistDifference = zip(base, twisted).map { abs($0 - $1) }.max() ?? 0

        XCTAssertLessThan(zeroError, 0.00001)
        XCTAssertGreaterThan(twistDifference, 0.01)
    }

    func testDistanceFieldBakerProducesGPUResidentSparseFieldBundle() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9)))
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
        let build = try LinearTriangleAccelerationBackend(buildsVolumeBrickBVH: false).build(scene: scene)

        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertEqual(fieldID.storage, .gpuSparse)
        XCTAssertTrue(scene.volumeInstances.isEmpty)
        XCTAssertTrue(scene.sparseVolumeInstances.isEmpty)
        XCTAssertEqual(scene.gpuSparseVolumeInstances.count, 1)
        XCTAssertEqual(build.volumes.count, 1)
        XCTAssertGreaterThan(build.volumeBricks.count, 0)
        XCTAssertTrue(build.volumeBrickSamples.isEmpty)
        XCTAssertNotNil(build.gpuVolumeBrickSampleBuffer)
        XCTAssertEqual(build.gpuVolumeBrickSampleCount, scene.gpuSparseVolumeInstances[0].resource.sampleCount)
    }

    func testDistanceFieldBakerUsesMetalForSampleScaledSparseBake() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.2, 0.65, 0.9)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(primitives: [
                SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
            ]),
            resolution: 12,
            storage: .sparseBricks(brickSize: 4, narrowBand: 0.3, sampleScale: 2),
            fallbackMaterial: material,
            backend: .metalCompute
        ))

        guard case .sparse(let sparse) = result.bundle.storage else {
            return XCTFail("Expected sparse field storage.")
        }

        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertEqual(sparse.dimensions, SIMD3<Int>(repeating: 23))
        XCTAssertEqual(sparse.brickSize, SIMD3<Int>(repeating: 8))
        XCTAssertGreaterThan(sparse.bricks.count, 0)
        XCTAssertLessThanOrEqual(sparse.bricks.count, 27)
    }

    func testDistanceFieldBakerProducesDirectGridGPUResidentSparseFieldBundle() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
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
        let resource = scene.gpuSparseVolumeInstances[0].resource
        let metadata = try XCTUnwrap(resource.metadataBuffers)
        let build = try LinearTriangleAccelerationBackend(buildsVolumeBrickBVH: false).build(scene: scene)

        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertTrue(resource.bricks.isEmpty)
        XCTAssertGreaterThan(metadata.brickCount, 0)
        XCTAssertEqual(metadata.gridCount, 1)
        let macroGridCount = Self.macroGridCount(
            dimensions: resource.dimensions,
            brickSize: resource.brickSize
        )
        XCTAssertEqual(metadata.gridIndexCount, metadata.brickCount + macroGridCount)
        let gpuGrid = metadata.gridBuffer.contents().bindMemory(to: GPUVolumeBrickGrid.self, capacity: metadata.gridCount)[0]
        XCTAssertGreaterThan(gpuGrid.macroDimensionsAndIndexOffset.x, 0)
        XCTAssertEqual(gpuGrid.macroDimensionsAndIndexOffset.w, UInt32(metadata.brickCount))
        XCTAssertEqual(gpuGrid.macroSizeAndReserved.x, 4)
        XCTAssertTrue(build.volumeBricks.isEmpty)
        XCTAssertTrue(build.volumeBrickGridIndices.isEmpty)
        XCTAssertNotNil(build.gpuVolumeBrickBuffer)
        XCTAssertNotNil(build.gpuVolumeBrickGridBuffer)
        XCTAssertNotNil(build.gpuVolumeBrickGridIndexBuffer)
        XCTAssertEqual(build.gpuVolumeBrickCount, metadata.brickCount)
        XCTAssertEqual(build.gpuVolumeBrickGridIndexCount, metadata.gridIndexCount)
    }

    func testGPUResidentDirectGridBrickIndicesCoverEditedLocalBounds() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
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
        guard case .gpuSparse(let resource) = result.bundle.storage else {
            return XCTFail("Expected GPU sparse field storage.")
        }

        let centralIndices = try resource.directGridBrickIndices(
            overlappingLocalBoundsMin: SIMD3<Float>(repeating: -0.1),
            localBoundsMax: SIMD3<Float>(repeating: 0.1)
        )
        let expectedCentralIndices: Set<Int> = [
            21, 22, 25, 26,
            37, 38, 41, 42
        ]

        XCTAssertEqual(resource.brickGridDimensions, SIMD3<Int>(repeating: 4))
        XCTAssertEqual(Set(centralIndices), expectedCentralIndices)
        XCTAssertEqual(centralIndices, centralIndices.sorted())
        XCTAssertEqual(
            try resource.directGridBrickIndices(
                overlappingLocalBoundsMin: SIMD3<Float>(repeating: 3),
                localBoundsMax: SIMD3<Float>(repeating: 4)
            ),
            []
        )
        let activeCentralIndices = try resource.directGridBrickIndices(
            overlappingLocalBoundsMin: SIMD3<Float>(repeating: -0.1),
            localBoundsMax: SIMD3<Float>(repeating: 0.1),
            activeOnly: true
        )
        XCTAssertFalse(activeCentralIndices.isEmpty)
        XCTAssertTrue(Set(activeCentralIndices).isSubset(of: expectedCentralIndices))
    }

    func testDistanceFieldBakerProducesSampleScaledDirectGridGPUResidentSparseFieldBundle() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(primitives: [
                    SDFPrimitive(shape: .sphere(radius: 0.55), material: material)
                ]),
                resolution: 12,
                storage: .sparseBricks(brickSize: 4, narrowBand: 0.3, sampleScale: 2),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )

        scene.add(fieldBundle: result.bundle)
        let resource = scene.gpuSparseVolumeInstances[0].resource
        let metadata = try XCTUnwrap(resource.metadataBuffers)
        let gpuGrid = metadata.gridBuffer.contents().bindMemory(to: GPUVolumeBrickGrid.self, capacity: metadata.gridCount)[0]

        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertEqual(resource.dimensions, SIMD3<Int>(repeating: 23))
        XCTAssertEqual(resource.brickSize, SIMD3<Int>(repeating: 8))
        XCTAssertEqual(metadata.brickCount, 27)
        XCTAssertGreaterThan(resource.sampleCount, 27 * 8 * 8 * 8)
        XCTAssertEqual(gpuGrid.dimensionsAndIndexOffset.x, 3)
        XCTAssertEqual(gpuGrid.dimensionsAndIndexOffset.y, 3)
        XCTAssertEqual(gpuGrid.dimensionsAndIndexOffset.z, 3)
        XCTAssertEqual(gpuGrid.brickSizeAndVolume.x, 8)
        XCTAssertEqual(gpuGrid.brickSizeAndVolume.y, 8)
        XCTAssertEqual(gpuGrid.brickSizeAndVolume.z, 8)
    }

    func testDistanceFieldProgramBakesGPUResidentDirectGridSparseFieldBundle() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .length(.init(0), .init(0)),
            .setFloat(.init(1), 0.55),
            .subtractFloat(.init(2), .init(0), .init(1)),
            .emit(distance: .init(2), material: material)
        ])
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 12,
                storage: .sparseBricks(brickSize: 4, narrowBand: 0.28, sampleScale: 2),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )

        scene.add(fieldBundle: result.bundle)
        let resource = scene.gpuSparseVolumeInstances[0].resource
        let metadata = try XCTUnwrap(resource.metadataBuffers)
        let build = try LinearTriangleAccelerationBackend(buildsVolumeBrickBVH: false).build(scene: scene)

        XCTAssertEqual(result.backend, .metalCompute)
        XCTAssertEqual(resource.dimensions, SIMD3<Int>(repeating: 23))
        XCTAssertEqual(resource.brickSize, SIMD3<Int>(repeating: 8))
        XCTAssertTrue(resource.bricks.isEmpty)
        XCTAssertNil(resource.attributeSampleBuffer)
        XCTAssertEqual(resource.attributeSampleCount, 0)
        XCTAssertGreaterThan(metadata.brickCount, 0)
        XCTAssertEqual(metadata.gridCount, 1)
        XCTAssertEqual(
            metadata.gridIndexCount,
            metadata.brickCount + Self.macroGridCount(dimensions: resource.dimensions, brickSize: resource.brickSize)
        )
        let gpuGrid = metadata.gridBuffer.contents().bindMemory(to: GPUVolumeBrickGrid.self, capacity: metadata.gridCount)[0]
        XCTAssertGreaterThan(gpuGrid.macroDimensionsAndIndexOffset.x, 0)
        XCTAssertEqual(gpuGrid.macroDimensionsAndIndexOffset.w, UInt32(metadata.brickCount))
        XCTAssertEqual(gpuGrid.macroSizeAndReserved.x, 4)
        XCTAssertNotNil(build.gpuVolumeBrickSampleBuffer)
        XCTAssertEqual(build.gpuVolumeBrickCount, metadata.brickCount)
    }

    func testDistanceFieldProgramEncodesDirtyDirectGridBrickUpdate() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        guard let commandQueue = renderer.device.makeCommandQueue() else {
            throw XCTSkip("Could not create Metal command queue.")
        }
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.45, 0.2)))
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let program = DistanceFieldProgram(instructions: [
            .loadPosition(.init(0)),
            .length(.init(0), .init(0)),
            .setFloat(.init(1), 0.55),
            .subtractFloat(.init(2), .init(0), .init(1)),
            .emit(distance: .init(2), material: material)
        ])
        let result = try baker.bakeGPUResident(
            DistanceFieldBakeRequest(
                graph: DistanceFieldBakeGraph(program: program),
                resolution: 20,
                storage: .sparseBricks(brickSize: 5, narrowBand: 0.28),
                fallbackMaterial: material
            ),
            metadataMode: .directGridGPU
        )
        guard case .gpuSparse(let resource) = result.bundle.storage,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return XCTFail("Expected GPU sparse field storage and command buffer.")
        }

        try baker.encodeUpdateGPUResidentProgramBricks(
            resource,
            program: program,
            brickIndices: [0, 1, 1],
            narrowBand: 0.28,
            fallbackMaterial: material,
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertNil(commandBuffer.error)
    }

    func testDistanceFieldProgramEncodesDirtyDirectGridAttributeUpdate() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer()
        guard let commandQueue = renderer.device.makeCommandQueue() else {
            throw XCTSkip("Could not create Metal command queue.")
        }
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let layout = DistanceVolumeAttributeLayout(channels: [
            DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge),
            DistanceVolumeAttributeChannel(name: "wetness", semantic: .wetness)
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
        guard case .gpuSparse(let resource) = result.bundle.storage,
              let metadata = resource.metadataBuffers,
              let attributeSampleBuffer = resource.attributeSampleBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return XCTFail("Expected GPU sparse field storage, resident attribute samples, and command buffer.")
        }

        let gridIndices = metadata.gridIndexBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: metadata.gridIndexCount
        )
        let activeBrickIndex = try XCTUnwrap((0..<metadata.brickCount).first { index in
            gridIndices[index] != UInt32.max
        })

        try baker.encodeUpdateGPUResidentProgramBricks(
            resource,
            program: program(growthAge: 0.85, wetness: 0.65),
            brickIndices: [activeBrickIndex],
            narrowBand: 0.28,
            fallbackMaterial: material,
            updatesTopology: false,
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertNil(commandBuffer.error)

        let descriptors = metadata.attributeDescriptorBuffer.contents().bindMemory(
            to: GPUVolumeAttributeDescriptor.self,
            capacity: metadata.attributeDescriptorCount
        )
        let descriptor = descriptors[activeBrickIndex]
        XCTAssertEqual(descriptor.metadata.y, 1)
        XCTAssertEqual(descriptor.semantics0.x, DistanceVolumeAttributeSemantic.growthAge.rawValue)
        XCTAssertEqual(descriptor.semantics0.y, DistanceVolumeAttributeSemantic.wetness.rawValue)
        let samples = attributeSampleBuffer.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: max(resource.attributeSampleCount, 1)
        )
        let attributeSampleIndex = Int(descriptor.metadata.x)
        XCTAssertLessThan(attributeSampleIndex, resource.attributeSampleCount)
        XCTAssertEqual(samples[attributeSampleIndex].x, 0.85, accuracy: 0.00001)
        XCTAssertEqual(samples[attributeSampleIndex].y, 0.65, accuracy: 0.00001)
    }

    func testDistanceFieldBakerFallsBackForAttributeGraphs() throws {
        let renderer = try DenrimRenderer()
        var scene = RenderScene()
        let material = scene.addMaterial(SemanticMaterial.moss())
        let baker = renderer.makeDistanceFieldBaker(preferredBackend: .metalCompute)
        let result = try baker.bake(DistanceFieldBakeRequest(
            graph: DistanceFieldBakeGraph(
                primitives: [
                    SDFPrimitive(
                        shape: .sphere(radius: 0.55),
                        material: material,
                        attributes: DistanceVolumeAttributeValues(["growthAge": 0.75])
                    )
                ],
                attributeLayout: DistanceVolumeAttributeLayout(channels: [
                    DistanceVolumeAttributeChannel(name: "growthAge", semantic: .growthAge)
                ])
            ),
            resolution: 14,
            storage: .dense,
            fallbackMaterial: material
        ))

        XCTAssertEqual(result.backend, .cpuReference)
        scene.add(fieldBundle: result.bundle)
        XCTAssertEqual(scene.volumeInstances.count, 1)
        XCTAssertEqual(scene.volumeInstances[0].volume.attributeLayout.channelCount, 1)
        XCTAssertFalse(scene.volumeInstances[0].volume.attributeSamples.isEmpty)
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

    func testSDFModelSupportsCylinderAndSubtraction() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.8, 0.76)))
        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .box(halfExtents: SIMD3<Float>(0.82, 0.82, 0.82), cornerRadius: 0.08),
                material: material
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.34),
                material: material,
                operation: .subtract
            ),
            SDFPrimitive(
                shape: .cylinder(radius: 0.28, halfHeight: 0.18),
                material: material,
                transform: .translation(SIMD3<Float>(0.48, 0, 0))
            )
        ])

        let volume = try DistanceVolumeBuilder.build(
            model: model,
            settings: DistanceVolumeBuildSettings(resolution: 11)
        )
        let centerIndex = 5 + 5 * 11 + 5 * 11 * 11

        XCTAssertGreaterThan(volume.distances[centerIndex], 0)
        XCTAssertTrue(volume.distances.contains { $0 < 0 })
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
        XCTAssertTrue(compiled.volumeBrickSamples.contains { $0.distance < 0 })
        XCTAssertEqual(compiled.volumeBrickMaterialFieldSamples.count, compiled.volumeBrickSamples.count)
        XCTAssertTrue(compiled.volumeBrickMaterialFieldSamples.contains { sample in
            let colorMatches = sample.baseColorOpacity.x == bakedColor.x
                && sample.baseColorOpacity.y == bakedColor.y
                && sample.baseColorOpacity.z == bakedColor.z
            let surfaceMatches = sample.surface.x == bakedRoughness
                && sample.surface.y == bakedMetallic
            let flags = sample.materialFieldFlags.x
            return colorMatches
                && surfaceMatches
                && flags & DistanceVolumeMaterialFields.baseColorFlag != 0
                && flags & DistanceVolumeMaterialFields.roughnessFlag != 0
                && flags & DistanceVolumeMaterialFields.metallicFlag != 0
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

    func testSparseSDFBuildSampleScaleRefinesBrickPayloadsWithoutMoreCoarseCells() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.15, 0.08)))
        let model = SDFModel(primitives: [
            SDFPrimitive(shape: .sphere(radius: 0.45), material: material)
        ])
        let base = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(
                resolution: 20,
                brickSize: 5,
                narrowBand: 0.35
            )
        )
        let refined = try DistanceVolumeBuilder.buildSparse(
            model: model,
            settings: SparseDistanceVolumeBuildSettings(
                resolution: 20,
                brickSize: 5,
                narrowBand: 0.35,
                sampleScale: 2
            )
        )

        let baseGridDimensions = SIMD3<Int>(
            (base.dimensions.x + base.brickSize.x - 1) / base.brickSize.x,
            (base.dimensions.y + base.brickSize.y - 1) / base.brickSize.y,
            (base.dimensions.z + base.brickSize.z - 1) / base.brickSize.z
        )
        let refinedGridDimensions = SIMD3<Int>(
            (refined.dimensions.x + refined.brickSize.x - 1) / refined.brickSize.x,
            (refined.dimensions.y + refined.brickSize.y - 1) / refined.brickSize.y,
            (refined.dimensions.z + refined.brickSize.z - 1) / refined.brickSize.z
        )

        XCTAssertEqual(baseGridDimensions, refinedGridDimensions)
        XCTAssertEqual(refined.dimensions, SIMD3<Int>(39, 39, 39))
        XCTAssertEqual(refined.brickSize, SIMD3<Int>(10, 10, 10))
        XCTAssertLessThanOrEqual(refined.bricks.count, base.bricks.count)
        XCTAssertGreaterThan(
            refined.bricks.reduce(0) { $0 + $1.distances.count },
            base.bricks.reduce(0) { $0 + $1.distances.count }
        )
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
        let build = try LinearTriangleAccelerationBackend(buildsVolumeBrickBVH: false).build(scene: scene)

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
        let grid = try XCTUnwrap(build.volumeBrickGrids.first)
        XCTAssertGreaterThan(grid.macroDimensionsAndIndexOffset.x, 0)
        XCTAssertGreaterThan(grid.macroDimensionsAndIndexOffset.y, 0)
        XCTAssertGreaterThan(grid.macroDimensionsAndIndexOffset.z, 0)
        XCTAssertEqual(grid.macroSizeAndReserved.x, 4)
        let macroOffset = Int(grid.macroDimensionsAndIndexOffset.w)
        let macroCount = Int(
            grid.macroDimensionsAndIndexOffset.x
                * grid.macroDimensionsAndIndexOffset.y
                * grid.macroDimensionsAndIndexOffset.z
        )
        XCTAssertTrue(build.volumeBrickGridIndices[macroOffset..<(macroOffset + macroCount)].contains(1))
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
        XCTAssertTrue(settings.showsEnvironmentBackground)
        XCTAssertEqual(settings.backgroundColor, SIMD3<Float>(0, 0, 0))
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
