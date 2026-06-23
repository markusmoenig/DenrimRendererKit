import CoreGraphics
import ImageIO
import Metal
import simd
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

    func testAlbedoOutputPreservesMaterialOpacity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: opacityScene(opacity: 0.35),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: .albedo).filter { $0.a > 0 }

        XCTAssertTrue(albedo.contains { abs($0.a - 0.35) < 0.02 })
    }

    func testAlbedoPNGPreservesMaterialOpacity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: opacityScene(opacity: 0.35),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-AlbedoOpacity.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.writePNG(output: .albedo, to: outputURL)
        let alphas = try pngAlphas(at: outputURL)

        XCTAssertTrue(alphas.contains { abs(Int($0) - 89) <= 3 })
    }

    func testPNGVisualizationUsesOutputSpecificEncoding() {
        let beautyPixels = [
            RenderOutputPixel(r: 0, g: 0, b: 0, a: 0.5),
            RenderOutputPixel(r: 1, g: 1, b: 1, a: 1),
            RenderOutputPixel(r: 16, g: 16, b: 16, a: 1)
        ]
        let beauty = PNGWriter.visualizedRGBA8Pixels(from: beautyPixels, output: .beauty)
        XCTAssertEqual(Array(beauty[0..<4]), [0, 0, 0, 127])
        XCTAssertGreaterThan(beauty[4], 200)
        XCTAssertGreaterThan(beauty[8], beauty[4])
        XCTAssertLessThanOrEqual(beauty[8], 255)

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

    private func opacityScene(opacity: Float) -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                verticalFieldOfViewDegrees: 34
            )
        )
        let material = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.7, 0.2, 0.1),
            roughness: 0.8,
            opacity: opacity
        ))
        scene.add(mesh: .quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ), material: material)
        return scene
    }

    private func pngAlphas(at url: URL) throws -> [UInt8] {
        let data = try Data(contentsOf: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
