import Foundation
import simd

struct GPUCamera {
    var origin: SIMD4<Float>
    var lowerLeft: SIMD4<Float>
    var horizontal: SIMD4<Float>
    var vertical: SIMD4<Float>
    var lens: SIMD4<Float>
}

struct GPUTriangle {
    var v0: SIMD4<Float>
    var v1: SIMD4<Float>
    var v2: SIMD4<Float>
    var n0: SIMD4<Float>
    var n1: SIMD4<Float>
    var n2: SIMD4<Float>
    var uv0: SIMD4<Float>
    var uv1: SIMD4<Float>
    var uv2: SIMD4<Float>
    var tangent: SIMD4<Float>
    var bitangent: SIMD4<Float>
    var materialID: UInt32
    var objectID: UInt32
    var primitiveID: UInt32
    var padding2: UInt32
}

struct GPUMaterial {
    var baseColor: SIMD4<Float>
    var emission: SIMD4<Float>
    var parameters: SIMD4<Float>
    var parameters2: SIMD4<Float>
    var specularColor: SIMD4<Float>
    var sheenColor: SIMD4<Float>
    var transmissionColor: SIMD4<Float>
    var parameters3: SIMD4<Float>
    var clearcoatColor: SIMD4<Float>
    var clearcoatAttenuation: SIMD4<Float>
    var transmissionAbsorption: SIMD4<Float>
    var thinFilm: SIMD4<Float>
    var subsurfaceColor: SIMD4<Float>
    var subsurfaceRadius: SIMD4<Float>
    var subsurfaceParameters: SIMD4<Float>
    var volumeScattering: SIMD4<Float>
    var volumeParameters: SIMD4<Float>
}

struct GPUTextureDescriptor {
    var metadata: SIMD4<UInt32>
}

struct GPULightRecord {
    var triangleIndex: UInt32
    var materialIndex: UInt32
    var area: Float
    var selectionCDF: Float
    var normal: SIMD4<Float>
}

struct GPUEnvironmentSample {
    var distribution: SIMD2<Float>
}

struct GPUVolumeDescriptor {
    var worldBoundsMin: SIMD4<Float>
    var worldBoundsMax: SIMD4<Float>
    var localBoundsMin: SIMD4<Float>
    var localBoundsMax: SIMD4<Float>
    var dimensions: SIMD4<UInt32>
    var metadata: SIMD4<UInt32>
    var materialProgram: SIMD4<UInt32>
    var worldToLocal0: SIMD4<Float>
    var worldToLocal1: SIMD4<Float>
    var worldToLocal2: SIMD4<Float>
    var worldToLocal3: SIMD4<Float>
    var normalTransform0: SIMD4<Float>
    var normalTransform1: SIMD4<Float>
    var normalTransform2: SIMD4<Float>
    var normalTransform3: SIMD4<Float>
}

struct GPUVolumeSample {
    var distance: Float
    var materialA: UInt32
    var materialB: UInt32
    var materialBlend: Float
    var baseColorOpacity: SIMD4<Float>
    var emissionTransmission: SIMD4<Float>
    var surface: SIMD4<Float>
    var materialFieldFlags: SIMD4<UInt32>
}

typealias GPUVolumeBrickSample = PackedDistanceVolumeSample

struct GPUVolumeMaterialFieldSample {
    var baseColorOpacity: SIMD4<Float>
    var emissionTransmission: SIMD4<Float>
    var surface: SIMD4<Float>
    var materialFieldFlags: SIMD4<UInt32>
}

struct GPUVolumeAttributeDescriptor {
    var metadata: SIMD4<UInt32>
    var reserved0: SIMD4<UInt32>
    var reserved1: SIMD4<UInt32>
}

struct GPUMaterialProgramDescriptor {
    var metadata: SIMD4<UInt32>
}

struct GPUMaterialProgramOperation {
    var metadata: SIMD4<UInt32>
    var data0: SIMD4<Float>
}

struct GPUVolumeBrickDescriptor {
    var worldBoundsMin: SIMD4<Float>
    var worldBoundsMax: SIMD4<Float>
    var localBoundsMin: SIMD4<Float>
    var localBoundsMax: SIMD4<Float>
    var sampleBoundsMin: SIMD4<Float>
    var sampleBoundsMax: SIMD4<Float>
    var gridOriginAndVolume: SIMD4<UInt32>
    var dimensionsAndSampleOffset: SIMD4<UInt32>
}

struct GPUVolumeBrickGrid {
    var dimensionsAndIndexOffset: SIMD4<UInt32>
    var brickSizeAndVolume: SIMD4<UInt32>
    var macroDimensionsAndIndexOffset: SIMD4<UInt32>
    var macroSizeAndReserved: SIMD4<UInt32>
}

struct GPUAccelerationNode: Equatable {
    var boundsMin: SIMD4<Float>
    var boundsMax: SIMD4<Float>
    var metadata: SIMD4<UInt32>
}

struct GPURenderConstants {
    var width: UInt32
    var height: UInt32
    var triangleCount: UInt32
    var volumeCount: UInt32
    var materialCount: UInt32
    var sampleIndex: UInt32
    var maxBounces: UInt32
    var renderQuality: UInt32
    var frameSeed: UInt32
    var accelerationNodeCount: UInt32
    var transparentBackground: UInt32
    var showsEnvironmentBackground: UInt32
    var lightCount: UInt32
    var environmentTextureIndexPlusOne: UInt32
    var environmentDistributionCount: UInt32
    var environmentIntensity: Float
    var environmentRotationY: Float
    var environmentMaxRadiance: Float
    var sampleRadianceClamp: Float
    var backgroundColor: SIMD4<Float>
    var volumeSampleCount: UInt32
    var volumeAttributeSampleCount: UInt32
    var volumeBrickCount: UInt32
    var volumeBrickSampleCount: UInt32
    var volumeBrickMaterialFieldSampleCount: UInt32
    var volumeBrickAttributeSampleCount: UInt32
    var volumeBrickBVHNodeCount: UInt32
    var volumeBrickBVHIndexCount: UInt32
    var volumeBrickGridCount: UInt32
    var volumeBrickGridIndexCount: UInt32
    var materialProgramCount: UInt32
    var materialProgramOperationCount: UInt32
    var denoiserEnabled: UInt32
    var sdfTraversalStatsEnabled: UInt32
    var tileX: UInt32
    var tileY: UInt32
    var tileWidth: UInt32
    var tileHeight: UInt32
}

struct GPURayTracingInstance {
    var metadata: SIMD4<UInt32>
    var normalTransform0: SIMD4<Float>
    var normalTransform1: SIMD4<Float>
    var normalTransform2: SIMD4<Float>
    var normalTransform3: SIMD4<Float>
}

extension SIMD4<Float> {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
