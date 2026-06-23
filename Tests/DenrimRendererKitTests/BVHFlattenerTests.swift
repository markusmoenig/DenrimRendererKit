import simd
import Metal
import XCTest
@testable import DenrimRendererKit

final class BVHFlattenerTests: XCTestCase {
    func testFlattenedLeafStoresPrimitiveRange() {
        let triangles = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ).gpuTriangles(material: MaterialID(rawValue: 0))
        let bvh = BVHBuilder(maxLeafPrimitiveCount: 4).build(triangles: triangles)

        let flat = BVHFlattener().flatten(bvh)

        XCTAssertEqual(flat.nodes.count, 1)
        XCTAssertEqual(flat.primitiveIndices, [0, 1])
        XCTAssertEqual(flat.nodes[0].metadata.x, 0)
        XCTAssertEqual(flat.nodes[0].metadata.y, 0)
        XCTAssertEqual(flat.nodes[0].metadata.z, 0)
        XCTAssertEqual(flat.nodes[0].metadata.w, 2)
        XCTAssertEqual(flat.nodes[0].boundsMin.x, -1, accuracy: 0.0001)
        XCTAssertEqual(flat.nodes[0].boundsMax.x, 1, accuracy: 0.0001)
    }

    func testFlattenedInteriorStoresChildIndices() {
        var triangles: [GPUTriangle] = []
        for x in 0..<4 {
            triangles.append(contentsOf: Mesh.quad(
                SIMD3<Float>(Float(x), 0, 0),
                SIMD3<Float>(Float(x) + 0.5, 0, 0),
                SIMD3<Float>(Float(x) + 0.5, 0.5, 0),
                SIMD3<Float>(Float(x), 0.5, 0)
            ).gpuTriangles(material: MaterialID(rawValue: 0)))
        }
        let bvh = BVHBuilder(maxLeafPrimitiveCount: 2).build(triangles: triangles)

        let flat = BVHFlattener().flatten(bvh)

        XCTAssertGreaterThan(flat.nodes.count, 1)
        XCTAssertEqual(flat.nodes[0].metadata.x, UInt32(bvh.nodes[0].leftChild))
        XCTAssertEqual(flat.nodes[0].metadata.y, UInt32(bvh.nodes[0].rightChild))
        XCTAssertEqual(flat.nodes[0].metadata.w, 0)
        XCTAssertEqual(flat.primitiveIndices.sorted(), Array(0..<UInt32(triangles.count)))
    }

    func testAccelerationBackendBuildsFlatBVH() throws {
        let build = try LinearTriangleAccelerationBackend().build(scene: .cornellBox())

        XCTAssertFalse(build.bvh.isEmpty)
        XCTAssertFalse(build.instanceAcceleration.topLevelBVH.isEmpty)
        XCTAssertEqual(build.instanceAcceleration.instances.count, 6)
        XCTAssertEqual(build.triangles.count, build.bvh.primitiveIndices.count)
        XCTAssertEqual(build.bvh.nodes[0].boundsMin.x, -1, accuracy: 0.0001)
        XCTAssertEqual(build.bvh.nodes[0].boundsMax.y, 2, accuracy: 0.0001)
    }

    func testAccelerationBackendBuildsEmissiveTriangleLightList() throws {
        var scene = RenderScene()
        let matte = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.8, 0.8)))
        let light = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            emission: SIMD3<Float>(1, 0.8, 0.6),
            emissionStrength: 4
        ))

        scene.add(mesh: Mesh.quad(
            SIMD3<Float>(-1, 0, 1),
            SIMD3<Float>(1, 0, 1),
            SIMD3<Float>(1, 0, -1),
            SIMD3<Float>(-1, 0, -1)
        ), material: matte)
        scene.add(mesh: Mesh.quad(
            SIMD3<Float>(-0.5, 1, -0.5),
            SIMD3<Float>(0.5, 1, -0.5),
            SIMD3<Float>(0.5, 1, 0.5),
            SIMD3<Float>(-0.5, 1, 0.5)
        ), material: light)

        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

        XCTAssertEqual(build.triangles.count, 4)
        XCTAssertEqual(build.lights.map(\.triangleIndex), [2, 3])
        XCTAssertTrue(build.lights.allSatisfy { light in
            build.materials[Int(light.materialIndex)].emission.x > 0
        })
        XCTAssertTrue(build.lights.allSatisfy { abs($0.area - 0.5) < 0.0001 })
        XCTAssertTrue(build.lights.allSatisfy { $0.normal.y < -0.99 })
    }

    func testAccelerationBackendLeavesLightListEmptyWithoutEmission() throws {
        var scene = RenderScene()
        let matte = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.8, 0.8)))

        scene.add(mesh: Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ), material: matte)

        let build = try LinearTriangleAccelerationBackend().build(scene: scene)

        XCTAssertEqual(build.triangles.count, 2)
        XCTAssertTrue(build.lights.isEmpty)
    }

    func testInstanceAccelerationBuildsTopLevelInstanceBounds() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(1, 1, 1)))
        let box = Mesh.box(size: SIMD3<Float>(1, 1, 1))

        scene.add(mesh: box, material: material, transform: .translation(SIMD3<Float>(-2, 0, 0)))
        scene.add(mesh: box, material: material, transform: .translation(SIMD3<Float>(2, 0, 0)))

        let acceleration = try InstanceAccelerationBuilder().build(scene: scene)
        let triangles = acceleration.materializedTriangles()

        XCTAssertEqual(acceleration.meshes.count, 1)
        XCTAssertEqual(acceleration.instances.count, 2)
        XCTAssertFalse(acceleration.meshes[0].localBVH.isEmpty)
        XCTAssertFalse(acceleration.topLevelBVH.isEmpty)
        XCTAssertEqual(acceleration.topLevelBVH.nodes[0].boundsMin.x, -2.5, accuracy: 0.0001)
        XCTAssertEqual(acceleration.topLevelBVH.nodes[0].boundsMax.x, 2.5, accuracy: 0.0001)
        XCTAssertEqual(Set(triangles.map(\.objectID)), [0, 1])
    }

    func testInstanceAccelerationCanSkipLocalBVHForHardwarePath() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(1, 1, 1)))
        let box = Mesh.box(size: SIMD3<Float>(1, 1, 1))

        scene.add(mesh: box, material: material, transform: .translation(SIMD3<Float>(0, 0, 0)))

        let acceleration = try InstanceAccelerationBuilder(buildsLocalBVH: false).build(scene: scene)
        let triangles = acceleration.materializedTriangles()

        XCTAssertEqual(acceleration.meshes.count, 1)
        XCTAssertTrue(acceleration.meshes[0].localBVH.isEmpty)
        XCTAssertFalse(acceleration.topLevelBVH.isEmpty)
        XCTAssertEqual(triangles.count, 12)
        XCTAssertEqual(Set(triangles.map(\.objectID)), [0])
    }

    func testInstanceAccelerationReusesIdenticalMeshRecords() throws {
        var scene = RenderScene()
        let red = scene.addMaterial(Material(baseColor: SIMD3<Float>(1, 0, 0)))
        let blue = scene.addMaterial(Material(baseColor: SIMD3<Float>(0, 0, 1)))
        let sharedMesh = Mesh.box(size: SIMD3<Float>(1, 1, 1))

        scene.add(mesh: sharedMesh, material: red, transform: .translation(SIMD3<Float>(-1, 0, 0)))
        scene.add(mesh: sharedMesh, material: blue, transform: .translation(SIMD3<Float>(1, 0, 0)))

        let acceleration = try InstanceAccelerationBuilder().build(scene: scene)
        let triangles = acceleration.materializedTriangles()

        XCTAssertEqual(acceleration.meshes.count, 1)
        XCTAssertEqual(acceleration.instances.count, 2)
        XCTAssertEqual(Set(triangles.map(\.materialID)), [red.rawValue, blue.rawValue])
        XCTAssertEqual(Set(triangles.map(\.objectID)), [0, 1])
    }

    func testMetalRayTracingBackendReportsAccelerationStructurePlans() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let build = try MetalRayTracingAccelerationBackend(device: device).build(scene: .cornellBox())
        let experiment = try XCTUnwrap(build.metalRayTracingExperiment)

        XCTAssertEqual(build.triangles.count, build.bvh.primitiveIndices.count)
        XCTAssertEqual(experiment.supportsRayTracing, device.supportsRaytracing)

        if device.supportsRaytracing {
            XCTAssertEqual(experiment.blasPlans.count, build.instanceAcceleration.meshes.count)
            XCTAssertEqual(experiment.blasResources.count, build.instanceAcceleration.meshes.count)
            XCTAssertEqual(experiment.tlasPlan?.instanceCount, build.instanceAcceleration.instances.count)
            XCTAssertNotNil(experiment.tlasResource)
            XCTAssertEqual(experiment.sceneBuffers?.instanceCount, build.instanceAcceleration.instances.count)
            XCTAssertEqual(experiment.sceneBuffers?.localTriangleCount, build.instanceAcceleration.meshes.reduce(0) {
                $0 + $1.localTriangles.count
            })
            XCTAssertGreaterThan(experiment.totalAccelerationStructureSize, 0)
            XCTAssertGreaterThan(experiment.totalBuildScratchBufferSize, 0)
            XCTAssertTrue(experiment.blasPlans.allSatisfy { $0.triangleCount > 0 })
            XCTAssertTrue(experiment.blasResources.allSatisfy { $0.accelerationStructure.size > 0 })
            XCTAssertGreaterThan(experiment.tlasResource?.accelerationStructure.size ?? 0, 0)
        } else {
            XCTAssertTrue(experiment.blasPlans.isEmpty)
            XCTAssertTrue(experiment.blasResources.isEmpty)
            XCTAssertNil(experiment.tlasPlan)
            XCTAssertNil(experiment.tlasResource)
            XCTAssertNil(experiment.sceneBuffers)
        }
    }
}
