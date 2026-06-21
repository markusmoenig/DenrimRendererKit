import Foundation
import simd

struct GPUCamera {
    var origin: SIMD4<Float>
    var lowerLeft: SIMD4<Float>
    var horizontal: SIMD4<Float>
    var vertical: SIMD4<Float>
}

struct GPUTriangle {
    var v0: SIMD4<Float>
    var v1: SIMD4<Float>
    var v2: SIMD4<Float>
    var n0: SIMD4<Float>
    var n1: SIMD4<Float>
    var n2: SIMD4<Float>
    var materialID: UInt32
    var objectID: UInt32
    var primitiveID: UInt32
    var padding2: UInt32
}

struct GPUMaterial {
    var baseColor: SIMD4<Float>
    var emission: SIMD4<Float>
    var parameters: SIMD4<Float>
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
    var materialCount: UInt32
    var sampleIndex: UInt32
    var maxBounces: UInt32
    var frameSeed: UInt32
    var accelerationNodeCount: UInt32
}

extension SIMD4<Float> {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
