import Metal
import XCTest
@testable import DenrimRendererKit

final class AOVTests: XCTestCase {
    func testSessionPreparesAOVTextures() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1)
        )

        XCTAssertTrue(session.aovDebugInfo.hasDepth)
        XCTAssertTrue(session.aovDebugInfo.hasNormal)
        XCTAssertTrue(session.aovDebugInfo.hasAlbedo)
        XCTAssertTrue(session.aovDebugInfo.hasMaterialID)
        XCTAssertTrue(session.aovDebugInfo.hasObjectID)
        XCTAssertTrue(session.aovDebugInfo.hasMotionVector)
    }

    func testAOVTexturesReceivePrimarySurfaceData() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .materialReference(),
            settings: RenderSettings(width: 32, height: 32, maxBounces: 1)
        )

        try session.renderNextSample()
        let aovs = try session.debugAOVPixels()

        XCTAssertTrue(aovs.depth.contains { $0.r > 0 })
        XCTAssertTrue(aovs.normal.contains { $0.a > 0 && $0.r >= 0 && $0.r <= 1 && $0.g >= 0 && $0.g <= 1 && $0.b >= 0 && $0.b <= 1 })
        XCTAssertGreaterThan(uniqueAlbedoEstimate(aovs.albedo), 3)
    }

    func testPublicOutputPixelReadback() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .materialReference(),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1)
        )

        try session.renderNextSample()

        for output in RenderOutput.allCases {
            let pixels = try session.pixels(for: output)
            XCTAssertEqual(pixels.count, 24 * 24)
        }

        XCTAssertTrue(try session.pixels(for: .depth).contains { $0.r > 0 })
        XCTAssertGreaterThan(uniqueAlbedoEstimate(try session.pixels(for: .albedo)), 3)
        XCTAssertGreaterThan(uniqueIDEstimate(try session.pixels(for: .materialID)), 3)
        XCTAssertGreaterThan(uniqueIDEstimate(try session.pixels(for: .objectID)), 3)
    }

    func testMotionVectorOutputUsesPreviousCamera() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let scene = RenderScene.materialReference()
        let previousCamera = Camera(
            origin: scene.camera.origin + SIMD3<Float>(0.15, 0, 0),
            target: scene.camera.target + SIMD3<Float>(0.15, 0, 0),
            up: scene.camera.up,
            verticalFieldOfViewDegrees: scene.camera.verticalFieldOfViewDegrees
        )
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 32, height: 32, maxBounces: 1, previousCamera: previousCamera)
        )

        try session.renderNextSample()
        let motion = try session.pixels(for: .motionVector)

        XCTAssertTrue(motion.contains { abs($0.r) > 0.01 || abs($0.g) > 0.01 })
        XCTAssertTrue(motion.contains { $0.a > 0 })
    }

    func testPublicOutputPNGExport() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .materialReference(),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1)
        )
        try session.renderNextSample()

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-Albedo.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.writePNG(output: .albedo, to: outputURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(byteCount, 0)
    }

    func testPNGVisualizationUsesOutputSpecificEncoding() {
        let depthPixels = [
            RenderOutputPixel(r: 0, g: 0, b: 0, a: 0),
            RenderOutputPixel(r: 2, g: 2, b: 2, a: 1),
            RenderOutputPixel(r: 4, g: 4, b: 4, a: 1)
        ]
        let depth = PNGWriter.visualizedRGBA8Pixels(from: depthPixels, output: .depth)
        XCTAssertEqual(Array(depth[0..<4]), [0, 0, 0, 255])
        XCTAssertGreaterThan(depth[4], 0)
        XCTAssertLessThan(depth[4], depth[8])

        let idPixels = [
            RenderOutputPixel(r: 0, g: 0, b: 0, a: 0),
            RenderOutputPixel(r: 1, g: 1, b: 1, a: 1),
            RenderOutputPixel(r: 2, g: 2, b: 2, a: 1)
        ]
        let ids = PNGWriter.visualizedRGBA8Pixels(from: idPixels, output: .materialID)
        XCTAssertEqual(Array(ids[0..<4]), [0, 0, 0, 255])
        XCTAssertNotEqual(Array(ids[4..<7]), Array(ids[8..<11]))
        XCTAssertNotEqual(Array(ids[4..<7]), [255, 255, 255])

        let motionPixels = [
            RenderOutputPixel(r: 0, g: 0, b: 0, a: 1),
            RenderOutputPixel(r: 2, g: -2, b: 0, a: 1)
        ]
        let motion = PNGWriter.visualizedRGBA8Pixels(from: motionPixels, output: .motionVector)
        XCTAssertEqual(Array(motion[0..<4]), [127, 127, 128, 255])
        XCTAssertGreaterThan(motion[4], motion[5])
    }

    private func uniqueAlbedoEstimate(_ pixels: [RenderOutputPixel]) -> Int {
        var colors = Set<Int>()
        for pixel in pixels where pixel.a > 0 {
            let red = Int(max(0, min(7, pixel.r * 7)))
            let green = Int(max(0, min(7, pixel.g * 7)))
            let blue = Int(max(0, min(7, pixel.b * 7)))
            colors.insert(red << 16 | green << 8 | blue)
        }
        return colors.count
    }

    private func uniqueIDEstimate(_ pixels: [RenderOutputPixel]) -> Int {
        Set(pixels.compactMap { pixel in
            let value = Int(pixel.r.rounded())
            return value > 0 ? value : nil
        }).count
    }
}
