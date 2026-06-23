import Foundation
import Metal
import XCTest
import DenrimRendererKit

final class ScriptedTextureReferenceRenderTests: XCTestCase {
    func testScriptedTextureSceneAOVMetricsMatchBaseline() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: try SceneScript.parse(Self.sceneSource),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 1)
        )

        try session.renderNextSample()

        let albedoURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-ScriptedTexture-Albedo.png")
        let normalURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-ScriptedTexture-Normal.png")
        try? FileManager.default.removeItem(at: albedoURL)
        try? FileManager.default.removeItem(at: normalURL)

        try session.writePNG(output: .albedo, to: albedoURL)
        try session.writePNG(output: .normal, to: normalURL)

        let albedoBaseline = try ImageMetricReader.baseline(named: "ScriptedTextureAlbedo")
        let normalBaseline = try ImageMetricReader.baseline(named: "ScriptedTextureNormal")
        let albedoMetrics = try ImageMetricReader.metrics(url: albedoURL)
        let normalMetrics = try ImageMetricReader.metrics(url: normalURL)

        XCTAssertGreaterThanOrEqual(albedoMetrics.uniqueColorEstimate, 2)
        XCTAssertGreaterThan(normalMetrics.averageBrightness, 100)
        assertMetrics(albedoMetrics, match: albedoBaseline)
        assertMetrics(normalMetrics, match: normalBaseline)
    }

    func testScriptedImportedMeshRendersAlbedoAOV() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-ScriptedImportedMesh", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try writeFixturePLY(url: baseURL.appendingPathComponent("fixture.ply"))

        let sceneSource = """
        camera 0 0 3 0 0 0 34
        mesh fixture fixture.ply
        material clay 0.82 0.42 0.26 roughness 0.8
        instance fixture clay 0 0 0 1.6 1.6 1.6
        """
        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: try SceneScript.parse(sceneSource, baseURL: baseURL),
            settings: RenderSettings(width: 32, height: 32, maxBounces: 1)
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }

        XCTAssertGreaterThan(albedo.count, 100)
        XCTAssertTrue(albedo.contains { pixel in
            pixel.r > 0.75 && pixel.g > 0.35 && pixel.g < 0.5 && pixel.b > 0.2 && pixel.b < 0.35
        })
    }

    func testMaterialVariantSceneScriptResourceRenders() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let sceneURL = packageRoot()
            .appendingPathComponent("Examples/SceneScripts/MaterialVariants/material-variants.denrim")
        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: try SceneScript.parse(contentsOf: sceneURL),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 2)
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }
        let materialIDs = try session.pixels(for: .materialID).filter { $0.a > 0 }

        XCTAssertGreaterThan(albedo.count, 300)
        XCTAssertGreaterThan(Set(materialIDs.map { Int($0.r.rounded()) }).count, 4)
        XCTAssertTrue(albedo.contains { $0.r > 0.75 && $0.g < 0.5 && $0.b < 0.35 })
        XCTAssertTrue(albedo.contains { $0.b > 0.75 && $0.r < 0.3 })
    }

    func testGlossyMetalReferenceSceneScriptResourceRenders() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let sceneURL = packageRoot()
            .appendingPathComponent("Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim")
        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: try SceneScript.parse(contentsOf: sceneURL),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 3)
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }
        let materialIDs = try session.pixels(for: .materialID).filter { $0.a > 0 }
        let beauty = try session.pixels(for: .beauty)

        XCTAssertGreaterThan(albedo.count, 600)
        XCTAssertGreaterThan(Set(materialIDs.map { Int($0.r.rounded()) }).count, 6)
        XCTAssertTrue(albedo.contains { $0.r > 0.82 && $0.g > 0.82 && $0.b > 0.80 })
        XCTAssertTrue(albedo.contains { $0.r < 0.08 && $0.g < 0.08 && $0.b < 0.09 })
        XCTAssertTrue(beauty.contains { $0.r > 0.25 && $0.g > 0.23 && $0.b > 0.20 })
    }

    private static let sceneSource = """
    camera 0 0 3 0 0 0 34
    texture checker checker 1 0 0 1 0 0 1 1
    texture tangentRight solid 1 0.5 0.5 1
    material textured 1 1 1 roughness 0.7 baseColorTexture checker normalMap tangentRight
    quad textured -1 -1 0 1 -1 0 1 1 0 -1 1 0
    """

    private func writeFixturePLY(url: URL) throws {
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
        -0.5 -0.5 0
        0.5 -0.5 0
        0.5 0.5 0
        -0.5 0.5 0
        4 0 1 2 3
        """
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
