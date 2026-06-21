import XCTest
import simd
@testable import DenrimRendererKit

final class CPUIntersectorTests: XCTestCase {
    func testRayHitsQuad() throws {
        let mesh = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        )
        let material = MaterialID(rawValue: 7)
        let ray = Ray(
            origin: SIMD3<Float>(0, 0, 2),
            direction: SIMD3<Float>(0, 0, -1)
        )

        let hit = try XCTUnwrap(CPUIntersector.closestHit(ray: ray, mesh: mesh, material: material))

        XCTAssertEqual(hit.material, material)
        XCTAssertEqual(hit.distance, 2, accuracy: 0.0001)
        XCTAssertEqual(hit.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(hit.position.y, 0, accuracy: 0.0001)
        XCTAssertEqual(hit.position.z, 0, accuracy: 0.0001)
        XCTAssertEqual(hit.normal.z, 1, accuracy: 0.0001)
    }

    func testRayMissesQuad() {
        let mesh = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        )
        let ray = Ray(
            origin: SIMD3<Float>(2, 0, 2),
            direction: SIMD3<Float>(0, 0, -1)
        )

        XCTAssertNil(CPUIntersector.closestHit(
            ray: ray,
            mesh: mesh,
            material: MaterialID(rawValue: 0)
        ))
    }

    func testRayHitsTranslatedQuad() throws {
        let mesh = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        )
        let ray = Ray(
            origin: SIMD3<Float>(2, 0, 2),
            direction: SIMD3<Float>(0, 0, -1)
        )

        let hit = try XCTUnwrap(CPUIntersector.closestHit(
            ray: ray,
            mesh: mesh,
            material: MaterialID(rawValue: 1),
            transform: .translation(SIMD3<Float>(2, 0, 0))
        ))

        XCTAssertEqual(hit.distance, 2, accuracy: 0.0001)
        XCTAssertEqual(hit.position.x, 2, accuracy: 0.0001)
        XCTAssertEqual(hit.position.z, 0, accuracy: 0.0001)
    }
}
