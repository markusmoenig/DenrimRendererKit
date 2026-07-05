import Foundation
import simd

struct AccelerationBuild {
    var triangles: [GPUTriangle]
    var volumes: [GPUVolumeDescriptor]
    var volumeSamples: [GPUVolumeSample]
    var volumeAttributeDescriptors: [GPUVolumeAttributeDescriptor]
    var volumeAttributeSamples: [SIMD4<Float>]
    var volumeBricks: [GPUVolumeBrickDescriptor]
    var volumeBrickSamples: [GPUVolumeSample]
    var volumeBrickAttributeDescriptors: [GPUVolumeAttributeDescriptor]
    var volumeBrickAttributeSamples: [SIMD4<Float>]
    var materials: [GPUMaterial]
    var materialSemantics: [GPUMaterialSemanticDescriptor]
    var textureDescriptors: [GPUTextureDescriptor]
    var texturePixels: [SIMD4<Float>]
    var environmentTextureIndexPlusOne: UInt32
    var environmentSamples: [GPUEnvironmentSample]
    var lights: [GPULightRecord]
    var bvh: FlatBVH
    var instanceAcceleration: InstanceAcceleration
    var metalRayTracingExperiment: MetalRayTracingExperiment?
}

protocol AccelerationBackend {
    func build(scene: RenderScene) throws -> AccelerationBuild
}

struct LinearTriangleAccelerationBackend: AccelerationBackend {
    var buildsFlatBVH: Bool = true

    func build(scene: RenderScene) throws -> AccelerationBuild {
        let instanceAcceleration = try InstanceAccelerationBuilder(
            buildsLocalBVH: buildsFlatBVH
        ).build(scene: scene)
        let materialResources = Self.gpuMaterialsAndTextures(scene: scene)
        let volumeResources = try Self.gpuVolumes(scene: scene)
        let volumeBrickResources = try Self.gpuVolumeBricks(scene: scene)
        let lightResources = Self.lightRecordsAndTaggedTriangles(
            triangles: instanceAcceleration.materializedTriangles(),
            materials: materialResources.materials
        )
        let triangles = lightResources.triangles
        let flatBVH = buildsFlatBVH
            ? BVHFlattener().flatten(BVHBuilder().build(triangles: triangles))
            : FlatBVH(nodes: [], primitiveIndices: [])

        return AccelerationBuild(
            triangles: triangles,
            volumes: volumeResources.descriptors,
            volumeSamples: volumeResources.samples,
            volumeAttributeDescriptors: volumeResources.attributeDescriptors,
            volumeAttributeSamples: volumeResources.attributeSamples,
            volumeBricks: volumeBrickResources.descriptors,
            volumeBrickSamples: volumeBrickResources.samples,
            volumeBrickAttributeDescriptors: volumeBrickResources.attributeDescriptors,
            volumeBrickAttributeSamples: volumeBrickResources.attributeSamples,
            materials: materialResources.materials,
            materialSemantics: materialResources.semantics,
            textureDescriptors: materialResources.descriptors,
            texturePixels: materialResources.pixels,
            environmentTextureIndexPlusOne: materialResources.environmentTextureIndexPlusOne,
            environmentSamples: Self.environmentSamples(scene: scene),
            lights: lightResources.lights,
            bvh: flatBVH,
            instanceAcceleration: instanceAcceleration,
            metalRayTracingExperiment: nil
        )
    }

    static func gpuVolumes(
        scene: RenderScene
    ) throws -> (
        descriptors: [GPUVolumeDescriptor],
        samples: [GPUVolumeSample],
        attributeDescriptors: [GPUVolumeAttributeDescriptor],
        attributeSamples: [SIMD4<Float>]
    ) {
        var descriptors: [GPUVolumeDescriptor] = []
        var samples: [GPUVolumeSample] = []
        var attributeDescriptors: [GPUVolumeAttributeDescriptor] = []
        var attributeSamples: [SIMD4<Float>] = []

        for (index, instance) in scene.volumeInstances.enumerated() {
            try appendVolume(
                instance.volume,
                material: instance.material,
                transform: instance.transform,
                objectID: scene.meshInstances.count + index,
                primitiveID: index,
                descriptors: &descriptors,
                samples: &samples,
                attributeDescriptors: &attributeDescriptors,
                attributeSamples: &attributeSamples,
                materialCount: scene.materials.count
            )
        }

        let sparseObjectIDBase = scene.meshInstances.count + scene.volumeInstances.count
        let sparsePrimitiveIDBase = scene.volumeInstances.count
        for (index, instance) in scene.sparseVolumeInstances.enumerated() {
            try appendSparseVolumeDescriptor(
                instance.volume,
                material: instance.material,
                transform: instance.transform,
                objectID: sparseObjectIDBase + index,
                primitiveID: sparsePrimitiveIDBase + index,
                descriptors: &descriptors,
                materialCount: scene.materials.count
            )
        }

        return (descriptors, samples, attributeDescriptors, attributeSamples)
    }

    static func gpuVolumeBricks(
        scene: RenderScene
    ) throws -> (
        descriptors: [GPUVolumeBrickDescriptor],
        samples: [GPUVolumeSample],
        attributeDescriptors: [GPUVolumeAttributeDescriptor],
        attributeSamples: [SIMD4<Float>]
    ) {
        var descriptors: [GPUVolumeBrickDescriptor] = []
        var samples: [GPUVolumeSample] = []
        var attributeDescriptors: [GPUVolumeAttributeDescriptor] = []
        var attributeSamples: [SIMD4<Float>] = []

        let sparseVolumeIndexBase = scene.volumeInstances.count
        for (volumeIndex, instance) in scene.sparseVolumeInstances.enumerated() {
            guard Int(instance.material.rawValue) < scene.materials.count else {
                throw DenrimRendererError.invalidScene("Sparse distance volume references an unknown material.")
            }

            let volume = instance.volume
            guard volume.dimensions.x >= 2, volume.dimensions.y >= 2, volume.dimensions.z >= 2 else {
                throw DenrimRendererError.invalidScene("Sparse distance volume dimensions must be at least 2x2x2.")
            }
            guard volume.boundsMax.x > volume.boundsMin.x,
                  volume.boundsMax.y > volume.boundsMin.y,
                  volume.boundsMax.z > volume.boundsMin.z else {
                throw DenrimRendererError.invalidScene("Sparse distance volume bounds must have positive extent.")
            }

            for brick in volume.bricks {
                try validate(brick: brick, in: volume)
                let sampleOffset = samples.count
                for sampleIndex in brick.distances.indices {
                    let materialSample = brick.materialSamples[sampleIndex]
                    samples.append(gpuVolumeSample(
                        distance: brick.distances[sampleIndex],
                        material: materialSample
                    ))
                }

                let attributeOffset = attributeSamples.count
                let packedVectorCount = volume.attributeLayout.packedVectorCount
                let brickIndex = descriptors.count
                if packedVectorCount > 0 {
                    let expectedAttributeCount = brick.distances.count * packedVectorCount
                    guard brick.attributeSamples.count >= expectedAttributeCount else {
                        throw DenrimRendererError.invalidScene("Sparse distance volume brick attribute sample count does not match its layout.")
                    }
                    attributeSamples.append(contentsOf: brick.attributeSamples.prefix(expectedAttributeCount))
                }
                attributeDescriptors.append(gpuVolumeAttributeDescriptor(
                    layout: volume.attributeLayout,
                    sampleOffset: attributeOffset,
                    sampleCount: brick.distances.count,
                    volumeOrBrickIndex: brickIndex
                ))

                let localBounds = brickCoreLocalBounds(brick: brick, in: volume)
                let worldBounds = transformedBounds(
                    minimum: localBounds.minimum,
                    maximum: localBounds.maximum,
                    transform: instance.transform
                )
                descriptors.append(GPUVolumeBrickDescriptor(
                    worldBoundsMin: SIMD4<Float>(worldBounds.minimum, 0),
                    worldBoundsMax: SIMD4<Float>(worldBounds.maximum, 0),
                    localBoundsMin: SIMD4<Float>(localBounds.minimum, 0),
                    localBoundsMax: SIMD4<Float>(localBounds.maximum, 0),
                    gridOriginAndVolume: SIMD4<UInt32>(
                        UInt32(brick.origin.x),
                        UInt32(brick.origin.y),
                        UInt32(brick.origin.z),
                        UInt32(sparseVolumeIndexBase + volumeIndex)
                    ),
                    dimensionsAndSampleOffset: SIMD4<UInt32>(
                        UInt32(brick.dimensions.x),
                        UInt32(brick.dimensions.y),
                        UInt32(brick.dimensions.z),
                        UInt32(sampleOffset)
                    )
                ))
            }
        }

        return (descriptors, samples, attributeDescriptors, attributeSamples)
    }

    private static func appendVolume(
        _ volume: DistanceVolume,
        material: MaterialID,
        transform: Transform,
        objectID: Int,
        primitiveID: Int,
        descriptors: inout [GPUVolumeDescriptor],
        samples: inout [GPUVolumeSample],
        attributeDescriptors: inout [GPUVolumeAttributeDescriptor],
        attributeSamples: inout [SIMD4<Float>],
        materialCount: Int
    ) throws {
        guard Int(material.rawValue) < materialCount else {
            throw DenrimRendererError.invalidScene("Distance volume references an unknown material.")
        }

        let dimensions = volume.dimensions
        guard dimensions.x >= 2, dimensions.y >= 2, dimensions.z >= 2 else {
            throw DenrimRendererError.invalidScene("Distance volume dimensions must be at least 2x2x2.")
        }

        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        guard sampleCount > 0, volume.distances.count >= sampleCount else {
            throw DenrimRendererError.invalidScene("Distance volume sample count does not match its dimensions.")
        }
        if !volume.materialSamples.isEmpty,
           volume.materialSamples.count < sampleCount {
            throw DenrimRendererError.invalidScene("Distance volume material sample count does not match its dimensions.")
        }
        let packedVectorCount = volume.attributeLayout.packedVectorCount
        if packedVectorCount > 0,
           volume.attributeSamples.count < sampleCount * packedVectorCount {
            throw DenrimRendererError.invalidScene("Distance volume attribute sample count does not match its layout.")
        }

        let boundsMin = volume.boundsMin
        let boundsMax = volume.boundsMax
        guard boundsMax.x > boundsMin.x,
              boundsMax.y > boundsMin.y,
              boundsMax.z > boundsMin.z else {
            throw DenrimRendererError.invalidScene("Distance volume bounds must have positive extent.")
        }

        let sampleOffset = samples.count
        for sampleIndex in 0..<sampleCount {
            let materialSample = volume.materialSamples.isEmpty
                ? DistanceVolumeMaterialSample(materialA: material)
                : volume.materialSamples[sampleIndex]
            samples.append(gpuVolumeSample(
                distance: volume.distances[sampleIndex],
                material: materialSample
            ))
        }
        let attributeOffset = attributeSamples.count
        if packedVectorCount > 0 {
            attributeSamples.append(contentsOf: volume.attributeSamples.prefix(sampleCount * packedVectorCount))
        }
        attributeDescriptors.append(gpuVolumeAttributeDescriptor(
            layout: volume.attributeLayout,
            sampleOffset: attributeOffset,
            sampleCount: sampleCount,
            volumeOrBrickIndex: descriptors.count
        ))

        let worldBounds = transformedBounds(
            minimum: boundsMin,
            maximum: boundsMax,
            transform: transform
        )
        let worldToLocal = transform.matrix.inverse
        let normalTransform = transform.matrix.transpose.inverse
        descriptors.append(GPUVolumeDescriptor(
            worldBoundsMin: SIMD4<Float>(worldBounds.minimum, 0),
            worldBoundsMax: SIMD4<Float>(worldBounds.maximum, 0),
            localBoundsMin: SIMD4<Float>(boundsMin, 0),
            localBoundsMax: SIMD4<Float>(boundsMax, 0),
            dimensions: SIMD4<UInt32>(
                UInt32(dimensions.x),
                UInt32(dimensions.y),
                UInt32(dimensions.z),
                material.rawValue
            ),
            metadata: SIMD4<UInt32>(
                UInt32(sampleOffset),
                UInt32(objectID),
                UInt32(primitiveID),
                0
            ),
            worldToLocal0: worldToLocal.columns.0,
            worldToLocal1: worldToLocal.columns.1,
            worldToLocal2: worldToLocal.columns.2,
            worldToLocal3: worldToLocal.columns.3,
            normalTransform0: normalTransform.columns.0,
            normalTransform1: normalTransform.columns.1,
            normalTransform2: normalTransform.columns.2,
            normalTransform3: normalTransform.columns.3
        ))
    }

    private static func gpuVolumeAttributeDescriptor(
        layout: DistanceVolumeAttributeLayout,
        sampleOffset: Int,
        sampleCount: Int,
        volumeOrBrickIndex: Int
    ) -> GPUVolumeAttributeDescriptor {
        var semantics = [UInt32](repeating: 0, count: DistanceVolumeAttributeLayout.maximumChannelCount)
        for (index, channel) in layout.channels.enumerated() where index < semantics.count {
            semantics[index] = channel.semantic.rawValue
        }
        return GPUVolumeAttributeDescriptor(
            metadata: SIMD4<UInt32>(
                UInt32(sampleOffset),
                UInt32(layout.packedVectorCount),
                UInt32(sampleCount),
                UInt32(volumeOrBrickIndex)
            ),
            semantics0: SIMD4<UInt32>(semantics[0], semantics[1], semantics[2], semantics[3]),
            semantics1: SIMD4<UInt32>(semantics[4], semantics[5], semantics[6], semantics[7])
        )
    }

    private static func gpuVolumeSample(
        distance: Float,
        material: DistanceVolumeMaterialSample
    ) -> GPUVolumeSample {
        GPUVolumeSample(
            distance: distance,
            materialA: material.materialA.rawValue,
            materialB: material.materialB.rawValue,
            materialBlend: simd_clamp(material.blend, 0, 1),
            baseColorOpacity: SIMD4<Float>(
                material.fields.baseColor ?? SIMD3<Float>(repeating: 0),
                material.fields.opacity ?? 0
            ),
            emissionTransmission: SIMD4<Float>(
                material.fields.emission ?? SIMD3<Float>(repeating: 0),
                material.fields.transmission ?? 0
            ),
            surface: SIMD4<Float>(
                material.fields.roughness ?? 0,
                material.fields.metallic ?? 0,
                0,
                0
            ),
            materialFieldFlags: SIMD4<UInt32>(
                material.fields.flags,
                0,
                0,
                0
            )
        )
    }

    private static func appendSparseVolumeDescriptor(
        _ volume: SparseDistanceVolume,
        material: MaterialID,
        transform: Transform,
        objectID: Int,
        primitiveID: Int,
        descriptors: inout [GPUVolumeDescriptor],
        materialCount: Int
    ) throws {
        guard Int(material.rawValue) < materialCount else {
            throw DenrimRendererError.invalidScene("Sparse distance volume references an unknown material.")
        }
        guard volume.dimensions.x >= 2, volume.dimensions.y >= 2, volume.dimensions.z >= 2 else {
            throw DenrimRendererError.invalidScene("Sparse distance volume dimensions must be at least 2x2x2.")
        }

        let boundsMin = volume.boundsMin
        let boundsMax = volume.boundsMax
        guard boundsMax.x > boundsMin.x,
              boundsMax.y > boundsMin.y,
              boundsMax.z > boundsMin.z else {
            throw DenrimRendererError.invalidScene("Sparse distance volume bounds must have positive extent.")
        }

        let worldBounds = transformedBounds(
            minimum: boundsMin,
            maximum: boundsMax,
            transform: transform
        )
        let worldToLocal = transform.matrix.inverse
        let normalTransform = transform.matrix.transpose.inverse
        descriptors.append(GPUVolumeDescriptor(
            worldBoundsMin: SIMD4<Float>(worldBounds.minimum, 0),
            worldBoundsMax: SIMD4<Float>(worldBounds.maximum, 0),
            localBoundsMin: SIMD4<Float>(boundsMin, 0),
            localBoundsMax: SIMD4<Float>(boundsMax, 0),
            dimensions: SIMD4<UInt32>(
                UInt32(volume.dimensions.x),
                UInt32(volume.dimensions.y),
                UInt32(volume.dimensions.z),
                material.rawValue
            ),
            metadata: SIMD4<UInt32>(
                0,
                UInt32(objectID),
                UInt32(primitiveID),
                1
            ),
            worldToLocal0: worldToLocal.columns.0,
            worldToLocal1: worldToLocal.columns.1,
            worldToLocal2: worldToLocal.columns.2,
            worldToLocal3: worldToLocal.columns.3,
            normalTransform0: normalTransform.columns.0,
            normalTransform1: normalTransform.columns.1,
            normalTransform2: normalTransform.columns.2,
            normalTransform3: normalTransform.columns.3
        ))
    }

    private static func validate(brick: SparseDistanceVolumeBrick, in volume: SparseDistanceVolume) throws {
        guard brick.origin.x >= 0, brick.origin.y >= 0, brick.origin.z >= 0,
              brick.dimensions.x > 0, brick.dimensions.y > 0, brick.dimensions.z > 0,
              brick.origin.x + brick.dimensions.x <= volume.dimensions.x,
              brick.origin.y + brick.dimensions.y <= volume.dimensions.y,
              brick.origin.z + brick.dimensions.z <= volume.dimensions.z else {
            throw DenrimRendererError.invalidScene("Sparse distance volume brick is outside its volume dimensions.")
        }
        guard brick.coreOrigin.x >= 0, brick.coreOrigin.y >= 0, brick.coreOrigin.z >= 0,
              brick.coreDimensions.x > 0, brick.coreDimensions.y > 0, brick.coreDimensions.z > 0,
              brick.coreOrigin.x + brick.coreDimensions.x <= volume.dimensions.x,
              brick.coreOrigin.y + brick.coreDimensions.y <= volume.dimensions.y,
              brick.coreOrigin.z + brick.coreDimensions.z <= volume.dimensions.z,
              brick.coreOrigin.x >= brick.origin.x,
              brick.coreOrigin.y >= brick.origin.y,
              brick.coreOrigin.z >= brick.origin.z,
              brick.coreOrigin.x + brick.coreDimensions.x <= brick.origin.x + brick.dimensions.x,
              brick.coreOrigin.y + brick.coreDimensions.y <= brick.origin.y + brick.dimensions.y,
              brick.coreOrigin.z + brick.coreDimensions.z <= brick.origin.z + brick.dimensions.z else {
            throw DenrimRendererError.invalidScene("Sparse distance volume brick core is outside its stored samples.")
        }

        let sampleCount = brick.dimensions.x * brick.dimensions.y * brick.dimensions.z
        guard brick.distances.count >= sampleCount,
              brick.materialSamples.count >= sampleCount else {
            throw DenrimRendererError.invalidScene("Sparse distance volume brick sample count does not match its dimensions.")
        }
    }

    private static func brickCoreLocalBounds(
        brick: SparseDistanceVolumeBrick,
        in volume: SparseDistanceVolume
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let extent = volume.boundsMax - volume.boundsMin
        let denominator = SIMD3<Float>(
            Float(max(volume.dimensions.x - 1, 1)),
            Float(max(volume.dimensions.y - 1, 1)),
            Float(max(volume.dimensions.z - 1, 1))
        )
        let minimumGrid = SIMD3<Float>(
            max(Float(brick.coreOrigin.x) - 0.5, 0),
            max(Float(brick.coreOrigin.y) - 0.5, 0),
            max(Float(brick.coreOrigin.z) - 0.5, 0)
        )
        let maximumGrid = SIMD3<Float>(
            min(Float(brick.coreOrigin.x + brick.coreDimensions.x - 1) + 0.5, denominator.x),
            min(Float(brick.coreOrigin.y + brick.coreDimensions.y - 1) + 0.5, denominator.y),
            min(Float(brick.coreOrigin.z + brick.coreDimensions.z - 1) + 0.5, denominator.z)
        )
        return (
            volume.boundsMin + extent * (minimumGrid / denominator),
            volume.boundsMin + extent * (maximumGrid / denominator)
        )
    }

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

    private static func lightRecordsAndTaggedTriangles(
        triangles: [GPUTriangle],
        materials: [GPUMaterial]
    ) -> (triangles: [GPUTriangle], lights: [GPULightRecord]) {
        guard !materials.isEmpty else {
            return (triangles, [])
        }

        let candidates = triangles.enumerated().compactMap { index, triangle -> (
            triangleIndex: UInt32,
            materialIndex: UInt32,
            area: Float,
            weight: Float,
            normal: SIMD4<Float>
        )? in
            let materialIndex = min(Int(triangle.materialID), materials.count - 1)
            let material = materials[materialIndex]
            guard max(material.emission.x, material.emission.y, material.emission.z) > 0 else {
                return nil
            }
            let area = triangleArea(triangle)
            guard area > 0 else {
                return nil
            }
            let power = luminance(material.emission.xyz) * area
            guard power > 0 else {
                return nil
            }
            return (
                UInt32(index),
                UInt32(materialIndex),
                area,
                power,
                SIMD4<Float>(triangleNormal(triangle), 0)
            )
        }

        let totalWeight = candidates.reduce(Float(0)) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return (triangles, [])
        }

        var cumulativeWeight: Float = 0
        var taggedTriangles = triangles
        let lights = candidates.enumerated().map { index, light in
            cumulativeWeight += light.weight
            let cdf = index == candidates.count - 1
                ? 1
                : min(cumulativeWeight / totalWeight, 1)
            taggedTriangles[Int(light.triangleIndex)].padding2 = UInt32(index + 1)
            return GPULightRecord(
                triangleIndex: light.triangleIndex,
                materialIndex: light.materialIndex,
                area: light.area,
                selectionCDF: cdf,
                normal: light.normal
            )
        }
        return (taggedTriangles, lights)
    }

    private static func environmentSamples(scene: RenderScene) -> [GPUEnvironmentSample] {
        guard let texture = scene.environment.texture,
              texture.width > 0,
              texture.height > 0,
              texture.pixels.count >= texture.width * texture.height else {
            return []
        }

        let width = texture.width
        let height = texture.height
        let intensity = max(scene.environment.intensity, 0)
        let maxRadiance = max(scene.environment.maxRadiance, 0)
        let deltaTheta = Float.pi / Float(height)
        let deltaPhi = 2 * Float.pi / Float(width)

        var weights: [Float] = []
        weights.reserveCapacity(width * height)
        var totalWeight: Float = 0

        for y in 0..<height {
            let theta = (Float(y) + 0.5) * deltaTheta
            let solidAngle = max(sin(theta) * deltaTheta * deltaPhi, 1e-8)
            for x in 0..<width {
                let texel = texture.pixels[y * width + x]
                var color = texel.xyz * intensity
                if maxRadiance > 0 {
                    color = simd_min(color, SIMD3<Float>(repeating: maxRadiance))
                }
                let weight = max(luminance(color), 0) * solidAngle
                weights.append(weight)
                totalWeight += weight
            }
        }

        guard totalWeight > 0 else {
            return []
        }

        var cumulative: Float = 0
        return weights.enumerated().map { index, weight in
            cumulative += weight
            let y = index / width
            let theta = (Float(y) + 0.5) * deltaTheta
            let solidAngle = max(sin(theta) * deltaTheta * deltaPhi, 1e-8)
            let probability = weight / totalWeight
            let pdfSolidAngle = probability / solidAngle
            return GPUEnvironmentSample(
                distribution: SIMD2<Float>(
                    min(cumulative / totalWeight, 1),
                    pdfSolidAngle
                )
            )
        }
    }

    private static func luminance(_ value: SIMD3<Float>) -> Float {
        simd_dot(value, SIMD3<Float>(0.2126, 0.7152, 0.0722))
    }

    private static func triangleArea(_ triangle: GPUTriangle) -> Float {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_length(simd_cross(a, b)) * 0.5
    }

    private static func triangleNormal(_ triangle: GPUTriangle) -> SIMD3<Float> {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_normalize(simd_cross(a, b))
    }

    private static func transformedBounds(
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>,
        transform: Transform
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var transformedMinimum = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var transformedMaximum = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        for x in [minimum.x, maximum.x] {
            for y in [minimum.y, maximum.y] {
                for z in [minimum.z, maximum.z] {
                    let point = transform.transformPoint(SIMD3<Float>(x, y, z))
                    transformedMinimum = simd_min(transformedMinimum, point)
                    transformedMaximum = simd_max(transformedMaximum, point)
                }
            }
        }

        return (transformedMinimum, transformedMaximum)
    }
}
