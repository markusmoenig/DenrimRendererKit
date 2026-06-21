import Foundation
import Metal

enum TextureReadback {
    static func floatPixels(from texture: MTLTexture, device: MTLDevice) throws -> [RenderOutputPixel] {
        let width = texture.width
        let height = texture.height
        let floatCount = width * height * 4
        let byteCount = floatCount * MemoryLayout<Float>.stride

        guard let readback = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not prepare texture readback.")
        }

        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: width * 4 * MemoryLayout<Float>.stride,
            destinationBytesPerImage: byteCount
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let floats = readback.contents().bindMemory(to: Float.self, capacity: floatCount)
        var pixels: [RenderOutputPixel] = []
        pixels.reserveCapacity(width * height)

        for pixelIndex in 0..<(width * height) {
            let offset = pixelIndex * 4
            pixels.append(RenderOutputPixel(
                r: floats[offset],
                g: floats[offset + 1],
                b: floats[offset + 2],
                a: floats[offset + 3]
            ))
        }

        return pixels
    }
}
