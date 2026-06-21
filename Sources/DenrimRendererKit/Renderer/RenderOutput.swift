import Foundation

/// A render output produced by a render session.
public enum RenderOutput: Sendable, CaseIterable {
    /// Progressive beauty color.
    case beauty

    /// Primary-hit depth encoded in the red, green, and blue channels.
    case depth

    /// Primary-hit world normal encoded from -1...1 into 0...1.
    case normal

    /// Primary-hit material base color.
    case albedo

    /// Primary-hit material identifier encoded as a one-based float value.
    case materialID

    /// Primary-hit object identifier encoded as a one-based float value.
    case objectID

    /// Primary-hit motion vector from the current pixel to the previous camera projection, in pixels.
    case motionVector
}

/// A single floating-point RGBA output pixel.
public struct RenderOutputPixel: Sendable, Equatable {
    /// Red channel.
    public var r: Float

    /// Green channel.
    public var g: Float

    /// Blue channel.
    public var b: Float

    /// Alpha channel.
    public var a: Float

    /// Creates an output pixel.
    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
