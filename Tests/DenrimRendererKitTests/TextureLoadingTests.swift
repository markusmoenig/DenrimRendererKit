import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DenrimRendererKit

final class TextureLoadingTests: XCTestCase {
    func testLoadsPNGDimensionsAndAlpha() throws {
        let url = try writeFixturePNG(
            name: "TextureLoading-alpha.png",
            width: 2,
            height: 1,
            rgba: [
                255, 0, 0, 255,
                0, 0, 0, 0
            ]
        )

        let texture = try Texture2D(contentsOf: url, colorEncoding: .linear)

        XCTAssertEqual(texture.width, 2)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.pixels.count, 2)
        XCTAssertEqual(texture.pixels[0], SIMD4<Float>(1, 0, 0, 1))
        XCTAssertEqual(texture.pixels[1], SIMD4<Float>(0, 0, 0, 0))
    }

    func testSRGBLoadingConvertsRGBToLinear() throws {
        let url = try writeFixturePNG(
            name: "TextureLoading-srgb.png",
            width: 1,
            height: 1,
            rgba: [128, 128, 128, 255]
        )

        let texture = try Texture2D(contentsOf: url, colorEncoding: .sRGB)

        XCTAssertEqual(texture.pixels[0].x, 0.21586, accuracy: 0.002)
        XCTAssertEqual(texture.pixels[0].y, 0.21586, accuracy: 0.002)
        XCTAssertEqual(texture.pixels[0].z, 0.21586, accuracy: 0.002)
        XCTAssertEqual(texture.pixels[0].w, 1, accuracy: 0.001)
    }

    func testLinearLoadingKeepsRGBValues() throws {
        let url = try writeFixturePNG(
            name: "TextureLoading-linear.png",
            width: 1,
            height: 1,
            rgba: [128, 128, 128, 255]
        )

        let texture = try Texture2D.load(contentsOf: url, colorEncoding: .linear)

        XCTAssertEqual(texture.pixels[0].x, Float(128) / 255, accuracy: 0.002)
        XCTAssertEqual(texture.pixels[0].y, Float(128) / 255, accuracy: 0.002)
        XCTAssertEqual(texture.pixels[0].z, Float(128) / 255, accuracy: 0.002)
        XCTAssertEqual(texture.pixels[0].w, 1, accuracy: 0.001)
    }

    func testTextureSamplingModeDefaultsAndOverrides() throws {
        let url = try writeFixturePNG(
            name: "TextureLoading-sampling.png",
            width: 1,
            height: 1,
            rgba: [255, 255, 255, 255]
        )

        XCTAssertEqual(Texture2D.solid(SIMD4<Float>(1, 1, 1, 1)).samplingMode, .nearest)
        XCTAssertEqual(Texture2D.checker(SIMD4<Float>(1, 0, 0, 1), SIMD4<Float>(0, 0, 1, 1)).samplingMode, .nearest)
        XCTAssertEqual(try Texture2D(contentsOf: url).samplingMode, .linear)
        XCTAssertEqual(try Texture2D(contentsOf: url, samplingMode: .nearest).samplingMode, .nearest)
    }

    func testDerivedNormalMapUsesTextureLuminanceGradient() {
        let texture = Texture2D(
            width: 3,
            height: 1,
            pixels: [
                SIMD4<Float>(0, 0, 0, 1),
                SIMD4<Float>(0.5, 0.5, 0.5, 1),
                SIMD4<Float>(1, 1, 1, 1)
            ],
            samplingMode: .linear
        )

        let normalMap = texture.derivedNormalMap(strength: 1)

        XCTAssertEqual(normalMap.width, 3)
        XCTAssertEqual(normalMap.height, 1)
        XCTAssertEqual(normalMap.samplingMode, .linear)
        XCTAssertLessThan(normalMap.pixels[1].x, 0.5)
        XCTAssertEqual(normalMap.pixels[1].y, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(normalMap.pixels[1].z, 0.8)
    }

    func testMissingTextureThrows() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-missing-texture.png")

        XCTAssertThrowsError(try Texture2D(contentsOf: url)) { error in
            XCTAssertTrue(error is TextureLoadingError)
        }
    }

    private func writeFixturePNG(
        name: String,
        width: Int,
        height: Int,
        rgba: [UInt8]
    ) throws -> URL {
        XCTAssertEqual(rgba.count, width * height * 4)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(name)
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
}
