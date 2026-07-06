import Foundation
import simd

/// Preset quality intent for render sessions.
public enum RenderQuality: Sendable {
    /// Fast progressive rendering for editing and thumbnails.
    case preview

    /// Higher quality progressive rendering for viewport work.
    case interactive

    /// Maximum quality rendering for exports.
    case final

    /// Default per-sample radiance clamp used to reduce isolated glossy fireflies.
    public var defaultSampleRadianceClamp: Float {
        switch self {
        case .preview:
            return 10
        case .interactive:
            return 24
        case .final:
            return 64
        }
    }
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

    /// Whether primary camera rays that miss the scene should render the environment.
    ///
    /// When disabled, environment lighting, reflections, and refractions remain active after a
    /// surface hit, but direct camera misses write `backgroundColor` with opaque alpha unless
    /// `transparentBackground` is enabled.
    public var showsEnvironmentBackground: Bool

    /// Linear RGB color used for primary camera misses when the environment background is hidden.
    public var backgroundColor: SIMD3<Float>

    /// Optional denoising applied to beauty output. Defaults to disabled.
    public var denoise: DenoiseSettings

    /// Maximum RGB channel value allowed for one Monte Carlo sample contribution.
    ///
    /// Use `nil` to inherit the value from `quality`, or `0` to disable clamping.
    public var sampleRadianceClamp: Float?

    /// Enables SDF traversal counters for profiling sparse and dense volume paths.
    ///
    /// Disabled by default because the shader uses atomic increments while collecting stats.
    public var collectsSDFTraversalStats: Bool

    /// Creates render settings.
    public init(
        width: Int = 512,
        height: Int = 512,
        maxBounces: Int = 4,
        quality: RenderQuality = .preview,
        previousCamera: Camera? = nil,
        transparentBackground: Bool = false,
        showsEnvironmentBackground: Bool = true,
        backgroundColor: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        denoise: DenoiseSettings = .none,
        sampleRadianceClamp: Float? = nil,
        collectsSDFTraversalStats: Bool = false
    ) {
        self.width = width
        self.height = height
        self.maxBounces = maxBounces
        self.quality = quality
        self.previousCamera = previousCamera
        self.transparentBackground = transparentBackground
        self.showsEnvironmentBackground = showsEnvironmentBackground
        self.backgroundColor = backgroundColor
        self.denoise = denoise
        self.sampleRadianceClamp = sampleRadianceClamp
        self.collectsSDFTraversalStats = collectsSDFTraversalStats
    }

    var resolvedSampleRadianceClamp: Float {
        sampleRadianceClamp ?? quality.defaultSampleRadianceClamp
    }

    var shaderQualityLevel: UInt32 {
        switch quality {
        case .preview:
            return 0
        case .interactive:
            return 1
        case .final:
            return 2
        }
    }
}
