import XCTest
import simd
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

    func testInstanceAccelerationBuildsTopLevelInstanceBounds() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(1, 1, 1)))
        let box = Mesh.box(size: SIMD3<Float>(1, 1, 1))

        scene.add(mesh: box, material: material, transform: .translation(SIMD3<Float>(-2, 0, 0)))
        scene.add(mesh: box, material: material, transform: .translation(SIMD3<Float>(2, 0, 0)))

        let acceleration = try InstanceAccelerationBuilder().build(scene: scene)
        let triangles = acceleration.materializedTriangles()

        XCTAssertEqual(acceleration.meshes.count, 2)
        XCTAssertEqual(acceleration.instances.count, 2)
        XCTAssertFalse(acceleration.meshes[0].localBVH.isEmpty)
        XCTAssertFalse(acceleration.topLevelBVH.isEmpty)
        XCTAssertEqual(acceleration.topLevelBVH.nodes[0].boundsMin.x, -2.5, accuracy: 0.0001)
        XCTAssertEqual(acceleration.topLevelBVH.nodes[0].boundsMax.x, 2.5, accuracy: 0.0001)
        XCTAssertEqual(Set(triangles.map(\.objectID)), [0, 1])
    }
}
