import Foundation

/// Background illumination sampled when a ray leaves the scene.
public struct Environment: Sendable, Equatable {
    /// Optional equirectangular environment map in linear RGB.
    public var texture: Texture2D?

    /// Multiplier applied to either the texture or built-in sky gradient.
    public var intensity: Float

    /// Rotation around the world Y axis in radians.
    public var rotationY: Float

    /// Maximum HDR value per color channel after sampling.
    public var maxRadiance: Float

    public init(
        texture: Texture2D? = nil,
        intensity: Float = 1,
        rotationY: Float = 0,
        maxRadiance: Float = 16
    ) {
        self.texture = texture
        self.intensity = intensity
        self.rotationY = rotationY
        self.maxRadiance = maxRadiance
    }

    /// Default procedural sky.
    public static let sky = Environment()
}
