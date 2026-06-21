import Foundation
import simd

/// Stable identifier for a material inside a render scene.
public struct MaterialID: RawRepresentable, Hashable, Sendable {
    /// Zero-based material index.
    public var rawValue: UInt32

    /// Creates a material identifier.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Basic physically inspired material parameters.
public struct Material: Sendable {
    /// Diffuse base color in linear RGB.
    public var baseColor: SIMD3<Float>

    /// Emission color in linear RGB.
    public var emission: SIMD3<Float>

    /// Multiplier applied to the emission color.
    public var emissionStrength: Float

    /// Surface roughness in the range 0...1.
    public var roughness: Float

    /// Metallic amount in the range 0...1.
    public var metallic: Float

    /// Opacity in the range 0...1.
    public var opacity: Float

    /// Creates a material.
    public init(
        baseColor: SIMD3<Float>,
        emission: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        emissionStrength: Float = 0,
        roughness: Float = 0.5,
        metallic: Float = 0,
        opacity: Float = 1
    ) {
        self.baseColor = baseColor
        self.emission = emission
        self.emissionStrength = emissionStrength
        self.roughness = roughness
        self.metallic = metallic
        self.opacity = opacity
    }

    var gpuMaterial: GPUMaterial {
        GPUMaterial(
            baseColor: SIMD4<Float>(baseColor, opacity),
            emission: SIMD4<Float>(emission * emissionStrength, 0),
            parameters: SIMD4<Float>(roughness, metallic, opacity, 0)
        )
    }
}
