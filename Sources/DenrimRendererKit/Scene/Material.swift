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

    /// Specular lobe anisotropy in the range -1...1.
    public var specularAnisotropy: Float

    /// Clearcoat lobe weight in the range 0...1.
    public var clearcoat: Float

    /// Clearcoat reflection tint in linear RGB.
    public var clearcoatColor: SIMD3<Float>

    /// Color remaining after traveling `clearcoatThickness` through the coating. Nil inherits `clearcoatColor`.
    public var clearcoatAttenuationColor: SIMD3<Float>?

    /// Clearcoat depth used for tint attenuation through the coating. Zero disables depth attenuation.
    public var clearcoatThickness: Float

    /// Clearcoat roughness in the range 0...1.
    public var clearcoatRoughness: Float

    /// Index of refraction used for clearcoat Fresnel behavior.
    public var clearcoatIndexOfRefraction: Float

    /// Thin-film interference strength in the range 0...1 for reflective lobes.
    public var thinFilm: Float

    /// Thin-film optical thickness in nanometers.
    public var thinFilmThicknessNanometers: Float

    /// Index of refraction for the thin-film layer.
    public var thinFilmIndexOfRefraction: Float

    /// Grazing fabric / fuzz reflection weight in the range 0...1.
    public var sheen: Float

    /// Grazing fabric / fuzz reflection tint in linear RGB.
    public var sheenColor: SIMD3<Float>

    /// Grazing fabric / fuzz lobe roughness in the range 0...1.
    public var sheenRoughness: Float

    /// Subsurface scattering weight in the range 0...1.
    public var subsurface: Float

    /// Multiple-scattering albedo tint for subsurface random walk.
    public var subsurfaceColor: SIMD3<Float>

    /// Per-channel mean free path radius in scene units.
    public var subsurfaceRadius: SIMD3<Float>

    /// Multiplier applied to `subsurfaceRadius`.
    public var subsurfaceScale: Float

    /// Henyey-Greenstein phase anisotropy in the range -0.95...0.95.
    public var subsurfaceAnisotropy: Float

    /// Opacity in the range 0...1.
    public var opacity: Float

    /// Specular transmission weight in the range 0...1.
    public var transmission: Float

    /// Specular transmission tint in linear RGB.
    public var transmissionColor: SIMD3<Float>

    /// Specular transmission microfacet roughness in the range 0...1.
    public var transmissionRoughness: Float

    /// Index of refraction used for specular transmission.
    public var transmissionIndexOfRefraction: Float

    /// Remaining transmission color after traveling `transmissionAbsorptionDistance` units through the material.
    public var transmissionAbsorptionColor: SIMD3<Float>

    /// Distance at which `transmissionAbsorptionColor` is reached. Zero disables absorption.
    public var transmissionAbsorptionDistance: Float

    /// Treats transmission as a zero-thickness surface with no volume refraction.
    public var thinWalled: Bool

    /// Participating-medium scattering strength for solid transmissive materials.
    public var volumeScattering: Float

    /// Participating-medium scattering tint in linear RGB.
    public var volumeScatteringColor: SIMD3<Float>

    /// Mean free path distance for participating-medium scattering. Zero disables scattering.
    public var volumeScatteringDistance: Float

    /// Henyey-Greenstein phase anisotropy for participating-medium scattering.
    public var volumeAnisotropy: Float

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
        specularAnisotropy: Float = 0,
        clearcoat: Float = 0,
        clearcoatColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        clearcoatAttenuationColor: SIMD3<Float>? = nil,
        clearcoatThickness: Float = 0,
        clearcoatRoughness: Float = 0.1,
        clearcoatIndexOfRefraction: Float = 1.5,
        thinFilm: Float = 0,
        thinFilmThicknessNanometers: Float = 450,
        thinFilmIndexOfRefraction: Float = 1.45,
        sheen: Float = 0,
        sheenColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        sheenRoughness: Float = 0.5,
        subsurface: Float = 0,
        subsurfaceColor: SIMD3<Float>? = nil,
        subsurfaceRadius: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        subsurfaceScale: Float = 1,
        subsurfaceAnisotropy: Float = 0,
        opacity: Float = 1,
        transmission: Float = 0,
        transmissionColor: SIMD3<Float>? = nil,
        transmissionRoughness: Float? = nil,
        transmissionIndexOfRefraction: Float? = nil,
        transmissionAbsorptionColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        transmissionAbsorptionDistance: Float = 0,
        thinWalled: Bool = false,
        volumeScattering: Float = 0,
        volumeScatteringColor: SIMD3<Float>? = nil,
        volumeScatteringDistance: Float = 1,
        volumeAnisotropy: Float = 0,
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
        self.specularAnisotropy = specularAnisotropy
        self.clearcoat = clearcoat
        self.clearcoatColor = clearcoatColor
        self.clearcoatAttenuationColor = clearcoatAttenuationColor
        self.clearcoatThickness = clearcoatThickness
        self.clearcoatRoughness = clearcoatRoughness
        self.clearcoatIndexOfRefraction = clearcoatIndexOfRefraction
        self.thinFilm = thinFilm
        self.thinFilmThicknessNanometers = thinFilmThicknessNanometers
        self.thinFilmIndexOfRefraction = thinFilmIndexOfRefraction
        self.sheen = sheen
        self.sheenColor = sheenColor
        self.sheenRoughness = sheenRoughness
        self.subsurface = subsurface
        self.subsurfaceColor = subsurfaceColor ?? baseColor
        self.subsurfaceRadius = subsurfaceRadius
        self.subsurfaceScale = subsurfaceScale
        self.subsurfaceAnisotropy = subsurfaceAnisotropy
        self.opacity = opacity
        self.transmission = transmission
        self.transmissionColor = transmissionColor ?? baseColor
        self.transmissionRoughness = transmissionRoughness ?? roughness
        self.transmissionIndexOfRefraction = transmissionIndexOfRefraction ?? indexOfRefraction
        self.transmissionAbsorptionColor = transmissionAbsorptionColor
        self.transmissionAbsorptionDistance = transmissionAbsorptionDistance
        self.thinWalled = thinWalled
        self.volumeScattering = volumeScattering
        self.volumeScatteringColor = volumeScatteringColor ?? transmissionColor ?? baseColor
        self.volumeScatteringDistance = volumeScatteringDistance
        self.volumeAnisotropy = volumeAnisotropy
        self.baseColorTexture = baseColorTexture
        self.normalMap = normalMap
    }

    func gpuMaterial(baseColorTextureIndex: Int? = nil, normalMapIndex: Int? = nil) -> GPUMaterial {
        GPUMaterial(
            baseColor: SIMD4<Float>(baseColor, opacity),
            emission: SIMD4<Float>(emission * emissionStrength, transmission),
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
            specularColor: SIMD4<Float>(specularColor, clearcoatIndexOfRefraction),
            sheenColor: SIMD4<Float>(sheenColor, sheen),
            transmissionColor: SIMD4<Float>(transmissionColor, thinWalled ? 1 : 0),
            parameters3: SIMD4<Float>(
                sheenRoughness,
                transmissionRoughness,
                transmissionIndexOfRefraction,
                specularAnisotropy
            ),
            clearcoatColor: SIMD4<Float>(clearcoatColor, 0),
            clearcoatAttenuation: SIMD4<Float>(
                clearcoatAttenuationColor ?? clearcoatColor,
                clearcoatThickness
            ),
            transmissionAbsorption: SIMD4<Float>(
                transmissionAbsorptionColor,
                transmissionAbsorptionDistance
            ),
            thinFilm: SIMD4<Float>(
                thinFilm,
                thinFilmThicknessNanometers,
                thinFilmIndexOfRefraction,
                0
            ),
            subsurfaceColor: SIMD4<Float>(subsurfaceColor, subsurface),
            subsurfaceRadius: SIMD4<Float>(
                subsurfaceRadius,
                subsurfaceScale
            ),
            subsurfaceParameters: SIMD4<Float>(
                subsurfaceAnisotropy,
                0,
                0,
                0
            ),
            volumeScattering: SIMD4<Float>(
                volumeScatteringColor,
                volumeScattering
            ),
            volumeParameters: SIMD4<Float>(
                volumeScatteringDistance,
                volumeAnisotropy,
                0,
                0
            )
        )
    }
}
