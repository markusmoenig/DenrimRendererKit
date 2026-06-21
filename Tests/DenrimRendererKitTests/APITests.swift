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

    func testMaterialVariantReferenceSceneCompiles() throws {
        let scene = RenderScene.materialVariantReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 8)
        XCTAssertEqual(scene.meshInstances.count, 8)
        XCTAssertEqual(compiled.triangles.count, 66)
        XCTAssertTrue(scene.materials.contains { $0.metallic > 0 })
        XCTAssertTrue(scene.materials.contains { $0.clearcoat > 0 })
    }

    func testTransparentMaterialReferenceSceneCompiles() throws {
        let scene = RenderScene.transparentMaterialReference()
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 7)
        XCTAssertEqual(scene.meshInstances.count, 7)
        XCTAssertEqual(compiled.triangles.count, 34)
        XCTAssertTrue(scene.materials.contains { $0.opacity == 0 })
        XCTAssertTrue(scene.materials.contains { $0.opacity > 0 && $0.opacity < 1 })
        XCTAssertTrue(scene.materials.contains { $0.emissionStrength > 0 })
    }

    func testMaterialSpecularClearcoatAndIORReachGPUParameters() {
        let material = Material(
            baseColor: .init(0.8, 0.7, 0.6),
            roughness: 0.35,
            metallic: 0.2,
            specular: 0.6,
            specularColor: .init(0.9, 0.7, 0.5),
            indexOfRefraction: 1.8,
            clearcoat: 0.4,
            clearcoatRoughness: 0.08,
            clearcoatIndexOfRefraction: 1.6
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
    }

    func testSettingsDefaultsAreSmallAndProgressive() {
        let settings = RenderSettings()

        XCTAssertEqual(settings.width, 512)
        XCTAssertEqual(settings.height, 512)
        XCTAssertEqual(settings.maxBounces, 4)
        XCTAssertEqual(settings.quality, .preview)
        XCTAssertFalse(settings.transparentBackground)
    }
}
