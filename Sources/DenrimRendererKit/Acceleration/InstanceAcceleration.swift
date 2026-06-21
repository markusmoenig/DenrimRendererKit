import Foundation
import simd

struct MeshAccelerationRecord {
    var localTriangles: [GPUTriangle]
    var localBounds: AABB
    var localBVH: FlatBVH
}

struct SceneInstanceRecord {
    var meshIndex: Int
    var material: MaterialID
    var objectID: UInt32
    var transform: Transform
    var worldBounds: AABB
}

struct InstanceAcceleration {
    var meshes: [MeshAccelerationRecord]
    var instances: [SceneInstanceRecord]
    var topLevelBVH: FlatBVH

    func materializedTriangles() -> [GPUTriangle] {
        instances.flatMap { instance in
            meshes[instance.meshIndex].localTriangles.map { triangle in
                Self.transform(
                    triangle,
                    transform: instance.transform,
                    material: instance.material,
                    objectID: instance.objectID
                )
            }
        }
    }

    private static func transform(
        _ triangle: GPUTriangle,
        transform: Transform,
        material: MaterialID,
        objectID: UInt32
    ) -> GPUTriangle {
        let v0 = transform.transformPoint(triangle.v0.xyz)
        let v1 = transform.transformPoint(triangle.v1.xyz)
        let v2 = transform.transformPoint(triangle.v2.xyz)
        let n0 = transform.transformNormal(triangle.n0.xyz)
        let n1 = transform.transformNormal(triangle.n1.xyz)
        let n2 = transform.transformNormal(triangle.n2.xyz)
        let tangent = transform.transformNormal(triangle.tangent.xyz)
        let bitangent = transform.transformNormal(triangle.bitangent.xyz)

        return GPUTriangle(
            v0: SIMD4<Float>(v0, 0),
            v1: SIMD4<Float>(v1, 0),
            v2: SIMD4<Float>(v2, 0),
            n0: SIMD4<Float>(n0, 0),
            n1: SIMD4<Float>(n1, 0),
            n2: SIMD4<Float>(n2, 0),
            uv0: triangle.uv0,
            uv1: triangle.uv1,
            uv2: triangle.uv2,
            tangent: SIMD4<Float>(tangent, 0),
            bitangent: SIMD4<Float>(bitangent, 0),
            materialID: material.rawValue,
            objectID: objectID,
            primitiveID: triangle.primitiveID,
            padding2: 0
        )
    }
}

struct InstanceAccelerationBuilder {
    func build(scene: RenderScene) throws -> InstanceAcceleration {
        var meshes: [MeshAccelerationRecord] = []
        var instances: [SceneInstanceRecord] = []

        for (instanceIndex, instance) in scene.meshInstances.enumerated() {
            guard Int(instance.material.rawValue) < scene.materials.count else {
                throw DenrimRendererError.invalidScene("Mesh references an unknown material.")
            }

            let objectID = UInt32(instanceIndex)
            let localTriangles = instance.mesh.gpuTriangles(
                material: instance.material,
                transform: .identity,
                objectID: objectID
            )
            let localBounds = Self.bounds(for: localTriangles)
            let localBVH = BVHFlattener().flatten(BVHBuilder().build(triangles: localTriangles))
            let meshIndex = meshes.count

            meshes.append(MeshAccelerationRecord(
                localTriangles: localTriangles,
                localBounds: localBounds,
                localBVH: localBVH
            ))
            instances.append(SceneInstanceRecord(
                meshIndex: meshIndex,
                material: instance.material,
                objectID: objectID,
                transform: instance.transform,
                worldBounds: Self.transformedBounds(localBounds, transform: instance.transform)
            ))
        }

        let topLevelBVH = BVHFlattener().flatten(
            InstanceBVHBuilder().build(bounds: instances.map(\.worldBounds))
        )

        return InstanceAcceleration(
            meshes: meshes,
            instances: instances,
            topLevelBVH: topLevelBVH
        )
    }

    private static func bounds(for triangles: [GPUTriangle]) -> AABB {
        var bounds = AABB.empty
        for triangle in triangles {
            bounds.include(triangle.v0.xyz)
            bounds.include(triangle.v1.xyz)
            bounds.include(triangle.v2.xyz)
        }
        return bounds
    }

    private static func transformedBounds(_ bounds: AABB, transform: Transform) -> AABB {
        var transformed = AABB.empty
        for x in [bounds.minimum.x, bounds.maximum.x] {
            for y in [bounds.minimum.y, bounds.maximum.y] {
                for z in [bounds.minimum.z, bounds.maximum.z] {
                    transformed.include(transform.transformPoint(SIMD3<Float>(x, y, z)))
                }
            }
        }
        return transformed
    }
}

struct InstanceBVHBuilder {
    var maxLeafInstanceCount: Int = 4

    func build(bounds: [AABB]) -> BVH {
        guard !bounds.isEmpty else {
            return BVH(nodes: [], primitiveIndices: [])
        }

        var primitiveIndices = Array(bounds.indices)
        var nodes: [BVHNode] = []

        _ = buildNode(
            bounds: bounds,
            primitiveIndices: &primitiveIndices,
            range: 0..<primitiveIndices.count,
            nodes: &nodes
        )

        return BVH(nodes: nodes, primitiveIndices: primitiveIndices)
    }

    private func buildNode(
        bounds: [AABB],
        primitiveIndices: inout [Int],
        range: Range<Int>,
        nodes: inout [BVHNode]
    ) -> Int {
        let nodeIndex = nodes.count
        let nodeBounds = combinedBounds(bounds: bounds, primitiveIndices: primitiveIndices, range: range)

        nodes.append(BVHNode(
            bounds: nodeBounds,
            leftChild: -1,
            rightChild: -1,
            firstPrimitive: range.lowerBound,
            primitiveCount: range.count
        ))

        guard range.count > max(1, maxLeafInstanceCount) else {
            return nodeIndex
        }

        let centroidBounds = combinedCentroidBounds(
            bounds: bounds,
            primitiveIndices: primitiveIndices,
            range: range
        )
        let splitAxis = largestAxis(centroidBounds.extent)

        primitiveIndices[range].sort { lhs, rhs in
            bounds[lhs].centroid[splitAxis] < bounds[rhs].centroid[splitAxis]
        }

        let mid = range.lowerBound + range.count / 2
        let leftChild = buildNode(
            bounds: bounds,
            primitiveIndices: &primitiveIndices,
            range: range.lowerBound..<mid,
            nodes: &nodes
        )
        let rightChild = buildNode(
            bounds: bounds,
            primitiveIndices: &primitiveIndices,
            range: mid..<range.upperBound,
            nodes: &nodes
        )

        nodes[nodeIndex] = BVHNode(
            bounds: nodeBounds,
            leftChild: leftChild,
            rightChild: rightChild,
            firstPrimitive: -1,
            primitiveCount: 0
        )

        return nodeIndex
    }

    private func combinedBounds(
        bounds: [AABB],
        primitiveIndices: [Int],
        range: Range<Int>
    ) -> AABB {
        var combined = AABB.empty
        for index in range {
            combined.include(bounds[primitiveIndices[index]])
        }
        return combined
    }

    private func combinedCentroidBounds(
        bounds: [AABB],
        primitiveIndices: [Int],
        range: Range<Int>
    ) -> AABB {
        var combined = AABB.empty
        for index in range {
            combined.include(bounds[primitiveIndices[index]].centroid)
        }
        return combined
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
