import Foundation
import simd

/// Broad grouping for built-in material presets.
public enum BuiltInMaterialCategory: String, CaseIterable, Sendable {
    case diffuse
    case plastic
    case fabric
    case metal
    case coating
    case glass
    case liquid
    case ceramic
    case emission
}

/// One built-in material preset exposed to Swift callers and SceneScript.
public struct BuiltInMaterialPreset: Sendable {
    /// Stable script/API identifier, such as `metal.brushed-aluminum`.
    public let identifier: String

    /// Human-readable display name.
    public let displayName: String

    /// Preset grouping.
    public let category: BuiltInMaterialCategory

    /// Short description for browser UIs.
    public let description: String

    /// Material parameters used by the renderer.
    public let material: Material
}

/// UI-facing metadata for a built-in material preview thumbnail.
public struct BuiltInMaterialPreview: Equatable, Sendable {
    /// Stable script/API identifier, such as `metal.brushed-aluminum`.
    public let identifier: String

    /// Human-readable display name.
    public let displayName: String

    /// Preset grouping.
    public let category: BuiltInMaterialCategory

    /// Short description for browser UIs.
    public let description: String

    /// Repository-relative PNG path for the generated preview thumbnail.
    public let thumbnailPath: String
}

/// Query surface for renderer-provided material presets.
public enum BuiltInMaterialLibrary {
    /// Repository-relative directory for generated built-in material thumbnails.
    public static let previewThumbnailDirectory = "Examples/Renders/Materials"

    /// All built-in presets in UI-friendly order.
    public static let presets: [BuiltInMaterialPreset] = [
        preset(
            "matte.clay",
            "Matte Clay",
            .diffuse,
            "Warm neutral diffuse clay for model previews.",
            Material(baseColor: SIMD3<Float>(0.78, 0.62, 0.48), roughness: 0.82, specular: 0.25)
        ),
        preset(
            "matte.paper",
            "Matte Paper",
            .diffuse,
            "Soft off-white paper with low specular response.",
            Material(baseColor: SIMD3<Float>(0.92, 0.9, 0.86), roughness: 0.9, specular: 0.18)
        ),
        preset(
            "matte.charcoal",
            "Matte Charcoal",
            .diffuse,
            "Dark rough diffuse surface.",
            Material(baseColor: SIMD3<Float>(0.025, 0.025, 0.023), roughness: 0.86, specular: 0.12)
        ),
        preset(
            "plastic.soft-black",
            "Soft Black Plastic",
            .plastic,
            "Dark plastic with readable broad highlights.",
            Material(baseColor: SIMD3<Float>(0.035, 0.034, 0.032), roughness: 0.38, specular: 0.55, clearcoat: 0.18, clearcoatRoughness: 0.24)
        ),
        preset(
            "plastic.gloss-white",
            "Gloss White Plastic",
            .plastic,
            "White molded plastic with a clear glossy coat.",
            Material(baseColor: SIMD3<Float>(0.86, 0.86, 0.82), roughness: 0.18, specular: 0.7, clearcoat: 0.45, clearcoatRoughness: 0.08)
        ),
        preset(
            "rubber.black",
            "Black Rubber",
            .plastic,
            "Very rough black rubber.",
            Material(baseColor: SIMD3<Float>(0.012, 0.012, 0.011), roughness: 0.78, specular: 0.22)
        ),
        preset(
            "fabric.velvet-purple",
            "Purple Velvet",
            .fabric,
            "Velvet-like fabric using the sheen/fuzz lobe.",
            Material(baseColor: SIMD3<Float>(0.22, 0.08, 0.42), roughness: 0.74, specular: 0.18, sheen: 0.72, sheenColor: SIMD3<Float>(0.72, 0.52, 1.0), sheenRoughness: 0.82)
        ),
        preset(
            "fabric.denim-blue",
            "Blue Denim",
            .fabric,
            "Rough blue fabric with a gentle grazing sheen.",
            Material(baseColor: SIMD3<Float>(0.055, 0.12, 0.26), roughness: 0.88, specular: 0.16, sheen: 0.3, sheenColor: SIMD3<Float>(0.35, 0.5, 0.78), sheenRoughness: 0.9)
        ),
        preset(
            "metal.chrome",
            "Chrome",
            .metal,
            "Polished neutral mirror-like metal.",
            Material(baseColor: SIMD3<Float>(0.95, 0.95, 0.93), roughness: 0.012, metallic: 1)
        ),
        preset(
            "metal.aluminum",
            "Aluminum",
            .metal,
            "Clean bright aluminum.",
            Material(baseColor: SIMD3<Float>(0.84, 0.85, 0.84), roughness: 0.08, metallic: 1)
        ),
        preset(
            "metal.brushed-aluminum",
            "Brushed Aluminum",
            .metal,
            "Anisotropic satin aluminum.",
            Material(baseColor: SIMD3<Float>(0.84, 0.85, 0.84), roughness: 0.16, metallic: 1, specularAnisotropy: 0.72)
        ),
        preset(
            "metal.gold",
            "Gold",
            .metal,
            "Polished warm gold.",
            Material(baseColor: SIMD3<Float>(1.0, 0.72, 0.29), roughness: 0.06, metallic: 1)
        ),
        preset(
            "metal.copper",
            "Copper",
            .metal,
            "Polished copper.",
            Material(baseColor: SIMD3<Float>(0.98, 0.45, 0.24), roughness: 0.07, metallic: 1)
        ),
        preset(
            "coating.car-red",
            "Red Automotive Paint",
            .coating,
            "Glossy red paint with a clearcoat layer.",
            Material(baseColor: SIMD3<Float>(0.72, 0.025, 0.018), roughness: 0.34, specular: 0.55, clearcoat: 0.9, clearcoatColor: SIMD3<Float>(1.0, 0.92, 0.88), clearcoatRoughness: 0.045)
        ),
        preset(
            "coating.pearl-white",
            "Pearl White Paint",
            .coating,
            "Bright coated paint with subtle warm clearcoat tint.",
            Material(baseColor: SIMD3<Float>(0.86, 0.84, 0.78), roughness: 0.28, specular: 0.6, clearcoat: 0.85, clearcoatColor: SIMD3<Float>(1.0, 0.94, 0.82), clearcoatRoughness: 0.04)
        ),
        preset(
            "coating.iridescent-amber",
            "Iridescent Amber Coating",
            .coating,
            "Glossy amber coated surface with thin-film color shift.",
            Material(
                baseColor: SIMD3<Float>(0.88, 0.24, 0.035),
                roughness: 0.18,
                specular: 0.72,
                specularColor: SIMD3<Float>(1.0, 0.9, 0.74),
                clearcoat: 0.95,
                clearcoatColor: SIMD3<Float>(1.0, 0.68, 0.2),
                clearcoatRoughness: 0.035,
                clearcoatIndexOfRefraction: 1.55,
                thinFilm: 0.48,
                thinFilmThicknessNanometers: 520,
                thinFilmIndexOfRefraction: 1.38
            )
        ),
        preset(
            "glass.clear",
            "Clear Glass",
            .glass,
            "Clear solid dielectric glass.",
            Material(baseColor: SIMD3<Float>(0.92, 0.98, 0.98), roughness: 0.01, specular: 1, indexOfRefraction: 1.45, transmission: 1, transmissionColor: SIMD3<Float>(0.96, 1.0, 1.0), transmissionRoughness: 0.01, transmissionIndexOfRefraction: 1.45)
        ),
        preset(
            "glass.frosted",
            "Frosted Glass",
            .glass,
            "Rough transmissive glass.",
            Material(baseColor: SIMD3<Float>(0.75, 0.9, 0.95), roughness: 0.32, specular: 0.9, indexOfRefraction: 1.45, transmission: 0.92, transmissionColor: SIMD3<Float>(0.82, 0.94, 1.0), transmissionRoughness: 0.3, transmissionIndexOfRefraction: 1.45)
        ),
        preset(
            "glass.thin-pane",
            "Thin Glass Pane",
            .glass,
            "Zero-thickness glass pane for windows and tabletops.",
            Material(baseColor: SIMD3<Float>(0.9, 0.98, 1.0), roughness: 0.012, specular: 1, indexOfRefraction: 1.45, transmission: 1, transmissionColor: SIMD3<Float>(0.94, 1.0, 1.0), transmissionRoughness: 0.012, transmissionIndexOfRefraction: 1.45, thinWalled: true)
        ),
        preset(
            "liquid.water",
            "Water",
            .liquid,
            "Clear water with IOR 1.333.",
            Material(baseColor: SIMD3<Float>(0.72, 0.9, 1.0), roughness: 0.002, specular: 1, indexOfRefraction: 1.333, transmission: 1, transmissionColor: SIMD3<Float>(0.8, 0.95, 1.0), transmissionRoughness: 0.002, transmissionIndexOfRefraction: 1.333)
        ),
        preset(
            "ceramic.white",
            "White Ceramic",
            .ceramic,
            "Glazed white ceramic.",
            Material(baseColor: SIMD3<Float>(0.82, 0.8, 0.76), roughness: 0.18, specular: 0.65, clearcoat: 0.58, clearcoatRoughness: 0.12)
        ),
        preset(
            "ceramic.porcelain",
            "Porcelain",
            .ceramic,
            "Smooth porcelain with soft off-white tint.",
            Material(baseColor: SIMD3<Float>(0.9, 0.88, 0.82), roughness: 0.1, specular: 0.72, clearcoat: 0.5, clearcoatRoughness: 0.07)
        ),
        preset(
            "emission.warm-panel",
            "Warm Light Panel",
            .emission,
            "Warm white area-light material.",
            Material(baseColor: SIMD3<Float>(1, 0.92, 0.8), emission: SIMD3<Float>(1, 0.78, 0.55), emissionStrength: 4, roughness: 0.5, specular: 0)
        ),
        preset(
            "emission.cool-panel",
            "Cool Light Panel",
            .emission,
            "Cool white area-light material.",
            Material(baseColor: SIMD3<Float>(0.82, 0.9, 1), emission: SIMD3<Float>(0.65, 0.78, 1), emissionStrength: 4, roughness: 0.5, specular: 0)
        )
    ]

    /// All stable preset identifiers.
    public static var identifiers: [String] {
        presets.map(\.identifier)
    }

    /// UI-facing preview metadata in the same order as `presets`.
    public static var previews: [BuiltInMaterialPreview] {
        presets.map { preview(for: $0) }
    }

    /// Presets in a category.
    public static func presets(in category: BuiltInMaterialCategory) -> [BuiltInMaterialPreset] {
        presets.filter { $0.category == category }
    }

    /// UI-facing preview metadata in a category.
    public static func previews(in category: BuiltInMaterialCategory) -> [BuiltInMaterialPreview] {
        presets(in: category).map { preview(for: $0) }
    }

    /// Finds a preset by identifier. Lookup is case-insensitive and treats `_` like `-`.
    public static func preset(named identifier: String) -> BuiltInMaterialPreset? {
        let key = normalized(identifier)
        return presets.first { normalized($0.identifier) == key }
    }

    /// Finds UI-facing preview metadata by preset identifier.
    public static func preview(named identifier: String) -> BuiltInMaterialPreview? {
        preset(named: identifier).map { preview(for: $0) }
    }

    /// Repository-relative thumbnail path for a preset identifier.
    public static func thumbnailPath(for identifier: String) -> String {
        "\(previewThumbnailDirectory)/\(identifier).png"
    }

    /// Finds a material by preset identifier.
    public static func material(named identifier: String) -> Material? {
        preset(named: identifier)?.material
    }

    private static func preview(for preset: BuiltInMaterialPreset) -> BuiltInMaterialPreview {
        BuiltInMaterialPreview(
            identifier: preset.identifier,
            displayName: preset.displayName,
            category: preset.category,
            description: preset.description,
            thumbnailPath: thumbnailPath(for: preset.identifier)
        )
    }

    private static func preset(
        _ identifier: String,
        _ displayName: String,
        _ category: BuiltInMaterialCategory,
        _ description: String,
        _ material: Material
    ) -> BuiltInMaterialPreset {
        BuiltInMaterialPreset(
            identifier: identifier,
            displayName: displayName,
            category: category,
            description: description,
            material: material
        )
    }

    private static func normalized(_ identifier: String) -> String {
        identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
