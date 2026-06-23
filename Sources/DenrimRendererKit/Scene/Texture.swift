import Foundation
import CoreGraphics
import ImageIO
import simd

/// Color encoding used when decoding image assets into linear texture pixels.
public enum TextureColorEncoding: Sendable, Hashable {
    /// Treat source RGB bytes as already linear.
    case linear

    /// Convert source RGB bytes from sRGB into linear values.
    case sRGB
}

/// Texture sampling mode used by the current packed texture path.
public enum TextureSamplingMode: UInt32, Sendable, Hashable {
    /// Select the nearest texel.
    case nearest = 0

    /// Bilinearly blend the nearest four texels.
    case linear = 1
}

/// Errors thrown while loading texture assets.
public enum TextureLoadingError: Error, LocalizedError {
    case unsupportedImage(URL)
    case couldNotCreateBitmapContext(width: Int, height: Int)
    case invalidHDR(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedImage(let url):
            "Could not decode texture image at \(url.path)."
        case .couldNotCreateBitmapContext(let width, let height):
            "Could not create a \(width)x\(height) texture loading context."
        case .invalidHDR(let url):
            "Could not decode Radiance HDR texture at \(url.path)."
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
        if url.pathExtension.lowercased() == "hdr" {
            let decoded = try Self.loadRadianceHDR(contentsOf: url)
            self.init(
                width: decoded.width,
                height: decoded.height,
                pixels: decoded.pixels,
                samplingMode: samplingMode
            )
            return
        }

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

    /// Derives a tangent-space normal map from the texture's luminance.
    ///
    /// This is useful for lightweight reference scenes that only have albedo
    /// images but need subtle surface relief for visual validation.
    public func derivedNormalMap(strength: Float = 1) -> Texture2D {
        guard width > 0, height > 0, pixels.count == width * height else {
            return Texture2D(width: width, height: height, pixels: pixels, samplingMode: samplingMode)
        }

        let clampedStrength = max(strength, 0)
        var normalPixels: [SIMD4<Float>] = []
        normalPixels.reserveCapacity(pixels.count)

        for y in 0..<height {
            for x in 0..<width {
                let left = luminanceAt(x: x - 1, y: y)
                let right = luminanceAt(x: x + 1, y: y)
                let down = luminanceAt(x: x, y: y - 1)
                let up = luminanceAt(x: x, y: y + 1)
                let normal = simd_normalize(SIMD3<Float>(
                    (left - right) * clampedStrength,
                    (down - up) * clampedStrength,
                    1
                ))

                normalPixels.append(SIMD4<Float>(
                    normal.x * 0.5 + 0.5,
                    normal.y * 0.5 + 0.5,
                    normal.z * 0.5 + 0.5,
                    1
                ))
            }
        }

        return Texture2D(
            width: width,
            height: height,
            pixels: normalPixels,
            samplingMode: samplingMode
        )
    }

    private static func sRGBToLinear(_ value: Float) -> Float {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func loadRadianceHDR(contentsOf url: URL) throws -> (
        width: Int,
        height: Int,
        pixels: [SIMD4<Float>]
    ) {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        var index = 0
        var resolutionLine: String?

        func readLine() -> String? {
            guard index < bytes.count else {
                return nil
            }
            let start = index
            while index < bytes.count && bytes[index] != 10 {
                index += 1
            }
            let end = index
            if index < bytes.count {
                index += 1
            }
            var lineBytes = bytes[start..<end]
            if lineBytes.last == 13 {
                lineBytes = lineBytes.dropLast()
            }
            return String(bytes: lineBytes, encoding: .ascii)
        }

        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.contains("-Y") || trimmed.contains("+Y") {
                resolutionLine = trimmed
                break
            }
        }

        guard let resolutionLine else {
            throw TextureLoadingError.invalidHDR(url)
        }

        let tokens = resolutionLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count == 4,
              let firstSize = Int(tokens[1]),
              let secondSize = Int(tokens[3]),
              firstSize > 0,
              secondSize > 0 else {
            throw TextureLoadingError.invalidHDR(url)
        }

        let width: Int
        let height: Int
        let yFirst = tokens[0].hasSuffix("Y")
        if yFirst {
            height = firstSize
            width = secondSize
        } else {
            width = firstSize
            height = secondSize
        }

        let scanlineByteCount = width * 4
        var rgbe = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            guard index + 4 <= bytes.count else {
                throw TextureLoadingError.invalidHDR(url)
            }

            if width >= 8,
               width <= 0x7fff,
               bytes[index] == 2,
               bytes[index + 1] == 2,
               bytes[index + 2] & 0x80 == 0 {
                let encodedWidth = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
                guard encodedWidth == width else {
                    throw TextureLoadingError.invalidHDR(url)
                }
                index += 4

                var scanline = [UInt8](repeating: 0, count: scanlineByteCount)
                for channel in 0..<4 {
                    var x = 0
                    while x < width {
                        guard index < bytes.count else {
                            throw TextureLoadingError.invalidHDR(url)
                        }
                        let count = Int(bytes[index])
                        index += 1
                        if count > 128 {
                            let runLength = count - 128
                            guard runLength > 0, x + runLength <= width, index < bytes.count else {
                                throw TextureLoadingError.invalidHDR(url)
                            }
                            let value = bytes[index]
                            index += 1
                            for _ in 0..<runLength {
                                scanline[x * 4 + channel] = value
                                x += 1
                            }
                        } else {
                            guard count > 0, x + count <= width, index + count <= bytes.count else {
                                throw TextureLoadingError.invalidHDR(url)
                            }
                            for _ in 0..<count {
                                scanline[x * 4 + channel] = bytes[index]
                                index += 1
                                x += 1
                            }
                        }
                    }
                }

                rgbe.replaceSubrange((y * scanlineByteCount)..<((y + 1) * scanlineByteCount), with: scanline)
            } else {
                guard index + scanlineByteCount <= bytes.count else {
                    throw TextureLoadingError.invalidHDR(url)
                }
                rgbe.replaceSubrange(
                    (y * scanlineByteCount)..<((y + 1) * scanlineByteCount),
                    with: bytes[index..<(index + scanlineByteCount)]
                )
                index += scanlineByteCount
            }
        }

        var pixels: [SIMD4<Float>] = []
        pixels.reserveCapacity(width * height)
        for offset in stride(from: 0, to: rgbe.count, by: 4) {
            let exponent = rgbe[offset + 3]
            if exponent == 0 {
                pixels.append(SIMD4<Float>(0, 0, 0, 1))
                continue
            }

            let scale = ldexpf(1, Int32(exponent) - 136)
            pixels.append(SIMD4<Float>(
                Float(rgbe[offset]) * scale,
                Float(rgbe[offset + 1]) * scale,
                Float(rgbe[offset + 2]) * scale,
                1
            ))
        }

        return (width, height, pixels)
    }

    private func luminanceAt(x: Int, y: Int) -> Float {
        let wrappedX = (x % width + width) % width
        let clampedY = min(max(y, 0), height - 1)
        let color = pixels[clampedY * width + wrappedX]
        return color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
    }
}
