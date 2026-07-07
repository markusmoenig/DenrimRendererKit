import Foundation
import Metal
import simd

// Sparse brick packing is kept isolated so release edit builds do not recompile the full acceleration backend.
extension LinearTriangleAccelerationBackend {
    private static let volumeBrickMacroCellSize = SIMD3<Int>(repeating: 4)

    static func gpuVolumeBricks(
        scene: RenderScene,
        buildsBVH: Bool = true
    ) throws -> (
        descriptors: [GPUVolumeBrickDescriptor],
        samples: [GPUVolumeBrickSample],
        materialFieldSamples: [GPUVolumeMaterialFieldSample],
        attributeDescriptors: [GPUVolumeAttributeDescriptor],
        attributeSamples: [SIMD4<Float>],
        bvh: FlatBVH,
        grids: [GPUVolumeBrickGrid],
        gridIndices: [UInt32],
        gpuBrickBuffer: MTLBuffer?,
        gpuBrickCount: Int?,
        gpuSampleBuffer: MTLBuffer?,
        gpuSampleCount: Int?,
        gpuMaterialFieldSampleBuffer: MTLBuffer?,
        gpuMaterialFieldSampleCount: Int?,
        gpuAttributeDescriptorBuffer: MTLBuffer?,
        gpuAttributeDescriptorCount: Int?,
        gpuAttributeSampleBuffer: MTLBuffer?,
        gpuAttributeSampleCount: Int?,
        gpuGridBuffer: MTLBuffer?,
        gpuGridCount: Int?,
        gpuGridIndexBuffer: MTLBuffer?,
        gpuGridIndexCount: Int?
    ) {
        if scene.gpuSparseVolumeInstances.count > 1 {
            throw DenrimRendererError.invalidScene("Only one GPU-resident sparse distance field can be bound in this renderer version.")
        }
        if !scene.gpuSparseVolumeInstances.isEmpty && !scene.sparseVolumeInstances.isEmpty {
            throw DenrimRendererError.invalidScene("GPU-resident sparse fields cannot be mixed with CPU sparse fields yet.")
        }

        var descriptors: [GPUVolumeBrickDescriptor] = []
        var samples: [GPUVolumeBrickSample] = []
        var materialFieldSamples: [GPUVolumeMaterialFieldSample] = []
        var attributeDescriptors: [GPUVolumeAttributeDescriptor] = []
        var attributeSamples: [SIMD4<Float>] = []
        var grids: [GPUVolumeBrickGrid] = []
        var gridIndices: [UInt32] = []

        let sparseVolumeIndexBase = scene.volumeInstances.count
        let storesMaterialFields = scene.sparseVolumeInstances.contains { instance in
            instance.volume.bricks.contains { brick in
                brick.materialSamples.contains { $0.fields.flags != 0 }
            }
        }
        for (volumeIndex, instance) in scene.sparseVolumeInstances.enumerated() {
            guard Int(instance.material.rawValue) < scene.materials.count else {
                throw DenrimRendererError.invalidScene("Sparse distance volume references an unknown material.")
            }

            let volume = instance.volume
            guard volume.dimensions.x >= 2, volume.dimensions.y >= 2, volume.dimensions.z >= 2 else {
                throw DenrimRendererError.invalidScene("Sparse distance volume dimensions must be at least 2x2x2.")
            }
            guard volume.brickSize.x > 0, volume.brickSize.y > 0, volume.brickSize.z > 0 else {
                throw DenrimRendererError.invalidScene("Sparse distance volume brick size must be positive.")
            }
            let gridDimensions = SIMD3<Int>(
                (volume.dimensions.x + volume.brickSize.x - 1) / volume.brickSize.x,
                (volume.dimensions.y + volume.brickSize.y - 1) / volume.brickSize.y,
                (volume.dimensions.z + volume.brickSize.z - 1) / volume.brickSize.z
            )
            let gridIndexOffset = gridIndices.count
            let gridIndexCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
            let macroSize = Self.volumeBrickMacroCellSize
            let macroDimensions = macroGridDimensions(gridDimensions: gridDimensions, macroSize: macroSize)
            let macroIndexOffset = gridIndexOffset + gridIndexCount
            let macroIndexCount = macroDimensions.x * macroDimensions.y * macroDimensions.z
            gridIndices.append(contentsOf: repeatElement(UInt32.max, count: gridIndexCount))
            gridIndices.append(contentsOf: repeatElement(UInt32(0), count: macroIndexCount))
            grids.append(GPUVolumeBrickGrid(
                dimensionsAndIndexOffset: SIMD4<UInt32>(
                    UInt32(gridDimensions.x),
                    UInt32(gridDimensions.y),
                    UInt32(gridDimensions.z),
                    UInt32(gridIndexOffset)
                ),
                brickSizeAndVolume: SIMD4<UInt32>(
                    UInt32(volume.brickSize.x),
                    UInt32(volume.brickSize.y),
                    UInt32(volume.brickSize.z),
                    UInt32(sparseVolumeIndexBase + volumeIndex)
                ),
                macroDimensionsAndIndexOffset: SIMD4<UInt32>(
                    UInt32(macroDimensions.x),
                    UInt32(macroDimensions.y),
                    UInt32(macroDimensions.z),
                    UInt32(macroIndexOffset)
                ),
                macroSizeAndReserved: SIMD4<UInt32>(
                    UInt32(macroSize.x),
                    UInt32(macroSize.y),
                    UInt32(macroSize.z),
                    0
                )
            ))
            guard volume.boundsMax.x > volume.boundsMin.x,
                  volume.boundsMax.y > volume.boundsMin.y,
                  volume.boundsMax.z > volume.boundsMin.z else {
                throw DenrimRendererError.invalidScene("Sparse distance volume bounds must have positive extent.")
            }
            for brick in volume.bricks {
                try validate(brick: brick, in: volume)
                let sampleOffset = samples.count
                if storesMaterialFields {
                    for sampleIndex in brick.packedSamples.indices {
                        samples.append(brick.packedSamples[sampleIndex])
                        let materialSample = brick.materialSamples[sampleIndex]
                        materialFieldSamples.append(gpuVolumeMaterialFieldSample(material: materialSample))
                    }
                } else {
                    samples.append(contentsOf: brick.packedSamples)
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

                let coreBounds = brickCoreLocalBounds(brick: brick, in: volume)
                let sampleBounds = brickSampleLocalBounds(brick: brick, in: volume)
                let distanceRange = brickDistanceRange(brick)
                let worldBounds = transformedBounds(
                    minimum: coreBounds.minimum,
                    maximum: coreBounds.maximum,
                    transform: instance.transform
                )
                descriptors.append(GPUVolumeBrickDescriptor(
                    worldBoundsMin: SIMD4<Float>(worldBounds.minimum, 0),
                    worldBoundsMax: SIMD4<Float>(worldBounds.maximum, 0),
                    localBoundsMin: SIMD4<Float>(coreBounds.minimum, 0),
                    localBoundsMax: SIMD4<Float>(coreBounds.maximum, 0),
                    sampleBoundsMin: SIMD4<Float>(sampleBounds.minimum, distanceRange.minimum),
                    sampleBoundsMax: SIMD4<Float>(sampleBounds.maximum, distanceRange.maximum),
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

                let cell = SIMD3<Int>(
                    brick.coreOrigin.x / volume.brickSize.x,
                    brick.coreOrigin.y / volume.brickSize.y,
                    brick.coreOrigin.z / volume.brickSize.z
                )
                if cell.x >= 0, cell.y >= 0, cell.z >= 0,
                   cell.x < gridDimensions.x,
                   cell.y < gridDimensions.y,
                   cell.z < gridDimensions.z {
                    let gridSlot = gridIndexOffset
                        + cell.x
                        + cell.y * gridDimensions.x
                        + cell.z * gridDimensions.x * gridDimensions.y
                    gridIndices[gridSlot] = UInt32(brickIndex)
                    markMacroCellOccupied(
                        cell: cell,
                        macroSize: macroSize,
                        macroDimensions: macroDimensions,
                        macroIndexOffset: macroIndexOffset,
                        gridIndices: &gridIndices
                    )
                }
            }
        }

        let gpuSparseVolumeIndexBase = scene.volumeInstances.count + scene.sparseVolumeInstances.count
        var gpuBrickBuffer: MTLBuffer?
        var gpuBrickCount: Int?
        var gpuSampleBuffer: MTLBuffer?
        var gpuSampleCount: Int?
        var gpuMaterialFieldSampleBuffer: MTLBuffer?
        var gpuMaterialFieldSampleCount: Int?
        var gpuAttributeDescriptorBuffer: MTLBuffer?
        var gpuAttributeDescriptorCount: Int?
        var gpuAttributeSampleBuffer: MTLBuffer?
        var gpuAttributeSampleCount: Int?
        var gpuGridBuffer: MTLBuffer?
        var gpuGridCount: Int?
        var gpuGridIndexBuffer: MTLBuffer?
        var gpuGridIndexCount: Int?
        for (volumeIndex, instance) in scene.gpuSparseVolumeInstances.enumerated() {
            guard Int(instance.material.rawValue) < scene.materials.count else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field references an unknown material.")
            }
            let resource = instance.resource
            guard resource.device === resource.sampleBuffer.device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field sample buffer belongs to a different Metal device.")
            }
            gpuSampleBuffer = resource.sampleBuffer
            gpuSampleCount = resource.sampleCount
            if let materialFieldSampleBuffer = resource.materialFieldSampleBuffer {
                guard materialFieldSampleBuffer.device === resource.device else {
                    throw DenrimRendererError.invalidScene("GPU sparse distance field material-field sample buffer belongs to a different Metal device.")
                }
                gpuMaterialFieldSampleBuffer = materialFieldSampleBuffer
                gpuMaterialFieldSampleCount = resource.materialFieldSampleCount
            }
            if let attributeSampleBuffer = resource.attributeSampleBuffer {
                guard attributeSampleBuffer.device === resource.device else {
                    throw DenrimRendererError.invalidScene("GPU sparse distance field attribute sample buffer belongs to a different Metal device.")
                }
                gpuAttributeSampleBuffer = attributeSampleBuffer
                gpuAttributeSampleCount = resource.attributeSampleCount
            }
            if let metadataBuffers = resource.metadataBuffers {
                patchGPUSparseMetadataVolumeIndex(
                    metadataBuffers,
                    volumeIndex: gpuSparseVolumeIndexBase + volumeIndex
                )
                gpuBrickBuffer = metadataBuffers.brickBuffer
                gpuBrickCount = metadataBuffers.brickCount
                gpuAttributeDescriptorBuffer = metadataBuffers.attributeDescriptorBuffer
                gpuAttributeDescriptorCount = metadataBuffers.attributeDescriptorCount
                gpuGridBuffer = metadataBuffers.gridBuffer
                gpuGridCount = metadataBuffers.gridCount
                gpuGridIndexBuffer = metadataBuffers.gridIndexBuffer
                gpuGridIndexCount = metadataBuffers.gridIndexCount
            } else {
                try appendGPUSparseVolumeBricks(
                    resource: resource,
                    transform: instance.transform,
                    volumeIndex: gpuSparseVolumeIndexBase + volumeIndex,
                    descriptors: &descriptors,
                    attributeDescriptors: &attributeDescriptors,
                    grids: &grids,
                    gridIndices: &gridIndices
                )
            }
        }

        let bvh: FlatBVH
        if buildsBVH {
            let brickBounds = descriptors.map { descriptor in
                AABB(
                    minimum: descriptor.worldBoundsMin.xyz,
                    maximum: descriptor.worldBoundsMax.xyz
                )
            }
            bvh = BVHFlattener().flatten(BVHBuilder(maxLeafPrimitiveCount: 4).build(bounds: brickBounds))
        } else {
            bvh = FlatBVH(nodes: [], primitiveIndices: [])
        }

        return (
            descriptors,
            samples,
            materialFieldSamples,
            attributeDescriptors,
            attributeSamples,
            bvh,
            grids,
            gridIndices,
            gpuBrickBuffer,
            gpuBrickCount,
            gpuSampleBuffer,
            gpuSampleCount,
            gpuMaterialFieldSampleBuffer,
            gpuMaterialFieldSampleCount,
            gpuAttributeDescriptorBuffer,
            gpuAttributeDescriptorCount,
            gpuAttributeSampleBuffer,
            gpuAttributeSampleCount,
            gpuGridBuffer,
            gpuGridCount,
            gpuGridIndexBuffer,
            gpuGridIndexCount
        )
    }

    private static func patchGPUSparseMetadataVolumeIndex(
        _ metadataBuffers: RenderGPUSparseFieldMetadataBuffers,
        volumeIndex: Int
    ) {
        let volume = UInt32(volumeIndex)
        if metadataBuffers.gridCount > 0 {
            let grids = metadataBuffers.gridBuffer.contents().bindMemory(
                to: GPUVolumeBrickGrid.self,
                capacity: metadataBuffers.gridCount
            )
            for index in 0..<metadataBuffers.gridCount {
                grids[index].brickSizeAndVolume.w = volume
            }
            #if os(macOS)
            if metadataBuffers.gridBuffer.storageMode == .managed {
                metadataBuffers.gridBuffer.didModifyRange(
                    0..<(MemoryLayout<GPUVolumeBrickGrid>.stride * metadataBuffers.gridCount)
                )
            }
            #endif
        }
        if metadataBuffers.brickCount > 0 {
            let bricks = metadataBuffers.brickBuffer.contents().bindMemory(
                to: GPUVolumeBrickDescriptor.self,
                capacity: metadataBuffers.brickCount
            )
            for index in 0..<metadataBuffers.brickCount {
                bricks[index].gridOriginAndVolume.w = volume
            }
            #if os(macOS)
            if metadataBuffers.brickBuffer.storageMode == .managed {
                metadataBuffers.brickBuffer.didModifyRange(
                    0..<(MemoryLayout<GPUVolumeBrickDescriptor>.stride * metadataBuffers.brickCount)
                )
            }
            #endif
        }
    }

    private static func appendGPUSparseVolumeBricks(
        resource: RenderGPUSparseFieldResource,
        transform: Transform,
        volumeIndex: Int,
        descriptors: inout [GPUVolumeBrickDescriptor],
        attributeDescriptors: inout [GPUVolumeAttributeDescriptor],
        grids: inout [GPUVolumeBrickGrid],
        gridIndices: inout [UInt32]
    ) throws {
        guard resource.dimensions.x >= 2, resource.dimensions.y >= 2, resource.dimensions.z >= 2 else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field dimensions must be at least 2x2x2.")
        }
        guard resource.brickSize.x > 0, resource.brickSize.y > 0, resource.brickSize.z > 0 else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field brick size must be positive.")
        }
        guard resource.boundsMax.x > resource.boundsMin.x,
              resource.boundsMax.y > resource.boundsMin.y,
              resource.boundsMax.z > resource.boundsMin.z else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field bounds must have positive extent.")
        }

        let gridDimensions = SIMD3<Int>(
            (resource.dimensions.x + resource.brickSize.x - 1) / resource.brickSize.x,
            (resource.dimensions.y + resource.brickSize.y - 1) / resource.brickSize.y,
            (resource.dimensions.z + resource.brickSize.z - 1) / resource.brickSize.z
        )
        let gridIndexOffset = gridIndices.count
        let gridIndexCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
        let macroSize = Self.volumeBrickMacroCellSize
        let macroDimensions = macroGridDimensions(gridDimensions: gridDimensions, macroSize: macroSize)
        let macroIndexOffset = gridIndexOffset + gridIndexCount
        let macroIndexCount = macroDimensions.x * macroDimensions.y * macroDimensions.z
        gridIndices.append(contentsOf: repeatElement(UInt32.max, count: gridIndexCount))
        gridIndices.append(contentsOf: repeatElement(UInt32(0), count: macroIndexCount))
        grids.append(GPUVolumeBrickGrid(
            dimensionsAndIndexOffset: SIMD4<UInt32>(
                UInt32(gridDimensions.x),
                UInt32(gridDimensions.y),
                UInt32(gridDimensions.z),
                UInt32(gridIndexOffset)
            ),
            brickSizeAndVolume: SIMD4<UInt32>(
                UInt32(resource.brickSize.x),
                UInt32(resource.brickSize.y),
                UInt32(resource.brickSize.z),
                UInt32(volumeIndex)
            ),
            macroDimensionsAndIndexOffset: SIMD4<UInt32>(
                UInt32(macroDimensions.x),
                UInt32(macroDimensions.y),
                UInt32(macroDimensions.z),
                UInt32(macroIndexOffset)
            ),
            macroSizeAndReserved: SIMD4<UInt32>(
                UInt32(macroSize.x),
                UInt32(macroSize.y),
                UInt32(macroSize.z),
                0
            )
        ))

        for brick in resource.bricks {
            try validate(gpuBrick: brick, in: resource)
            let brickIndex = descriptors.count
            let coreBounds = gpuBrickCoreLocalBounds(brick: brick, resource: resource)
            let sampleBounds = gpuBrickSampleLocalBounds(brick: brick, resource: resource)
            let worldBounds = transformedBounds(
                minimum: coreBounds.minimum,
                maximum: coreBounds.maximum,
                transform: transform
            )
            descriptors.append(GPUVolumeBrickDescriptor(
                worldBoundsMin: SIMD4<Float>(worldBounds.minimum, 0),
                worldBoundsMax: SIMD4<Float>(worldBounds.maximum, 0),
                localBoundsMin: SIMD4<Float>(coreBounds.minimum, 0),
                localBoundsMax: SIMD4<Float>(coreBounds.maximum, 0),
                sampleBoundsMin: SIMD4<Float>(sampleBounds.minimum, brick.minimumDistance),
                sampleBoundsMax: SIMD4<Float>(sampleBounds.maximum, brick.maximumDistance),
                gridOriginAndVolume: SIMD4<UInt32>(
                    UInt32(brick.origin.x),
                    UInt32(brick.origin.y),
                    UInt32(brick.origin.z),
                    UInt32(volumeIndex)
                ),
                dimensionsAndSampleOffset: SIMD4<UInt32>(
                    UInt32(brick.dimensions.x),
                    UInt32(brick.dimensions.y),
                    UInt32(brick.dimensions.z),
                    UInt32(brick.sampleOffset)
                )
            ))
            attributeDescriptors.append(gpuVolumeAttributeDescriptor(
                layout: DistanceVolumeAttributeLayout(),
                sampleOffset: 0,
                sampleCount: brick.sampleCount,
                volumeOrBrickIndex: brickIndex
            ))

            let cell = SIMD3<Int>(
                brick.coreOrigin.x / resource.brickSize.x,
                brick.coreOrigin.y / resource.brickSize.y,
                brick.coreOrigin.z / resource.brickSize.z
            )
            if cell.x >= 0, cell.y >= 0, cell.z >= 0,
               cell.x < gridDimensions.x,
               cell.y < gridDimensions.y,
               cell.z < gridDimensions.z {
                let gridSlot = gridIndexOffset
                    + cell.x
                    + cell.y * gridDimensions.x
                    + cell.z * gridDimensions.x * gridDimensions.y
                gridIndices[gridSlot] = UInt32(brickIndex)
                markMacroCellOccupied(
                    cell: cell,
                    macroSize: macroSize,
                    macroDimensions: macroDimensions,
                    macroIndexOffset: macroIndexOffset,
                    gridIndices: &gridIndices
                )
            }
        }
    }

    private static func macroGridDimensions(
        gridDimensions: SIMD3<Int>,
        macroSize: SIMD3<Int>
    ) -> SIMD3<Int> {
        SIMD3<Int>(
            (gridDimensions.x + macroSize.x - 1) / macroSize.x,
            (gridDimensions.y + macroSize.y - 1) / macroSize.y,
            (gridDimensions.z + macroSize.z - 1) / macroSize.z
        )
    }

    private static func markMacroCellOccupied(
        cell: SIMD3<Int>,
        macroSize: SIMD3<Int>,
        macroDimensions: SIMD3<Int>,
        macroIndexOffset: Int,
        gridIndices: inout [UInt32]
    ) {
        let macroCell = SIMD3<Int>(
            cell.x / macroSize.x,
            cell.y / macroSize.y,
            cell.z / macroSize.z
        )
        guard macroCell.x >= 0, macroCell.y >= 0, macroCell.z >= 0,
              macroCell.x < macroDimensions.x,
              macroCell.y < macroDimensions.y,
              macroCell.z < macroDimensions.z else {
            return
        }
        let macroSlot = macroIndexOffset
            + macroCell.x
            + macroCell.y * macroDimensions.x
            + macroCell.z * macroDimensions.x * macroDimensions.y
        guard gridIndices.indices.contains(macroSlot) else {
            return
        }
        gridIndices[macroSlot] = 1
    }

    private static func brickDistanceRange(_ brick: SparseDistanceVolumeBrick) -> (minimum: Float, maximum: Float) {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        let sampleCount = brick.dimensions.x * brick.dimensions.y * brick.dimensions.z
        for distance in brick.distances.prefix(sampleCount) {
            minimum = min(minimum, distance)
            maximum = max(maximum, distance)
        }
        if minimum == Float.greatestFiniteMagnitude || maximum == -Float.greatestFiniteMagnitude {
            return (-Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        }
        return (minimum, maximum)
    }

    static func validate(brick: SparseDistanceVolumeBrick, in volume: SparseDistanceVolume) throws {
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
              brick.materialSamples.count >= sampleCount,
              brick.packedSamples.count >= sampleCount else {
            throw DenrimRendererError.invalidScene("Sparse distance volume brick sample count does not match its dimensions.")
        }
    }

    static func validate(
        gpuBrick brick: RenderGPUSparseFieldBrick,
        in resource: RenderGPUSparseFieldResource
    ) throws {
        guard brick.origin.x >= 0, brick.origin.y >= 0, brick.origin.z >= 0,
              brick.dimensions.x > 0, brick.dimensions.y > 0, brick.dimensions.z > 0,
              brick.origin.x + brick.dimensions.x <= resource.dimensions.x,
              brick.origin.y + brick.dimensions.y <= resource.dimensions.y,
              brick.origin.z + brick.dimensions.z <= resource.dimensions.z else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field brick is outside its field dimensions.")
        }
        guard brick.coreOrigin.x >= 0, brick.coreOrigin.y >= 0, brick.coreOrigin.z >= 0,
              brick.coreDimensions.x > 0, brick.coreDimensions.y > 0, brick.coreDimensions.z > 0,
              brick.coreOrigin.x + brick.coreDimensions.x <= resource.dimensions.x,
              brick.coreOrigin.y + brick.coreDimensions.y <= resource.dimensions.y,
              brick.coreOrigin.z + brick.coreDimensions.z <= resource.dimensions.z,
              brick.coreOrigin.x >= brick.origin.x,
              brick.coreOrigin.y >= brick.origin.y,
              brick.coreOrigin.z >= brick.origin.z,
              brick.coreOrigin.x + brick.coreDimensions.x <= brick.origin.x + brick.dimensions.x,
              brick.coreOrigin.y + brick.coreDimensions.y <= brick.origin.y + brick.dimensions.y,
              brick.coreOrigin.z + brick.coreDimensions.z <= brick.origin.z + brick.dimensions.z else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field brick core is outside its stored samples.")
        }
        let expectedSampleCount = brick.dimensions.x * brick.dimensions.y * brick.dimensions.z
        guard brick.sampleCount >= expectedSampleCount,
              brick.sampleOffset >= 0,
              brick.sampleOffset + expectedSampleCount <= resource.sampleCount else {
            throw DenrimRendererError.invalidScene("GPU sparse distance field brick sample range is outside the sample buffer.")
        }
    }

    static func brickCoreLocalBounds(
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

    static func gpuBrickCoreLocalBounds(
        brick: RenderGPUSparseFieldBrick,
        resource: RenderGPUSparseFieldResource
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let extent = resource.boundsMax - resource.boundsMin
        let denominator = SIMD3<Float>(
            Float(max(resource.dimensions.x - 1, 1)),
            Float(max(resource.dimensions.y - 1, 1)),
            Float(max(resource.dimensions.z - 1, 1))
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
            resource.boundsMin + extent * (minimumGrid / denominator),
            resource.boundsMin + extent * (maximumGrid / denominator)
        )
    }

    static func brickSampleLocalBounds(
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
            Float(brick.origin.x),
            Float(brick.origin.y),
            Float(brick.origin.z)
        )
        let maximumGrid = SIMD3<Float>(
            Float(brick.origin.x + brick.dimensions.x - 1),
            Float(brick.origin.y + brick.dimensions.y - 1),
            Float(brick.origin.z + brick.dimensions.z - 1)
        )
        return (
            volume.boundsMin + extent * (minimumGrid / denominator),
            volume.boundsMin + extent * (maximumGrid / denominator)
        )
    }

    static func gpuBrickSampleLocalBounds(
        brick: RenderGPUSparseFieldBrick,
        resource: RenderGPUSparseFieldResource
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let extent = resource.boundsMax - resource.boundsMin
        let denominator = SIMD3<Float>(
            Float(max(resource.dimensions.x - 1, 1)),
            Float(max(resource.dimensions.y - 1, 1)),
            Float(max(resource.dimensions.z - 1, 1))
        )
        let minimumGrid = SIMD3<Float>(
            Float(brick.origin.x),
            Float(brick.origin.y),
            Float(brick.origin.z)
        )
        let maximumGrid = SIMD3<Float>(
            Float(brick.origin.x + brick.dimensions.x - 1),
            Float(brick.origin.y + brick.dimensions.y - 1),
            Float(brick.origin.z + brick.dimensions.z - 1)
        )
        return (
            resource.boundsMin + extent * (minimumGrid / denominator),
            resource.boundsMin + extent * (maximumGrid / denominator)
        )
    }
}
