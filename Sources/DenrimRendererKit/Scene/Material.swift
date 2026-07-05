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

/// Semantic material families that can be expanded into renderer materials.
public enum MaterialArchetype: String, Sendable {
    case plain
    case moss
    case bark
    case wetFilm
    case crystal
    case wax
    case ceramic
    case metal
    case rust
    case burn
    case ice
    case lava
    case emissive
}

/// Artist-facing material style for semantic material families.
public struct MaterialStyle: Sendable {
    public var primaryColor: SIMD3<Float>
    public var secondaryColor: SIMD3<Float>
    public var accentColor: SIMD3<Float>
    public var roughness: Float
    public var metallic: Float
    public var opacity: Float
    public var transmission: Float
    public var emissionStrength: Float

    public init(
        primaryColor: SIMD3<Float>,
        secondaryColor: SIMD3<Float>? = nil,
        accentColor: SIMD3<Float>? = nil,
        roughness: Float = 0.5,
        metallic: Float = 0,
        opacity: Float = 1,
        transmission: Float = 0,
        emissionStrength: Float = 0
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor ?? primaryColor
        self.accentColor = accentColor ?? primaryColor
        self.roughness = roughness
        self.metallic = metallic
        self.opacity = opacity
        self.transmission = transmission
        self.emissionStrength = emissionStrength
    }
}

/// Compact semantic controls that material families interpret into renderer parameters.
public struct MaterialSemanticAttributes: Sendable {
    public var amount: Float
    public var age: Float
    public var wetness: Float
    public var polish: Float
    public var cavity: Float
    public var emission: Float

    public init(
        amount: Float = 1,
        age: Float = 0,
        wetness: Float = 0,
        polish: Float = 0,
        cavity: Float = 0,
        emission: Float = 0
    ) {
        self.amount = amount
        self.age = age
        self.wetness = wetness
        self.polish = polish
        self.cavity = cavity
        self.emission = emission
    }
}

/// Authored material intent.
///
/// RendererKit expands this semantic source into `Material` when compiling a
/// scene. Host products can keep artist-facing controls like moss age, wetness,
/// polish, and editable palettes without storing a full renderer material at
/// every SDF sample.
public struct SemanticMaterial: Sendable {
    public var archetype: MaterialArchetype
    public var style: MaterialStyle
    public var attributes: MaterialSemanticAttributes
    public var physicalOverride: Material?

    public init(
        archetype: MaterialArchetype,
        style: MaterialStyle,
        attributes: MaterialSemanticAttributes = MaterialSemanticAttributes()
    ) {
        self.archetype = archetype
        self.style = style
        self.attributes = attributes
        self.physicalOverride = nil
    }

    public static func physical(_ material: Material) -> SemanticMaterial {
        var source = SemanticMaterial(
            archetype: .plain,
            style: MaterialStyle(
                primaryColor: material.baseColor,
                roughness: material.roughness,
                metallic: material.metallic,
                opacity: material.opacity,
                transmission: material.transmission,
                emissionStrength: material.emissionStrength
            )
        )
        source.physicalOverride = material
        return source
    }

    public static func plain(
        color: SIMD3<Float>,
        roughness: Float = 0.55,
        metallic: Float = 0
    ) -> SemanticMaterial {
        SemanticMaterial(
            archetype: .plain,
            style: MaterialStyle(primaryColor: color, roughness: roughness, metallic: metallic)
        )
    }

    public static func moss(
        youngColor: SIMD3<Float> = SIMD3<Float>(0.42, 0.68, 0.22),
        matureColor: SIMD3<Float> = SIMD3<Float>(0.12, 0.38, 0.12),
        dryColor: SIMD3<Float> = SIMD3<Float>(0.45, 0.34, 0.18),
        age: Float = 0.35,
        wetness: Float = 0
    ) -> SemanticMaterial {
        SemanticMaterial(
            archetype: .moss,
            style: MaterialStyle(
                primaryColor: youngColor,
                secondaryColor: matureColor,
                accentColor: dryColor,
                roughness: 0.86
            ),
            attributes: MaterialSemanticAttributes(age: age, wetness: wetness)
        )
    }

    public static func wetFilm(
        tint: SIMD3<Float> = SIMD3<Float>(0.55, 0.72, 0.82),
        wetness: Float = 1
    ) -> SemanticMaterial {
        SemanticMaterial(
            archetype: .wetFilm,
            style: MaterialStyle(
                primaryColor: tint,
                roughness: 0.08,
                opacity: 0.55,
                transmission: 0.65
            ),
            attributes: MaterialSemanticAttributes(wetness: wetness, polish: 1)
        )
    }

    public static func crystal(
        color: SIMD3<Float> = SIMD3<Float>(0.75, 0.9, 1),
        clarity: Float = 0.85,
        polish: Float = 0.8
    ) -> SemanticMaterial {
        SemanticMaterial(
            archetype: .crystal,
            style: MaterialStyle(
                primaryColor: color,
                roughness: 0.18,
                opacity: simd_clamp(1 - clarity * 0.25, 0, 1),
                transmission: clarity
            ),
            attributes: MaterialSemanticAttributes(polish: polish)
        )
    }

    public static func emissive(
        color: SIMD3<Float>,
        strength: Float
    ) -> SemanticMaterial {
        SemanticMaterial(
            archetype: .emissive,
            style: MaterialStyle(
                primaryColor: color,
                roughness: 0.5,
                emissionStrength: strength
            ),
            attributes: MaterialSemanticAttributes(emission: 1)
        )
    }

    public func resolvedMaterial() -> Material {
        if let physicalOverride {
            return physicalOverride
        }

        let amount = simd_clamp(attributes.amount, 0, 1)
        let age = simd_clamp(attributes.age, 0, 1)
        let wetness = simd_clamp(attributes.wetness, 0, 1)
        let polish = simd_clamp(attributes.polish, 0, 1)
        let emission = simd_clamp(attributes.emission, 0, 1)
        let base = mix(style.primaryColor, style.secondaryColor, t: age)

        switch archetype {
        case .plain:
            return Material(
                baseColor: style.primaryColor,
                roughness: style.roughness,
                metallic: style.metallic,
                opacity: style.opacity,
                transmission: style.transmission
            )
        case .moss:
            let aged = mix(base, style.accentColor, t: max(age - 0.65, 0) / 0.35)
            let wetTint = mix(aged, aged * SIMD3<Float>(0.45, 0.62, 0.48), t: wetness)
            return Material(
                baseColor: wetTint,
                roughness: mix(style.roughness, 0.34, t: wetness),
                specular: mix(0.18, 0.45, t: wetness),
                sheen: 0.28 * amount,
                sheenColor: mix(style.primaryColor, style.secondaryColor, t: 0.5),
                sheenRoughness: 0.78,
                subsurface: 0.18 * amount,
                subsurfaceColor: style.primaryColor
            )
        case .bark:
            return Material(
                baseColor: mix(style.primaryColor, style.secondaryColor, t: age),
                roughness: max(style.roughness, 0.74),
                specular: 0.22,
                sheen: 0.12
            )
        case .wetFilm:
            return Material(
                baseColor: style.primaryColor,
                roughness: mix(0.32, 0.025, t: max(wetness, polish)),
                specular: 0.85,
                opacity: mix(0.22, style.opacity, t: wetness),
                transmission: mix(0.2, style.transmission, t: wetness),
                transmissionColor: style.primaryColor,
                transmissionRoughness: 0.025,
                thinWalled: true
            )
        case .crystal:
            return Material(
                baseColor: style.primaryColor,
                roughness: mix(0.32, 0.012, t: polish),
                specular: 1,
                indexOfRefraction: 1.5,
                opacity: style.opacity,
                transmission: style.transmission,
                transmissionColor: style.primaryColor,
                transmissionRoughness: mix(0.25, 0.012, t: polish),
                transmissionIndexOfRefraction: 1.5,
                transmissionAbsorptionColor: mix(SIMD3<Float>(1, 1, 1), style.primaryColor, t: 0.35),
                transmissionAbsorptionDistance: 1.2
            )
        case .wax:
            return Material(
                baseColor: style.primaryColor,
                roughness: max(style.roughness, 0.58),
                specular: 0.35,
                subsurface: 0.46,
                subsurfaceColor: style.secondaryColor,
                transmission: 0.18,
                transmissionColor: style.primaryColor,
                transmissionRoughness: 0.65
            )
        case .ceramic:
            return Material(
                baseColor: style.primaryColor,
                roughness: mix(0.44, 0.08, t: polish),
                specular: 0.62,
                clearcoat: 0.35 + 0.4 * polish,
                clearcoatRoughness: mix(0.18, 0.035, t: polish)
            )
        case .metal:
            return Material(
                baseColor: style.primaryColor,
                roughness: mix(style.roughness, 0.08, t: polish),
                metallic: 1,
                specularAnisotropy: 0.35 * polish
            )
        case .rust:
            return Material(
                baseColor: mix(style.primaryColor, style.accentColor, t: age),
                roughness: 0.9,
                metallic: 0.05,
                specular: 0.18
            )
        case .burn:
            return Material(
                baseColor: mix(style.primaryColor, SIMD3<Float>(0.015, 0.014, 0.012), t: age),
                emission: style.accentColor,
                emissionStrength: style.emissionStrength * emission,
                roughness: 0.82,
                specular: 0.08
            )
        case .ice:
            return Material(
                baseColor: style.primaryColor,
                roughness: mix(0.34, 0.035, t: polish),
                specular: 0.9,
                indexOfRefraction: 1.31,
                transmission: max(style.transmission, 0.72),
                transmissionColor: style.primaryColor,
                transmissionRoughness: mix(0.28, 0.02, t: polish),
                transmissionIndexOfRefraction: 1.31
            )
        case .lava:
            return Material(
                baseColor: mix(style.primaryColor, style.secondaryColor, t: age),
                emission: style.accentColor,
                emissionStrength: max(style.emissionStrength, 2) * max(amount, emission),
                roughness: 0.64,
                specular: 0.22
            )
        case .emissive:
            return Material(
                baseColor: style.primaryColor,
                emission: style.primaryColor,
                emissionStrength: style.emissionStrength,
                roughness: style.roughness,
                specular: 0
            )
        }
    }

    private func mix(_ lhs: Float, _ rhs: Float, t: Float) -> Float {
        lhs + (rhs - lhs) * simd_clamp(t, 0, 1)
    }

    private func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * simd_clamp(t, 0, 1)
    }
}

/// Expanded renderer material produced from semantic material intent.
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
