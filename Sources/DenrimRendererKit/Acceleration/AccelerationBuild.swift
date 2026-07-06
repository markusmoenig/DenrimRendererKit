import Metal
import simd

struct AccelerationBuild {
    var triangles: [GPUTriangle]
    var volumes: [GPUVolumeDescriptor]
    var volumeSamples: [GPUVolumeSample]
    var volumeAttributeDescriptors: [GPUVolumeAttributeDescriptor]
    var volumeAttributeSamples: [SIMD4<Float>]
    var volumeBricks: [GPUVolumeBrickDescriptor]
    var volumeBrickSamples: [GPUVolumeBrickSample]
    var volumeBrickMaterialFieldSamples: [GPUVolumeMaterialFieldSample]
    var volumeBrickAttributeDescriptors: [GPUVolumeAttributeDescriptor]
    var volumeBrickAttributeSamples: [SIMD4<Float>]
    var volumeBrickBVH: FlatBVH
    var volumeBrickGrids: [GPUVolumeBrickGrid]
    var volumeBrickGridIndices: [UInt32]
    var gpuVolumeBrickBuffer: MTLBuffer?
    var gpuVolumeBrickCount: Int?
    var gpuVolumeBrickSampleBuffer: MTLBuffer?
    var gpuVolumeBrickSampleCount: Int?
    var gpuVolumeBrickAttributeDescriptorBuffer: MTLBuffer?
    var gpuVolumeBrickAttributeDescriptorCount: Int?
    var gpuVolumeBrickAttributeSampleBuffer: MTLBuffer?
    var gpuVolumeBrickAttributeSampleCount: Int?
    var gpuVolumeBrickGridBuffer: MTLBuffer?
    var gpuVolumeBrickGridCount: Int?
    var gpuVolumeBrickGridIndexBuffer: MTLBuffer?
    var gpuVolumeBrickGridIndexCount: Int?
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
