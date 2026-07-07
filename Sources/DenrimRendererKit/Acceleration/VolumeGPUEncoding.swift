import Foundation
import simd

extension LinearTriangleAccelerationBackend {
    static func gpuVolumes(
        scene: RenderScene
    ) throws -> (
        descriptors: [GPUVolumeDescriptor],
        samples: [GPUVolumeSample],
        attributeDescriptors: [GPUVolumeAttributeDescriptor],
        attributeSamples: [SIMD4<Float>],
        materialPrograms: [DistanceFieldMaterialProgram]
    ) {
        var descriptors: [GPUVolumeDescriptor] = []
        var samples: [GPUVolumeSample] = []
        var attributeDescriptors: [GPUVolumeAttributeDescriptor] = []
        var attributeSamples: [SIMD4<Float>] = []
        var materialPrograms: [DistanceFieldMaterialProgram] = []

        for (index, instance) in scene.volumeInstances.enumerated() {
            try appendVolume(
                instance.volume,
                material: instance.material,
                transform: instance.transform,
                materialProgramIndex: gpuMaterialProgramIndex(for: instance.materialProgram, programs: &materialPrograms),
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
                materialProgramIndex: gpuMaterialProgramIndex(for: instance.materialProgram, programs: &materialPrograms),
                objectID: sparseObjectIDBase + index,
                primitiveID: sparsePrimitiveIDBase + index,
                descriptors: &descriptors,
                materialCount: scene.materials.count
            )
        }

        let gpuSparseObjectIDBase = sparseObjectIDBase + scene.sparseVolumeInstances.count
        let gpuSparsePrimitiveIDBase = sparsePrimitiveIDBase + scene.sparseVolumeInstances.count
        for (index, instance) in scene.gpuSparseVolumeInstances.enumerated() {
            try appendGPUSparseVolumeDescriptor(
                instance.resource,
                material: instance.material,
                transform: instance.transform,
                materialProgramIndex: gpuMaterialProgramIndex(for: instance.materialProgram, programs: &materialPrograms),
                objectID: gpuSparseObjectIDBase + index,
                primitiveID: gpuSparsePrimitiveIDBase + index,
                descriptors: &descriptors,
                materialCount: scene.materials.count
            )
        }

        return (descriptors, samples, attributeDescriptors, attributeSamples, materialPrograms)
    }

    private static func gpuMaterialProgramIndex(
        for program: DistanceFieldMaterialProgram?,
        programs: inout [DistanceFieldMaterialProgram]
    ) -> UInt32 {
        guard let program else {
            return UInt32.max
        }
        if let existing = programs.firstIndex(of: program) {
            return UInt32(existing)
        }
        programs.append(program)
        return UInt32(programs.count - 1)
    }

    static func appendVolume(
        _ volume: DistanceVolume,
        material: MaterialID,
        transform: Transform,
        materialProgramIndex: UInt32,
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
            materialProgram: SIMD4<UInt32>(materialProgramIndex, 0, 0, 0),
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

    static func appendSparseVolumeDescriptor(
        _ volume: SparseDistanceVolume,
        material: MaterialID,
        transform: Transform,
        materialProgramIndex: UInt32,
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
            materialProgram: SIMD4<UInt32>(materialProgramIndex, 0, 0, 0),
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

    static func appendGPUSparseVolumeDescriptor(
        _ resource: RenderGPUSparseFieldResource,
        material: MaterialID,
        transform: Transform,
        materialProgramIndex: UInt32,
        objectID: Int,
        primitiveID: Int,
        descriptors: inout [GPUVolumeDescriptor],
        materialCount: Int
    ) throws {
        guard Int(material.rawValue) < materialCount else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field references an unknown material.")
        }
        guard resource.dimensions.x >= 2, resource.dimensions.y >= 2, resource.dimensions.z >= 2 else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field dimensions must be at least 2x2x2.")
        }

        let boundsMin = resource.boundsMin
        let boundsMax = resource.boundsMax
        guard boundsMax.x > boundsMin.x,
              boundsMax.y > boundsMin.y,
              boundsMax.z > boundsMin.z else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field bounds must have positive extent.")
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
                UInt32(resource.dimensions.x),
                UInt32(resource.dimensions.y),
                UInt32(resource.dimensions.z),
                material.rawValue
            ),
            metadata: SIMD4<UInt32>(
                0,
                UInt32(objectID),
                UInt32(primitiveID),
                1
            ),
            materialProgram: SIMD4<UInt32>(materialProgramIndex, 0, 0, 0),
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

    static func gpuVolumeAttributeDescriptor(
        layout: DistanceVolumeAttributeLayout,
        sampleOffset: Int,
        sampleCount: Int,
        volumeOrBrickIndex: Int
    ) -> GPUVolumeAttributeDescriptor {
        return GPUVolumeAttributeDescriptor(
            metadata: SIMD4<UInt32>(
                UInt32(sampleOffset),
                UInt32(layout.packedVectorCount),
                UInt32(sampleCount),
                UInt32(volumeOrBrickIndex)
            ),
            reserved0: SIMD4<UInt32>(repeating: 0),
            reserved1: SIMD4<UInt32>(repeating: 0)
        )
    }

    static func gpuVolumeSample(
        distance: Float,
        material: DistanceVolumeMaterialSample
    ) -> GPUVolumeSample {
        let fields = gpuVolumeMaterialFieldSample(material: material)
        return GPUVolumeSample(
            distance: distance,
            materialA: material.materialA.rawValue,
            materialB: material.materialB.rawValue,
            materialBlend: simd_clamp(material.blend, 0, 1),
            baseColorOpacity: fields.baseColorOpacity,
            emissionTransmission: fields.emissionTransmission,
            surface: fields.surface,
            materialFieldFlags: fields.materialFieldFlags
        )
    }

    static func gpuVolumeMaterialFieldSample(
        material: DistanceVolumeMaterialSample
    ) -> GPUVolumeMaterialFieldSample {
        GPUVolumeMaterialFieldSample(
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
                material.fields.specular ?? 0,
                material.fields.emissionStrength ?? 0
            ),
            materialFieldFlags: SIMD4<UInt32>(
                material.fields.flags,
                0,
                0,
                0
            )
        )
    }

    static func transformedBounds(
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
