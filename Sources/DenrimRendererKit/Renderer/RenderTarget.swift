import Foundation
import Metal

/// Pixel dimensions for a render output.
public struct RenderTarget {
    /// Target width in pixels.
    public let width: Int

    /// Target height in pixels.
    public let height: Int

    /// Creates a render target.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

extension MTLTextureDescriptor {
    static func denrimAccumulationTarget(width: Int, height: Int) -> MTLTextureDescriptor {
        denrimFloatTarget(width: width, height: height)
    }

    static func denrimFloatTarget(width: Int, height: Int) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return descriptor
    }
}
