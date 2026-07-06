import Foundation

struct LinearTriangleAccelerationBackend: AccelerationBackend {
    var buildsFlatBVH: Bool = true
    var buildsVolumeBrickBVH: Bool = true

    func build(scene: RenderScene) throws -> AccelerationBuild {
        let instanceAcceleration = try InstanceAccelerationBuilder(
            buildsLocalBVH: buildsFlatBVH
        ).build(scene: scene)
        let materialResources = Self.gpuMaterialsAndTextures(scene: scene)
        let volumeResources = try Self.gpuVolumes(scene: scene)
        let volumeBrickResources = try Self.gpuVolumeBricks(
            scene: scene,
            buildsBVH: buildsVolumeBrickBVH
        )
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
            volumeBrickMaterialFieldSamples: volumeBrickResources.materialFieldSamples,
            volumeBrickAttributeDescriptors: volumeBrickResources.attributeDescriptors,
            volumeBrickAttributeSamples: volumeBrickResources.attributeSamples,
            volumeBrickBVH: volumeBrickResources.bvh,
            volumeBrickGrids: volumeBrickResources.grids,
            volumeBrickGridIndices: volumeBrickResources.gridIndices,
            gpuVolumeBrickBuffer: volumeBrickResources.gpuBrickBuffer,
            gpuVolumeBrickCount: volumeBrickResources.gpuBrickCount,
            gpuVolumeBrickSampleBuffer: volumeBrickResources.gpuSampleBuffer,
            gpuVolumeBrickSampleCount: volumeBrickResources.gpuSampleCount,
            gpuVolumeBrickAttributeDescriptorBuffer: volumeBrickResources.gpuAttributeDescriptorBuffer,
            gpuVolumeBrickAttributeDescriptorCount: volumeBrickResources.gpuAttributeDescriptorCount,
            gpuVolumeBrickAttributeSampleBuffer: volumeBrickResources.gpuAttributeSampleBuffer,
            gpuVolumeBrickAttributeSampleCount: volumeBrickResources.gpuAttributeSampleCount,
            gpuVolumeBrickGridBuffer: volumeBrickResources.gpuGridBuffer,
            gpuVolumeBrickGridCount: volumeBrickResources.gpuGridCount,
            gpuVolumeBrickGridIndexBuffer: volumeBrickResources.gpuGridIndexBuffer,
            gpuVolumeBrickGridIndexCount: volumeBrickResources.gpuGridIndexCount,
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
}
