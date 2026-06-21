import XCTest
import simd
@testable import DenrimRendererKit

final class TransformTests: XCTestCase {
    func testTranslationMovesPoints() {
        let transform = Transform.translation(SIMD3<Float>(2, 3, 4))
        let point = transform.transformPoint(SIMD3<Float>(1, 1, 1))

        XCTAssertEqual(point.x, 3, accuracy: 0.0001)
        XCTAssertEqual(point.y, 4, accuracy: 0.0001)
        XCTAssertEqual(point.z, 5, accuracy: 0.0001)
    }

    func testScaleTransformsNormalWithInverseTranspose() {
        let transform = Transform.scale(SIMD3<Float>(1, 2, 4))
        let normal = simd_normalize(SIMD3<Float>(0, 2, 4))
        let transformed = transform.transformNormal(normal)

        XCTAssertEqual(transformed.x, 0, accuracy: 0.0001)
        XCTAssertEqual(transformed.y, transformed.z, accuracy: 0.0001)
    }

    func testSceneCompilationBakesInstanceTransform() throws {
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(1, 1, 1)))
        scene.add(
            mesh: .quad(
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(1, 1, 0),
                SIMD3<Float>(0, 1, 0)
            ),
            material: material,
            transform: .translation(SIMD3<Float>(2, 0, 0))
        )

        let compiled = try scene.compileForGPU()

        XCTAssertEqual(compiled.triangles.count, 2)
        XCTAssertEqual(compiled.triangles[0].v0.x, 2, accuracy: 0.0001)
        XCTAssertEqual(compiled.triangles[0].v1.x, 3, accuracy: 0.0001)
        XCTAssertEqual(compiled.triangles[0].v2.x, 3, accuracy: 0.0001)
        XCTAssertEqual(compiled.triangles[0].objectID, 0)
        XCTAssertEqual(compiled.instanceAcceleration.instances.count, 1)
        XCTAssertEqual(compiled.instanceAcceleration.instances[0].worldBounds.minimum.x, 2, accuracy: 0.0001)
        XCTAssertEqual(compiled.instanceAcceleration.instances[0].worldBounds.maximum.x, 3, accuracy: 0.0001)
        XCTAssertFalse(compiled.instanceAcceleration.topLevelBVH.isEmpty)
    }
}
