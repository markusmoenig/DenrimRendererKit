import Foundation
import simd

struct BVHBuilder {
    var maxLeafPrimitiveCount: Int = 4

    func build(triangles: [GPUTriangle]) -> BVH {
        guard !triangles.isEmpty else {
            return BVH(nodes: [], primitiveIndices: [])
        }

        return build(bounds: triangles.map(Self.bounds))
    }

    func build(bounds primitiveBounds: [AABB]) -> BVH {
        guard !primitiveBounds.isEmpty else {
            return BVH(nodes: [], primitiveIndices: [])
        }

        var primitiveIndices = Array(primitiveBounds.indices)
        var nodes: [BVHNode] = []

        _ = buildNode(
            primitiveBounds: primitiveBounds,
            primitiveIndices: &primitiveIndices,
            range: 0..<primitiveIndices.count,
            nodes: &nodes
        )

        return BVH(nodes: nodes, primitiveIndices: primitiveIndices)
    }

    private func buildNode(
        primitiveBounds: [AABB],
        primitiveIndices: inout [Int],
        range: Range<Int>,
        nodes: inout [BVHNode]
    ) -> Int {
        let nodeIndex = nodes.count
        let bounds = combinedBounds(
            primitiveBounds: primitiveBounds,
            primitiveIndices: primitiveIndices,
            range: range
        )

        nodes.append(BVHNode(
            bounds: bounds,
            leftChild: -1,
            rightChild: -1,
            firstPrimitive: range.lowerBound,
            primitiveCount: range.count
        ))

        guard range.count > max(1, maxLeafPrimitiveCount) else {
            return nodeIndex
        }

        let centroidBounds = combinedCentroidBounds(
            primitiveBounds: primitiveBounds,
            primitiveIndices: primitiveIndices,
            range: range
        )
        let splitAxis = largestAxis(centroidBounds.extent)

        primitiveIndices[range].sort { lhs, rhs in
            primitiveBounds[lhs].centroid[splitAxis] < primitiveBounds[rhs].centroid[splitAxis]
        }

        let mid = range.lowerBound + range.count / 2
        let leftChild = buildNode(
            primitiveBounds: primitiveBounds,
            primitiveIndices: &primitiveIndices,
            range: range.lowerBound..<mid,
            nodes: &nodes
        )
        let rightChild = buildNode(
            primitiveBounds: primitiveBounds,
            primitiveIndices: &primitiveIndices,
            range: mid..<range.upperBound,
            nodes: &nodes
        )

        nodes[nodeIndex] = BVHNode(
            bounds: bounds,
            leftChild: leftChild,
            rightChild: rightChild,
            firstPrimitive: -1,
            primitiveCount: 0
        )

        return nodeIndex
    }

    private static func bounds(for triangle: GPUTriangle) -> AABB {
        var bounds = AABB.empty
        bounds.include(triangle.v0.xyz)
        bounds.include(triangle.v1.xyz)
        bounds.include(triangle.v2.xyz)
        return bounds
    }

    private func combinedBounds(
        primitiveBounds: [AABB],
        primitiveIndices: [Int],
        range: Range<Int>
    ) -> AABB {
        var bounds = AABB.empty
        for index in range {
            bounds.include(primitiveBounds[primitiveIndices[index]])
        }
        return bounds
    }

    private func combinedCentroidBounds(
        primitiveBounds: [AABB],
        primitiveIndices: [Int],
        range: Range<Int>
    ) -> AABB {
        var bounds = AABB.empty
        for index in range {
            bounds.include(primitiveBounds[primitiveIndices[index]].centroid)
        }
        return bounds
    }

    private func largestAxis(_ extent: SIMD3<Float>) -> Int {
        if extent.x >= extent.y && extent.x >= extent.z {
            return 0
        }
        if extent.y >= extent.z {
            return 1
        }
        return 2
    }
}
