import Foundation
import simd

struct AABB: Equatable {
    var minimum: SIMD3<Float>
    var maximum: SIMD3<Float>

    static var empty: AABB {
        AABB(
            minimum: SIMD3<Float>(repeating: Float.greatestFiniteMagnitude),
            maximum: SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        )
    }

    var centroid: SIMD3<Float> {
        (minimum + maximum) * 0.5
    }

    var extent: SIMD3<Float> {
        maximum - minimum
    }

    mutating func include(_ point: SIMD3<Float>) {
        minimum = simd_min(minimum, point)
        maximum = simd_max(maximum, point)
    }

    mutating func include(_ bounds: AABB) {
        include(bounds.minimum)
        include(bounds.maximum)
    }
}

struct BVHNode: Equatable {
    var bounds: AABB
    var leftChild: Int
    var rightChild: Int
    var firstPrimitive: Int
    var primitiveCount: Int

    var isLeaf: Bool {
        primitiveCount > 0
    }
}

struct BVH: Equatable {
    var nodes: [BVHNode]
    var primitiveIndices: [Int]

    var isEmpty: Bool {
        nodes.isEmpty
    }
}
