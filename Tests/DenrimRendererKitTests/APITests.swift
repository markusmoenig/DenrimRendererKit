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
