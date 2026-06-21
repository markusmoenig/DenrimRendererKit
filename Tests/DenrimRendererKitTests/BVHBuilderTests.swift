import XCTest
import simd
@testable import DenrimRendererKit

final class BVHBuilderTests: XCTestCase {
    func testEmptyBVHBuildsWithoutNodes() {
        let bvh = BVHBuilder().build(triangles: [])

        XCTAssertTrue(bvh.isEmpty)
        XCTAssertTrue(bvh.primitiveIndices.isEmpty)
    }

    func testSmallBVHBuildsSingleLeaf() {
        let triangles = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ).gpuTriangles(material: MaterialID(rawValue: 0))

        let bvh = BVHBuilder(maxLeafPrimitiveCount: 4).build(triangles: triangles)

        XCTAssertEqual(bvh.nodes.count, 1)
        XCTAssertTrue(bvh.nodes[0].isLeaf)
        XCTAssertEqual(bvh.nodes[0].primitiveCount, 2)
        XCTAssertEqual(bvh.primitiveIndices.sorted(), [0, 1])
    }

    func testBVHSplitsLargePrimitiveSet() {
        var triangles: [GPUTriangle] = []
        for x in 0..<8 {
            triangles.append(contentsOf: Mesh.quad(
                SIMD3<Float>(Float(x), 0, 0),
                SIMD3<Float>(Float(x) + 0.5, 0, 0),
                SIMD3<Float>(Float(x) + 0.5, 0.5, 0),
                SIMD3<Float>(Float(x), 0.5, 0)
            ).gpuTriangles(material: MaterialID(rawValue: 0)))
        }

        let bvh = BVHBuilder(maxLeafPrimitiveCount: 2).build(triangles: triangles)

        XCTAssertFalse(bvh.nodes[0].isLeaf)
        XCTAssertGreaterThan(bvh.nodes.count, 1)
        XCTAssertEqual(bvh.primitiveIndices.sorted(), Array(triangles.indices))
        XCTAssertLessThanOrEqual(maxLeafPrimitiveCount(in: bvh), 2)
        XCTAssertEqual(bvh.nodes[0].bounds.minimum.x, 0, accuracy: 0.0001)
        XCTAssertEqual(bvh.nodes[0].bounds.maximum.x, 7.5, accuracy: 0.0001)
    }

    private func maxLeafPrimitiveCount(in bvh: BVH) -> Int {
        bvh.nodes
            .filter(\.isLeaf)
            .map(\.primitiveCount)
            .max() ?? 0
    }
}
