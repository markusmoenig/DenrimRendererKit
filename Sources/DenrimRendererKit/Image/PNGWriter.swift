import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

enum PNGWriter {
    static func image(from texture: MTLTexture, output: RenderOutput, device: MTLDevice) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        let floatPixels = try TextureReadback.floatPixels(from: texture, device: device)
        let pixels = visualizedRGBA8Pixels(from: floatPixels, output: output)

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw DenrimRendererError.commandBufferFailed("Could not create CGImage.")
        }

        return image
    }

    static func visualizedRGBA8Pixels(from pixels: [RenderOutputPixel], output: RenderOutput) -> [UInt8] {
        switch output {
        case .beauty:
            return encodePixels(pixels, channelEncoder: tonemap, preservesAlpha: true)
        case .depth:
            return encodeDepthPixels(pixels)
        case .normal:
            return encodePixels(pixels, channelEncoder: encodeDisplayLinear)
        case .albedo:
            return encodePixels(pixels, channelEncoder: encodeDisplayLinear, preservesAlpha: true)
        case .materialID, .objectID:
            return encodeIDPixels(pixels)
        case .motionVector:
            return encodeMotionVectorPixels(pixels)
        }
    }

    static func write(image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DenrimRendererError.pngExportFailed(url)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DenrimRendererError.pngExportFailed(url)
        }
    }

    private static func encodePixels(
        _ pixels: [RenderOutputPixel],
        channelEncoder: (Float) -> UInt8,
        preservesAlpha: Bool = false
    ) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: pixels.count * 4)
        for (pixelIndex, pixel) in pixels.enumerated() {
            let dst = pixelIndex * 4
            output[dst] = channelEncoder(pixel.r)
            output[dst + 1] = channelEncoder(pixel.g)
            output[dst + 2] = channelEncoder(pixel.b)
            output[dst + 3] = preservesAlpha ? encodeAlpha(pixel.a) : 255
        }
        return output
    }

    private static func encodeDepthPixels(_ pixels: [RenderOutputPixel]) -> [UInt8] {
        let depths = pixels
            .map(\.r)
            .filter { $0.isFinite && $0 > 0 }

        guard let minDepth = depths.min(), let maxDepth = depths.max() else {
            return [UInt8](repeating: 0, count: pixels.count * 4)
        }

        let depthRange = maxDepth - minDepth
        var output = [UInt8](repeating: 0, count: pixels.count * 4)

        for (pixelIndex, pixel) in pixels.enumerated() {
            let dst = pixelIndex * 4
            guard pixel.r.isFinite, pixel.r > 0 else {
                output[dst + 3] = 255
                continue
            }

            let normalized: Float
            if depthRange <= Float.ulpOfOne {
                normalized = 1
            } else {
                normalized = (pixel.r - minDepth) / depthRange
            }

            let displayValue = UInt8(max(0, min(255, (0.1 + normalized * 0.9) * 255)))
            output[dst] = displayValue
            output[dst + 1] = displayValue
            output[dst + 2] = displayValue
            output[dst + 3] = 255
        }

        return output
    }

    private static func encodeIDPixels(_ pixels: [RenderOutputPixel]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: pixels.count * 4)

        for (pixelIndex, pixel) in pixels.enumerated() {
            let dst = pixelIndex * 4
            let id = Int(pixel.r.rounded())

            guard id > 0 else {
                output[dst + 3] = 255
                continue
            }

            let color = colorForID(id)
            output[dst] = color.r
            output[dst + 1] = color.g
            output[dst + 2] = color.b
            output[dst + 3] = 255
        }

        return output
    }

    private static func encodeMotionVectorPixels(_ pixels: [RenderOutputPixel]) -> [UInt8] {
        let maxMagnitude = pixels.reduce(Float(0)) { partial, pixel in
            max(partial, max(abs(pixel.r), abs(pixel.g)))
        }
        let scale = max(maxMagnitude, 1)
        var output = [UInt8](repeating: 0, count: pixels.count * 4)

        for (pixelIndex, pixel) in pixels.enumerated() {
            let dst = pixelIndex * 4
            output[dst] = encodeSigned(pixel.r / scale)
            output[dst + 1] = encodeSigned(pixel.g / scale)
            output[dst + 2] = 128
            output[dst + 3] = 255
        }

        return output
    }

    private static func tonemap(_ linear: Float) -> UInt8 {
        let exposed = max(0, linear) * 0.8
        let mapped = (exposed * (2.51 * exposed + 0.03))
            / (exposed * (2.43 * exposed + 0.59) + 0.14)
        let gamma = pow(max(0, min(1, mapped)), 1 / 2.2)
        return UInt8(max(0, min(255, gamma * 255)))
    }

    private static func encodeDisplayLinear(_ linear: Float) -> UInt8 {
        let gamma = pow(max(0, min(1, linear)), 1 / 2.2)
        return UInt8(max(0, min(255, gamma * 255)))
    }

    private static func encodeAlpha(_ alpha: Float) -> UInt8 {
        UInt8(max(0, min(255, alpha * 255)))
    }

    private static func colorForID(_ id: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var hash = UInt32(id)
        hash &*= 747_796_405
        hash &+= 2_891_336_453
        hash = ((hash >> ((hash >> 28) + 4)) ^ hash) &* 277_803_737
        hash = (hash >> 22) ^ hash

        let red = UInt8(64 + Int(hash & 0x7F))
        let green = UInt8(64 + Int((hash >> 8) & 0x7F))
        let blue = UInt8(64 + Int((hash >> 16) & 0x7F))
        return (red, green, blue)
    }

    private static func encodeSigned(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, (value * 0.5 + 0.5) * 255)))
    }
}
