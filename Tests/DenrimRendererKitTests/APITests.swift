import XCTest
@testable import DenrimRendererKit

final class APITests: XCTestCase {
    func testCornellBoxSceneCompiles() throws {
        let scene = RenderScene.cornellBox()

        XCTAssertEqual(scene.materials.count, 4)
        XCTAssertEqual(scene.meshInstances.count, 6)
    }

    func testMaterialReferenceSceneCompiles() throws {
        let scene = RenderScene.materialReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 8)
        XCTAssertEqual(scene.meshInstances.count, 8)
        XCTAssertEqual(compiled.triangles.count, 66)
        XCTAssertTrue(scene.materials.contains { $0.metallic > 0 })
        XCTAssertTrue(scene.materials.contains { $0.roughness < 0.2 })
    }

    func testSettingsDefaultsAreSmallAndProgressive() {
        let settings = RenderSettings()

        XCTAssertEqual(settings.width, 512)
        XCTAssertEqual(settings.height, 512)
        XCTAssertEqual(settings.maxBounces, 4)
        XCTAssertEqual(settings.quality, .preview)
    }
}
