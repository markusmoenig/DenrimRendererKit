import Foundation

/// Preset quality intent for render sessions.
public enum RenderQuality: Sendable {
    /// Fast progressive rendering for editing and thumbnails.
    case preview

    /// Higher quality progressive rendering for viewport work.
    case interactive

    /// Maximum quality rendering for exports.
    case final
}

/// User-facing settings for a render session.
public struct RenderSettings: Sendable {
    /// Output width in pixels.
    public var width: Int

    /// Output height in pixels.
    public var height: Int

    /// Maximum path depth.
    public var maxBounces: Int

    /// Quality intent used by the renderer.
    public var quality: RenderQuality

    /// Previous frame camera used for motion vector output.
    public var previousCamera: Camera?

    /// Whether primary camera rays that miss the scene should export with zero alpha.
    public var transparentBackground: Bool

    /// Optional denoising applied to beauty output. Defaults to disabled.
    public var denoise: DenoiseSettings

    /// Creates render settings.
    public init(
        width: Int = 512,
        height: Int = 512,
        maxBounces: Int = 4,
        quality: RenderQuality = .preview,
        previousCamera: Camera? = nil,
        transparentBackground: Bool = false,
        denoise: DenoiseSettings = .none
    ) {
        self.width = width
        self.height = height
        self.maxBounces = maxBounces
        self.quality = quality
        self.previousCamera = previousCamera
        self.transparentBackground = transparentBackground
        self.denoise = denoise
    }
}
