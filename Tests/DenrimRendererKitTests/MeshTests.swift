import XCTest
import simd
@testable import DenrimRendererKit

final class MeshTests: XCTestCase {
    func testBoxCreatesTwelveTriangles() {
        let mesh = Mesh.box(size: SIMD3<Float>(2, 4, 6))

        XCTAssertEqual(mesh.vertices.count, 8)
        XCTAssertEqual(mesh.indices.count, 36)

        let triangles = mesh.gpuTriangles(material: MaterialID(rawValue: 0))
        XCTAssertEqual(triangles.count, 12)
    }

    func testGPUTrianglesCarryIDs() {
        let triangles = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ).gpuTriangles(
            material: MaterialID(rawValue: 3),
            objectID: 9
        )

        XCTAssertEqual(triangles[0].materialID, 3)
        XCTAssertEqual(triangles[0].objectID, 9)
        XCTAssertEqual(triangles[0].primitiveID, 0)
        XCTAssertEqual(triangles[1].primitiveID, 1)
    }

    func testBoxBoundsMatchInputCorners() {
        let mesh = Mesh.box(
            minimum: SIMD3<Float>(-1, -2, -3),
            maximum: SIMD3<Float>(4, 5, 6)
        )

        XCTAssertEqual(mesh.vertices.map(\.x).min(), -1)
        XCTAssertEqual(mesh.vertices.map(\.x).max(), 4)
        XCTAssertEqual(mesh.vertices.map(\.y).min(), -2)
        XCTAssertEqual(mesh.vertices.map(\.y).max(), 5)
        XCTAssertEqual(mesh.vertices.map(\.z).min(), -3)
        XCTAssertEqual(mesh.vertices.map(\.z).max(), 6)
    }
}
