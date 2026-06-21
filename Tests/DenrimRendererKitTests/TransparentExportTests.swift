import CoreGraphics
import ImageIO
import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class TransparentExportTests: XCTestCase {
    func testTransparentBackgroundWritesBeautyAlpha() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: Self.floatingQuadScene(),
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 1,
                transparentBackground: true
            ),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let pixels = try session.pixels(for: .beauty)

        XCTAssertTrue(pixels.contains { $0.a < 0.01 && $0.r == 0 && $0.g == 0 && $0.b == 0 })
        XCTAssertTrue(pixels.contains { $0.a > 0.99 && ($0.r > 0 || $0.g > 0 || $0.b > 0) })
    }

    func testDefaultBackgroundRemainsOpaqueSky() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: Self.floatingQuadScene(),
            settings: RenderSettings(width: 24, height: 24, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let pixels = try session.pixels(for: .beauty)

        XCTAssertTrue(pixels.allSatisfy { $0.a > 0.99 })
        XCTAssertTrue(pixels.contains { $0.r > 0 && $0.g > 0 && $0.b > 0 })
    }

    func testBeautyPNGPreservesTransparentAlpha() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: Self.floatingQuadScene(),
            settings: RenderSettings(
                width: 24,
                height: 24,
                maxBounces: 1,
                transparentBackground: true
            ),
            accelerationMode: .flatBVH
        )

        try session.renderNextSample()
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-TransparentBeauty.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.writePNG(output: .beauty, to: outputURL)
        let alphas = try Self.pngAlphas(at: outputURL)

        XCTAssertTrue(alphas.contains { $0 < 8 })
        XCTAssertTrue(alphas.contains { $0 > 247 })
    }

    private static func floatingQuadScene() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                verticalFieldOfViewDegrees: 34
            )
        )
        let material = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.9, 0.2, 0.1),
            emission: SIMD3<Float>(0.9, 0.2, 0.1),
            emissionStrength: 1
        ))
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.45, -0.45, 0),
            SIMD3<Float>(0.45, -0.45, 0),
            SIMD3<Float>(0.45, 0.45, 0),
            SIMD3<Float>(-0.45, 0.45, 0)
        ), material: material)
        return scene
    }

    private static func pngAlphas(at url: URL) throws -> [UInt8] {
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
