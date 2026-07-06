import Foundation
import simd

extension LinearTriangleAccelerationBackend {
    static func gpuMaterialsAndTextures(
        scene: RenderScene
    ) -> (
        materials: [GPUMaterial],
        semantics: [GPUMaterialSemanticDescriptor],
        descriptors: [GPUTextureDescriptor],
        pixels: [SIMD4<Float>],
        environmentTextureIndexPlusOne: UInt32
    ) {
        var descriptors: [GPUTextureDescriptor] = []
        var pixels: [SIMD4<Float>] = []

        func append(_ texture: Texture2D?) -> Int? {
            guard let texture, texture.width > 0, texture.height > 0 else {
                return nil
            }
            let expectedPixelCount = texture.width * texture.height
            guard expectedPixelCount > 0, texture.pixels.count >= expectedPixelCount else {
                return nil
            }

            let index = descriptors.count
            descriptors.append(GPUTextureDescriptor(
                metadata: SIMD4<UInt32>(
                    UInt32(pixels.count),
                    UInt32(texture.width),
                    UInt32(texture.height),
                    texture.samplingMode.rawValue
                )
            ))
            pixels.append(contentsOf: texture.pixels.prefix(expectedPixelCount))
            return index
        }

        let resolvedMaterials = scene.materialSources.map { $0.resolvedMaterial() }
        let semantics = scene.materialSources.map(gpuMaterialSemanticDescriptor)
        let materials = resolvedMaterials.map { material in
            let baseColorTextureIndex = append(material.baseColorTexture)
            let normalMapIndex = append(material.normalMap)
            return material.gpuMaterial(
                baseColorTextureIndex: baseColorTextureIndex,
                normalMapIndex: normalMapIndex
            )
        }

        let environmentTextureIndexPlusOne = append(scene.environment.texture).map { UInt32($0 + 1) } ?? 0

        return (materials, semantics, descriptors, pixels, environmentTextureIndexPlusOne)
    }

    static func gpuMaterialSemanticDescriptor(
        _ source: SemanticMaterial
    ) -> GPUMaterialSemanticDescriptor {
        let style = source.style
        let attributes = source.attributes
        return GPUMaterialSemanticDescriptor(
            metadata: SIMD4<UInt32>(
                materialArchetypeID(source.archetype),
                source.physicalOverride == nil ? 1 : 0,
                0,
                0
            ),
            style0: SIMD4<Float>(style.primaryColor, style.roughness),
            style1: SIMD4<Float>(style.secondaryColor, style.metallic),
            style2: SIMD4<Float>(style.accentColor, style.opacity),
            controls0: SIMD4<Float>(
                attributes.amount,
                attributes.age,
                attributes.wetness,
                attributes.polish
            ),
            controls1: SIMD4<Float>(
                attributes.cavity,
                attributes.emission,
                style.transmission,
                style.emissionStrength
            )
        )
    }

    static func materialArchetypeID(_ archetype: MaterialArchetype) -> UInt32 {
        switch archetype {
        case .plain: return 0
        case .moss: return 1
        case .bark: return 2
        case .wetFilm: return 3
        case .crystal: return 4
        case .wax: return 5
        case .ceramic: return 6
        case .metal: return 7
        case .rust: return 8
        case .burn: return 9
        case .ice: return 10
        case .lava: return 11
        case .emissive: return 12
        }
    }
}
