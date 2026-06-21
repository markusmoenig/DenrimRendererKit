import Foundation
import simd

struct FlatBVH: Equatable {
    var nodes: [GPUAccelerationNode]
    var primitiveIndices: [UInt32]

    var isEmpty: Bool {
        nodes.isEmpty
    }
}

struct BVHFlattener {
    func flatten(_ bvh: BVH) -> FlatBVH {
        FlatBVH(
            nodes: bvh.nodes.map(Self.gpuNode),
            primitiveIndices: bvh.primitiveIndices.map(UInt32.init)
        )
    }

    private static func gpuNode(_ node: BVHNode) -> GPUAccelerationNode {
        GPUAccelerationNode(
            boundsMin: SIMD4<Float>(node.bounds.minimum, 0),
            boundsMax: SIMD4<Float>(node.bounds.maximum, 0),
            metadata: SIMD4<UInt32>(
                UInt32(max(0, node.leftChild)),
                UInt32(max(0, node.rightChild)),
                UInt32(max(0, node.firstPrimitive)),
                UInt32(max(0, node.primitiveCount))
            )
        )
    }
}
