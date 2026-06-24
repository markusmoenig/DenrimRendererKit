import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd
import UniformTypeIdentifiers
import XCTest
@testable import DenrimRendererKit

final class SceneScriptTests: XCTestCase {
    func testSceneScriptBuildsRenderableScene() throws {
        let source = """
        # Small scripted material test scene
        camera 0 1.4 4.0 0 0.6 0 42
        material floor 0.7 0.7 0.65
        material red 0.9 0.2 0.1
        material light 1 1 1 1 0.9 0.7 8
        quad floor -2 0 2 2 0 2 2 0 -2 -2 0 -2
        quad light -0.4 2 -0.4 0.4 2 -0.4 0.4 2 0.4 -0.4 2 0.4
        box red 0 0.3 0 0.6 0.6 0.6 0.4
        """

        let scene = try SceneScript.parse(source)
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 3)
        XCTAssertEqual(scene.meshInstances.count, 3)
        XCTAssertEqual(compiled.triangles.count, 16)
        XCTAssertEqual(scene.camera.verticalFieldOfViewDegrees, 42)
    }

    func testSceneScriptIgnoresCommentsAndBlankLines() throws {
        let source = """

        # comment only
        camera 0 0 1 0 0 0 45
        material white 1 1 1 # inline comment
        quad white -1 0 0 1 0 0 1 1 0 -1 1 0
        """

        let scene = try SceneScript.parse(source)

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertEqual(scene.meshInstances.count, 1)
    }

    func testSceneScriptParsesNamedGroupedGeometryArguments() throws {
        let source = """
        camera origin(0, 1.4, 4.0) target(0, 0.6, 0) fov(42)
        mesh subject fixture.ply
        material floor 0.7 0.7 0.65
        material clay 0.82 0.42 0.26 roughness 0.8
        quad floor a(-2, 0, 2) b(2, 0, 2) c(2, 0, -2) d(-2, 0, -2) uvA(0, 0) uvB(4, 0) uvC(4, 4) uvD(0, 4)
        box clay position(0, 0.3, 0) size(0.6, 0.6, 0.6) rotationY(0.4)
        instance mesh(subject) material(clay) position(0.5, 0, -0.25) scale(1.5, 1.5, 1.5) rotationY(0.25)
        """

        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptNamedGroups", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try writeFixturePLY(url: baseURL.appendingPathComponent("fixture.ply"))

        let scene = try SceneScript.parse(source, baseURL: baseURL)
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.camera.verticalFieldOfViewDegrees, 42)
        XCTAssertEqual(scene.materials.count, 2)
        XCTAssertEqual(scene.meshInstances.count, 3)
        XCTAssertEqual(scene.meshInstances[0].mesh.texcoords[1].x, 4, accuracy: 0.0001)
        XCTAssertEqual(scene.meshInstances[0].mesh.texcoords[2].y, 4, accuracy: 0.0001)
        XCTAssertEqual(compiled.triangles.count, 16)
    }

    func testSceneScriptParsesMaterialParameters() throws {
        let source = """
        material compact 0.8 0.7 0.5 roughness 0.22 metallic 1
        material brushed 0.8 0.7 0.5 roughness 0.22 metallic 1 opacity 0.9
        material glow 1 1 1 emission 1 0.8 0.4 6
        material glassy 0.8 0.9 1 specular 0.7 specularColor 0.9 0.8 0.7 ior 1.62 anisotropy 0.55 transmission 0.85 transmissionColor 0.45 0.72 1 transmissionRoughness 0.12 transmissionIOR 1.38 absorptionColor 0.5 0.75 1 absorptionDistance 1.4 volumeScattering 0.68 volumeScatteringColor 0.82 0.88 0.96 volumeScatteringDistance 0.45 volumeAnisotropy 0.25 clearcoat 0.45 clearcoatColor 0.7 0.92 1 clearcoatAttenuationColor 0.62 0.78 0.94 clearcoatThickness 0.35 clearcoatRoughness 0.08 clearcoatIOR 1.58 thinFilm 0.7 thinFilmThickness 510 thinFilmIOR 1.42
        material fabric 0.35 0.2 0.8 sheen 0.6 sheenColor 0.9 0.72 1 sheenRoughness 0.75 subsurface 0.65 subsurfaceColor 0.9 0.35 0.22 subsurfaceRadius 1.0 0.42 0.18 subsurfaceScale 0.3 subsurfaceAnisotropy 0.12
        material sourceGlass 0.7 0.8 0.8 spectrans 1 thinWalled 1 fuzz 0.4 fuzzColor 0.7 0.8 0.9 fuzzRoughness 0.65
        """

        let scene = try SceneScript.parse(source)

        XCTAssertEqual(scene.materials.count, 6)
        XCTAssertEqual(scene.materials[0].roughness, 0.22, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[0].metallic, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[1].opacity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[2].emissionStrength, 6, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].specular, 0.7, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].specularColor.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].specularColor.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].specularColor.z, 0.7, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].indexOfRefraction, 1.62, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].specularAnisotropy, 0.55, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmission, 0.85, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionColor.x, 0.45, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionColor.y, 0.72, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionColor.z, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionRoughness, 0.12, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionIndexOfRefraction, 1.38, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionAbsorptionColor.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionAbsorptionColor.y, 0.75, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionAbsorptionColor.z, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].transmissionAbsorptionDistance, 1.4, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].volumeScattering, 0.68, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].volumeScatteringColor.x, 0.82, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].volumeScatteringColor.y, 0.88, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].volumeScatteringColor.z, 0.96, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].volumeScatteringDistance, 0.45, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].volumeAnisotropy, 0.25, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoat, 0.45, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoatColor.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoatColor.y, 0.92, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoatColor.z, 1, accuracy: 0.0001)
        let clearcoatAttenuationColor = try XCTUnwrap(scene.materials[3].clearcoatAttenuationColor)
        XCTAssertEqual(clearcoatAttenuationColor.x, 0.62, accuracy: 0.0001)
        XCTAssertEqual(clearcoatAttenuationColor.y, 0.78, accuracy: 0.0001)
        XCTAssertEqual(clearcoatAttenuationColor.z, 0.94, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoatThickness, 0.35, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoatRoughness, 0.08, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].clearcoatIndexOfRefraction, 1.58, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].thinFilm, 0.7, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].thinFilmThicknessNanometers, 510, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].thinFilmIndexOfRefraction, 1.42, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].sheen, 0.6, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].sheenColor.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].sheenColor.y, 0.72, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].sheenColor.z, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].sheenRoughness, 0.75, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurface, 0.65, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceColor.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceColor.y, 0.35, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceColor.z, 0.22, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceRadius.x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceRadius.y, 0.42, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceRadius.z, 0.18, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceScale, 0.3, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[4].subsurfaceAnisotropy, 0.12, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[5].transmission, 1, accuracy: 0.0001)
        XCTAssertTrue(scene.materials[5].thinWalled)
        XCTAssertEqual(scene.materials[5].sheen, 0.4, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[5].sheenColor.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[5].sheenColor.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[5].sheenColor.z, 0.9, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[5].sheenRoughness, 0.65, accuracy: 0.0001)
    }

    func testSceneScriptParsesRenderDefaults() throws {
        let source = """
        render output ./beauty.png outputType normal size hd spp 512 quality final maxBounces 10 backend metal-ray-tracing sampleRadianceClamp 48 transparentBackground denoise simple
        """

        let scene = try SceneScript.parse(source)
        let defaults = scene.renderDefaults

        XCTAssertEqual(defaults.outputPath, "./beauty.png")
        if case .normal? = defaults.output {
        } else {
            XCTFail("Expected normal output default.")
        }
        XCTAssertEqual(defaults.width, 1280)
        XCTAssertEqual(defaults.height, 720)
        XCTAssertEqual(defaults.samples, 512)
        if case .final? = defaults.quality {
        } else {
            XCTFail("Expected final quality default.")
        }
        XCTAssertEqual(defaults.maxBounces, 10)
        XCTAssertEqual(defaults.accelerationMode?.rawValue, RenderAccelerationMode.metalRayTracing.rawValue)
        XCTAssertEqual(try XCTUnwrap(defaults.sampleRadianceClamp), 48, accuracy: 0.0001)
        XCTAssertEqual(defaults.transparentBackground, true)
        XCTAssertEqual(defaults.denoise?.denoiser, .simpleSpatial)
    }

    func testSceneScriptFileRenderDefaultOutputResolvesRelativeToScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("denrim-render-defaults-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sceneURL = directory.appendingPathComponent("scene.denrim")
        try "render output ../Renders/DiningRoom.png size 64 samples 2\n".write(to: sceneURL, atomically: true, encoding: .utf8)

        let scene = try SceneScript.parse(contentsOf: sceneURL)

        XCTAssertEqual(
            scene.renderDefaults.outputPath,
            directory.deletingLastPathComponent()
                .appendingPathComponent("Renders/DiningRoom.png")
                .path
        )
        XCTAssertEqual(scene.renderDefaults.width, 64)
        XCTAssertEqual(scene.renderDefaults.height, 64)
        XCTAssertEqual(scene.renderDefaults.samples, 2)
    }

    func testSceneScriptParsesBuiltInMaterialPresets() throws {
        let source = """
        material glass preset glass.thin-pane roughness 0.03
        material aluminum builtin metal.brushed_aluminum anisotropy 0.4
        material amber built-in coating.iridescent-amber thinFilmThickness 470
        material warm built-in emission.warm-panel emission 1 0.85 0.6 8
        """

        let scene = try SceneScript.parse(source)

        XCTAssertEqual(scene.materials.count, 4)
        XCTAssertEqual(scene.materials[0].transmission, 1, accuracy: 0.0001)
        XCTAssertTrue(scene.materials[0].thinWalled)
        XCTAssertEqual(scene.materials[0].roughness, 0.03, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[1].metallic, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[1].specularAnisotropy, 0.4, accuracy: 0.0001)
        XCTAssertGreaterThan(scene.materials[2].thinFilm, 0)
        XCTAssertEqual(scene.materials[2].thinFilmThicknessNanometers, 470, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[3].emissionStrength, 8, accuracy: 0.0001)
    }

    func testSceneScriptParsesMaterialTextureBindings() throws {
        let source = """
        texture checker checker 1 0 0 1 0 0 1 1 linear
        texture tangentRight solid 1 0.5 0.5 1 nearest
        material textured 1 1 1 roughness 0.7 baseColorTexture checker normalMap tangentRight
        """

        let scene = try SceneScript.parse(source)

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertEqual(scene.materials[0].baseColorTexture, .checker(
            SIMD4<Float>(1, 0, 0, 1),
            SIMD4<Float>(0, 0, 1, 1),
            samplingMode: .linear
        ))
        XCTAssertEqual(scene.materials[0].normalMap, .solid(SIMD4<Float>(1, 0.5, 0.5, 1)))
    }

    func testSceneScriptCanDeriveNormalMapFromTexture() throws {
        let source = """
        texture height checker 0 0 0 1 1 1 1 1 linear
        texture derived normalFrom height strength 0.8
        material wood 1 1 1 baseColorTexture height normalMap derived
        """

        let scene = try SceneScript.parse(source)
        let normalMap = try XCTUnwrap(scene.materials[0].normalMap)

        XCTAssertEqual(normalMap.width, 2)
        XCTAssertEqual(normalMap.height, 2)
        XCTAssertEqual(normalMap.samplingMode, .linear)
        XCTAssertNotEqual(normalMap.pixels[0], SIMD4<Float>(0.5, 0.5, 1, 1))
    }

    func testSceneScriptLoadsImageTextureRelativeToBaseURL() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptImageTexture", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        _ = try writeFixturePNG(
            url: baseURL.appendingPathComponent("albedo.png"),
            width: 2,
            height: 1,
            rgba: [
                255, 0, 0, 255,
                0, 0, 255, 128
            ]
        )

        let source = """
        texture albedo image albedo.png color linear sampler nearest
        material textured 1 1 1 baseColorTexture albedo
        """

        let scene = try SceneScript.parse(source, baseURL: baseURL)
        let texture = try XCTUnwrap(scene.materials[0].baseColorTexture)

        XCTAssertEqual(texture.width, 2)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.samplingMode, .nearest)
        XCTAssertEqual(texture.pixels[0], SIMD4<Float>(1, 0, 0, 1))
        XCTAssertEqual(texture.pixels[1].z, 1, accuracy: 0.004)
        XCTAssertEqual(texture.pixels[1].w, Float(128) / 255, accuracy: 0.004)
    }

    func testSceneScriptLoadsEnvironmentImageRelativeToBaseURL() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptEnvironment", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try writeFixtureHDR(
            url: baseURL.appendingPathComponent("studio.hdr"),
            width: 1,
            height: 1,
            rgbe: [128, 64, 32, 129]
        )

        let scene = try SceneScript.parse(
            "environment image studio.hdr intensity 0.75 rotationY 1.5 maxRadiance 4",
            baseURL: baseURL
        )

        let texture = try XCTUnwrap(scene.environment.texture)
        XCTAssertEqual(texture.width, 1)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(scene.environment.intensity, 0.75, accuracy: 0.0001)
        XCTAssertEqual(scene.environment.rotationY, 1.5, accuracy: 0.0001)
        XCTAssertEqual(scene.environment.maxRadiance, 4, accuracy: 0.0001)
        XCTAssertEqual(texture.pixels[0].x, 1, accuracy: 0.001)
        XCTAssertEqual(texture.pixels[0].y, 0.5, accuracy: 0.001)
        XCTAssertEqual(texture.pixels[0].z, 0.25, accuracy: 0.001)
    }

    func testSceneScriptAssetCacheReusesDecodedImageTexturesUntilCleared() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptTextureCache", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let textureURL = baseURL.appendingPathComponent("albedo.png")
        let cache = SceneAssetCache()
        let source = """
        texture albedo image albedo.png color linear sampler nearest
        material textured 1 1 1 baseColorTexture albedo
        """

        _ = try writeFixturePNG(
            url: textureURL,
            width: 1,
            height: 1,
            rgba: [255, 0, 0, 255]
        )
        let firstScene = try SceneScript.parse(source, baseURL: baseURL, assetCache: cache)
        let firstTexture = try XCTUnwrap(firstScene.materials[0].baseColorTexture)
        XCTAssertEqual(firstTexture.pixels[0], SIMD4<Float>(1, 0, 0, 1))

        _ = try writeFixturePNG(
            url: textureURL,
            width: 1,
            height: 1,
            rgba: [0, 0, 255, 255]
        )
        let cachedScene = try SceneScript.parse(source, baseURL: baseURL, assetCache: cache)
        let cachedTexture = try XCTUnwrap(cachedScene.materials[0].baseColorTexture)
        XCTAssertEqual(cachedTexture.pixels[0], SIMD4<Float>(1, 0, 0, 1))

        cache.removeAll()
        let reloadedScene = try SceneScript.parse(source, baseURL: baseURL, assetCache: cache)
        let reloadedTexture = try XCTUnwrap(reloadedScene.materials[0].baseColorTexture)
        XCTAssertEqual(reloadedTexture.pixels[0], SIMD4<Float>(0, 0, 1, 1))
    }

    func testSceneScriptLoadsMeshRelativeToBaseURL() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptMesh", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try writeFixturePLY(url: baseURL.appendingPathComponent("dragon.ply"))

        let source = """
        camera 0 0 3 0 0 0 34
        mesh dragon dragon.ply
        material clay 0.82 0.42 0.26 roughness 0.8
        instance dragon clay 0 0 0 1 1 1 0.25
        """

        let scene = try SceneScript.parse(source, baseURL: baseURL)
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertEqual(scene.meshInstances.count, 1)
        XCTAssertEqual(compiled.triangles.count, 2)
    }

    func testSceneScriptAssetCacheReusesDecodedMeshesUntilCleared() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptMeshCache", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let meshURL = baseURL.appendingPathComponent("fixture.ply")
        let cache = SceneAssetCache()
        let source = """
        mesh fixture fixture.ply
        material clay 0.8 0.7 0.6
        instance fixture clay 0 0 0 1 1 1
        """

        try writeFixturePLY(url: meshURL, halfExtent: 0.5)
        let firstScene = try SceneScript.parse(source, baseURL: baseURL, assetCache: cache)
        XCTAssertEqual(firstScene.meshInstances[0].mesh.vertices[0].x, -0.5, accuracy: 0.0001)

        try writeFixturePLY(url: meshURL, halfExtent: 2.0)
        let cachedScene = try SceneScript.parse(source, baseURL: baseURL, assetCache: cache)
        XCTAssertEqual(cachedScene.meshInstances[0].mesh.vertices[0].x, -0.5, accuracy: 0.0001)

        cache.removeAll()
        let reloadedScene = try SceneScript.parse(source, baseURL: baseURL, assetCache: cache)
        XCTAssertEqual(reloadedScene.meshInstances[0].mesh.vertices[0].x, -2.0, accuracy: 0.0001)
    }

    func testSceneScriptTexturedSceneRendersAOVs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let source = """
        camera 0 0 3 0 0 0 34
        texture checker checker 1 0 0 1 0 0 1 1
        texture tangentRight solid 1 0.5 0.5 1
        material textured 1 1 1 roughness 0.7 baseColorTexture checker normalMap tangentRight
        quad textured -1 -1 0 1 -1 0 1 1 0 -1 1 0
        """
        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: SceneScript.parse(source),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }
        let normals = try session.pixels(for: .normal).filter { $0.a > 0 }

        XCTAssertTrue(albedo.contains { $0.r > 0.9 && $0.g < 0.1 && $0.b < 0.1 })
        XCTAssertTrue(albedo.contains { $0.r < 0.1 && $0.g < 0.1 && $0.b > 0.9 })
        XCTAssertTrue(normals.contains { pixel in
            pixel.r > 0.9
                && pixel.g > 0.4 && pixel.g < 0.6
                && pixel.b > 0.4 && pixel.b < 0.6
        })
    }

    func testSceneScriptImageTextureRendersAlbedoAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptImageRender", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        _ = try writeFixturePNG(
            url: baseURL.appendingPathComponent("checker.png"),
            width: 2,
            height: 2,
            rgba: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )

        let source = """
        camera 0 0 3 0 0 0 34
        texture imageChecker image checker.png color linear sampler nearest
        material textured 1 1 1 baseColorTexture imageChecker
        quad textured -1 -1 0 1 -1 0 1 1 0 -1 1 0
        """
        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: SceneScript.parse(source, baseURL: baseURL),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }

        XCTAssertTrue(albedo.contains { $0.r > 0.9 && $0.g < 0.1 && $0.b < 0.1 })
        XCTAssertTrue(albedo.contains { $0.r < 0.1 && $0.g > 0.9 && $0.b < 0.1 })
        XCTAssertTrue(albedo.contains { $0.r < 0.1 && $0.g < 0.1 && $0.b > 0.9 })
    }

    func testSceneScriptIncludesReusableFragments() throws {
        let source = """
        camera 0 1 4 0 0.5 0 40
        include commonMaterials
        include floor
        box red 0 0.3 0 0.6 0.6 0.6
        """
        let fragments = [
            "commonMaterials": """
            material floor 0.6 0.6 0.55
            material red 0.9 0.15 0.1 roughness 0.4
            """,
            "floor": "quad floor -2 0 2 2 0 2 2 0 -2 -2 0 -2"
        ]

        let scene = try SceneScript.parse(source) { name in
            try XCTUnwrap(fragments[name])
        }
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 2)
        XCTAssertEqual(scene.meshInstances.count, 2)
        XCTAssertEqual(compiled.triangles.count, 14)
    }

    func testSceneScriptFileParsingResolvesIncludesAndAssets() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptFile", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try writeFixturePLY(url: baseURL.appendingPathComponent("fixture.ply"))
        try """
        material clay 0.82 0.42 0.26 roughness 0.8
        """.write(to: baseURL.appendingPathComponent("materials.denrim"), atomically: true, encoding: .utf8)
        try """
        camera 0 0 3 0 0 0 34
        include materials.denrim
        mesh fixture fixture.ply
        instance fixture clay 0 0 0 1 1 1
        """.write(to: baseURL.appendingPathComponent("scene.denrim"), atomically: true, encoding: .utf8)

        let scene = try SceneScript.parse(contentsOf: baseURL.appendingPathComponent("scene.denrim"))
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertEqual(scene.meshInstances.count, 1)
        XCTAssertEqual(compiled.triangles.count, 2)
    }

    func testSceneScriptMeshCanFlipOBJTextureV() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptMeshFlipV", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try """
        v -0.5 -0.5 0
        v 0.5 -0.5 0
        v 0.5 0.5 0
        vt 0.25 0.2
        vt 0.75 0.2
        vt 0.75 0.8
        f 1/1 2/2 3/3
        """.write(to: baseURL.appendingPathComponent("fixture.obj"), atomically: true, encoding: .utf8)
        try """
        material clay 0.82 0.42 0.26 roughness 0.8
        mesh fixture fixture.obj flipV
        instance fixture clay 0 0 0 1 1 1
        """.write(to: baseURL.appendingPathComponent("scene.denrim"), atomically: true, encoding: .utf8)

        let scene = try SceneScript.parse(contentsOf: baseURL.appendingPathComponent("scene.denrim"))
        let texcoords = try XCTUnwrap(scene.meshInstances.first?.mesh.texcoords)

        XCTAssertEqual(texcoords[0].x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(texcoords[0].y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(texcoords[1].x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(texcoords[1].y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(texcoords[2].x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(texcoords[2].y, 0.2, accuracy: 0.0001)
    }

    func testSceneScriptFileParsingReportsIncludeCycles() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-SceneScriptFileCycle", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try "include b.denrim".write(to: baseURL.appendingPathComponent("a.denrim"), atomically: true, encoding: .utf8)
        try "include a.denrim".write(to: baseURL.appendingPathComponent("b.denrim"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SceneScript.parse(contentsOf: baseURL.appendingPathComponent("a.denrim"))) { error in
            XCTAssertEqual(error as? SceneScriptError, .includeCycle("b.denrim", line: 1))
        }
    }

    func testSceneScriptReportsMissingIncludeResolver() {
        XCTAssertThrowsError(try SceneScript.parse("include common")) { error in
            XCTAssertEqual(error as? SceneScriptError, .includeResolverMissing("common", line: 1))
        }
    }

    func testSceneScriptReportsIncludeCycles() {
        let fragments = [
            "a": "include b",
            "b": "include a"
        ]

        XCTAssertThrowsError(try SceneScript.parse("include a", includeResolver: { name in
            try XCTUnwrap(fragments[name])
        })) { error in
            XCTAssertEqual(error as? SceneScriptError, .includeCycle("a", line: 1))
        }
    }

    func testSceneScriptReportsUnknownMaterial() {
        let source = """
        material white 1 1 1
        box missing 0 0 0 1 1 1
        """

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .unknownMaterial("missing", line: 2))
        }
    }

    func testSceneScriptReportsUnknownBuiltInMaterialPreset() {
        XCTAssertThrowsError(try SceneScript.parse("material bad preset missing.material")) { error in
            XCTAssertEqual(error as? SceneScriptError, .unknownMaterialPreset("missing.material", line: 1))
        }
    }

    func testSceneScriptReportsUnknownTexture() {
        let source = "material textured 1 1 1 baseColorTexture missing"

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .unknownTexture("missing", line: 1))
        }
    }

    func testSceneScriptReportsFailedImageTextureLoad() {
        let source = "texture missing image missing.png"

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .textureLoadFailed("missing.png", line: 1))
        }
    }

    func testSceneScriptReportsFailedEnvironmentLoad() {
        XCTAssertThrowsError(try SceneScript.parse("environment image missing.hdr")) { error in
            XCTAssertEqual(error as? SceneScriptError, .environmentLoadFailed("missing.hdr", line: 1))
        }
    }

    func testSceneScriptReportsFailedMeshLoad() {
        let source = "mesh missing missing.ply"

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .meshLoadFailed("missing.ply", line: 1))
        }
    }

    func testSceneScriptReportsUnknownMesh() {
        let source = """
        material clay 0.82 0.42 0.26
        instance missing clay 0 0 0 1 1 1
        """

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .unknownMesh("missing", line: 2))
        }
    }

    func testSceneScriptReportsBadNumbers() {
        let source = "camera 0 nope 1 0 0 0 45"

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .invalidNumber("nope", line: 1))
        }
    }

    private func writeFixturePNG(
        url: URL,
        width: Int,
        height: Int,
        rgba: [UInt8]
    ) throws -> URL {
        XCTAssertEqual(rgba.count, width * height * 4)
        try? FileManager.default.removeItem(at: url)

        let data = Data(rgba)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func writeFixtureHDR(
        url: URL,
        width: Int,
        height: Int,
        rgbe: [UInt8]
    ) throws {
        XCTAssertEqual(rgbe.count, width * height * 4)
        try? FileManager.default.removeItem(at: url)
        var data = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y \(height) +X \(width)\n".utf8)
        data.append(contentsOf: rgbe)
        try data.write(to: url)
    }

    private func writeFixturePLY(url: URL, halfExtent: Float = 0.5) throws {
        let source = """
        ply
        format ascii 1.0
        element vertex 4
        property float x
        property float y
        property float z
        element face 1
        property list uchar int vertex_indices
        end_header
        -\(halfExtent) -\(halfExtent) 0
        \(halfExtent) -\(halfExtent) 0
        \(halfExtent) \(halfExtent) 0
        -\(halfExtent) \(halfExtent) 0
        4 0 1 2 3
        """
        try source.write(to: url, atomically: true, encoding: .utf8)
    }
}
