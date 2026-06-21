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

    /// Dielectric specular reflection weight in the range 0...1.
    public var specular: Float

    /// Dielectric specular reflection tint in linear RGB.
    public var specularColor: SIMD3<Float>

    /// Index of refraction used for dielectric Fresnel behavior.
    public var indexOfRefraction: Float

    /// Clearcoat lobe weight in the range 0...1.
    public var clearcoat: Float

    /// Clearcoat roughness in the range 0...1.
    public var clearcoatRoughness: Float

    /// Index of refraction used for clearcoat Fresnel behavior.
    public var clearcoatIndexOfRefraction: Float

    /// Opacity in the range 0...1.
    public var opacity: Float

    /// Optional base color texture sampled by mesh UVs.
    public var baseColorTexture: Texture2D?

    /// Optional tangent-space normal map sampled by mesh UVs.
    public var normalMap: Texture2D?

    /// Creates a material.
    public init(
        baseColor: SIMD3<Float>,
        emission: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        emissionStrength: Float = 0,
        roughness: Float = 0.5,
        metallic: Float = 0,
        specular: Float = 1,
        specularColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        indexOfRefraction: Float = 1.5,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1,
        clearcoatIndexOfRefraction: Float = 1.5,
        opacity: Float = 1,
        baseColorTexture: Texture2D? = nil,
        normalMap: Texture2D? = nil
    ) {
        self.baseColor = baseColor
        self.emission = emission
        self.emissionStrength = emissionStrength
        self.roughness = roughness
        self.metallic = metallic
        self.specular = specular
        self.specularColor = specularColor
        self.indexOfRefraction = indexOfRefraction
        self.clearcoat = clearcoat
        self.clearcoatRoughness = clearcoatRoughness
        self.clearcoatIndexOfRefraction = clearcoatIndexOfRefraction
        self.opacity = opacity
        self.baseColorTexture = baseColorTexture
        self.normalMap = normalMap
    }

    func gpuMaterial(baseColorTextureIndex: Int? = nil, normalMapIndex: Int? = nil) -> GPUMaterial {
        GPUMaterial(
            baseColor: SIMD4<Float>(baseColor, opacity),
            emission: SIMD4<Float>(emission * emissionStrength, 0),
            parameters: SIMD4<Float>(
                roughness,
                metallic,
                Float((baseColorTextureIndex ?? -1) + 1),
                Float((normalMapIndex ?? -1) + 1)
            ),
            parameters2: SIMD4<Float>(
                specular,
                indexOfRefraction,
                clearcoat,
                clearcoatRoughness
            ),
            specularColor: SIMD4<Float>(specularColor, clearcoatIndexOfRefraction)
        )
    }
}
