import Foundation
import CoreGraphics
import ImageIO
import simd

/// Color encoding used when decoding image assets into linear texture pixels.
public enum TextureColorEncoding: Sendable {
    /// Treat source RGB bytes as already linear.
    case linear

    /// Convert source RGB bytes from sRGB into linear values.
    case sRGB
}

/// Texture sampling mode used by the current packed texture path.
public enum TextureSamplingMode: UInt32, Sendable {
    /// Select the nearest texel.
    case nearest = 0

    /// Bilinearly blend the nearest four texels.
    case linear = 1
}

/// Errors thrown while loading texture assets.
public enum TextureLoadingError: Error, LocalizedError {
    case unsupportedImage(URL)
    case couldNotCreateBitmapContext(width: Int, height: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedImage(let url):
            "Could not decode texture image at \(url.path)."
        case .couldNotCreateBitmapContext(let width, let height):
            "Could not create a \(width)x\(height) texture loading context."
        }
    }
}

/// A small linear RGBA texture used by material inputs.
public struct Texture2D: Sendable, Equatable {
    /// Texture width in pixels.
    public var width: Int

    /// Texture height in pixels.
    public var height: Int

    /// Linear RGBA pixels in row-major order.
    public var pixels: [SIMD4<Float>]

    /// Sampling mode used by material texture lookups.
    public var samplingMode: TextureSamplingMode

    /// Creates a texture from linear RGBA pixels.
    public init(
        width: Int,
        height: Int,
        pixels: [SIMD4<Float>],
        samplingMode: TextureSamplingMode = .nearest
    ) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.samplingMode = samplingMode
    }

    /// Loads an image asset into linear RGBA pixels.
    public init(
        contentsOf url: URL,
        colorEncoding: TextureColorEncoding = .sRGB,
        samplingMode: TextureSamplingMode = .linear
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TextureLoadingError.unsupportedImage(url)
        }

        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TextureLoadingError.couldNotCreateBitmapContext(width: width, height: height)
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels: [SIMD4<Float>] = []
        pixels.reserveCapacity(width * height)

        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Float(bytes[offset + 3]) / 255
            let unpremultiply = alpha > 0 ? 1 / alpha : 0
            var red = Float(bytes[offset]) / 255 * unpremultiply
            var green = Float(bytes[offset + 1]) / 255 * unpremultiply
            var blue = Float(bytes[offset + 2]) / 255 * unpremultiply

            red = min(max(red, 0), 1)
            green = min(max(green, 0), 1)
            blue = min(max(blue, 0), 1)

            if colorEncoding == .sRGB {
                red = Self.sRGBToLinear(red)
                green = Self.sRGBToLinear(green)
                blue = Self.sRGBToLinear(blue)
            }

            pixels.append(SIMD4<Float>(red, green, blue, alpha))
        }

        self.init(width: width, height: height, pixels: pixels, samplingMode: samplingMode)
    }

    /// Creates a single-color texture.
    public static func solid(
        _ color: SIMD4<Float>,
        samplingMode: TextureSamplingMode = .nearest
    ) -> Texture2D {
        Texture2D(width: 1, height: 1, pixels: [color], samplingMode: samplingMode)
    }

    /// Creates a 2x2 checker texture.
    public static func checker(
        _ a: SIMD4<Float>,
        _ b: SIMD4<Float>,
        samplingMode: TextureSamplingMode = .nearest
    ) -> Texture2D {
        Texture2D(width: 2, height: 2, pixels: [
            a, b,
            b, a
        ], samplingMode: samplingMode)
    }

    /// Loads an image asset into linear RGBA pixels.
    public static func load(
        contentsOf url: URL,
        colorEncoding: TextureColorEncoding = .sRGB,
        samplingMode: TextureSamplingMode = .linear
    ) throws -> Texture2D {
        try Texture2D(contentsOf: url, colorEncoding: colorEncoding, samplingMode: samplingMode)
    }

    private static func sRGBToLinear(_ value: Float) -> Float {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}
