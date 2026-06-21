import Foundation
import simd

/// Triangle mesh geometry.
public struct Mesh: Sendable {
    /// Vertex positions.
    public var vertices: [SIMD3<Float>]

    /// Triangle indices. Every three indices form one triangle.
    public var indices: [UInt32]

    /// Optional vertex normals.
    public var normals: [SIMD3<Float>]

    /// Creates a triangle mesh.
    public init(
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        normals: [SIMD3<Float>] = []
    ) {
        self.vertices = vertices
        self.indices = indices
        self.normals = normals
    }

    /// Creates a two-triangle quad from four corners.
    public static func quad(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>
    ) -> Mesh {
        Mesh(
            vertices: [a, b, c, d],
            indices: [0, 1, 2, 0, 2, 3]
        )
    }

    /// Creates a box centered at the origin.
    public static func box(size: SIMD3<Float>) -> Mesh {
        let half = size * 0.5
        return box(
            minimum: SIMD3<Float>(-half.x, -half.y, -half.z),
            maximum: SIMD3<Float>(half.x, half.y, half.z)
        )
    }

    /// Creates an axis-aligned box from minimum and maximum corners.
    public static func box(
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>
    ) -> Mesh {
        let vertices = [
            SIMD3<Float>(minimum.x, minimum.y, minimum.z),
            SIMD3<Float>(maximum.x, minimum.y, minimum.z),
            SIMD3<Float>(maximum.x, maximum.y, minimum.z),
            SIMD3<Float>(minimum.x, maximum.y, minimum.z),
            SIMD3<Float>(minimum.x, minimum.y, maximum.z),
            SIMD3<Float>(maximum.x, minimum.y, maximum.z),
            SIMD3<Float>(maximum.x, maximum.y, maximum.z),
            SIMD3<Float>(minimum.x, maximum.y, maximum.z)
        ]

        let indices: [UInt32] = [
            0, 2, 1, 0, 3, 2,
            4, 5, 6, 4, 6, 7,
            0, 4, 7, 0, 7, 3,
            1, 2, 6, 1, 6, 5,
            3, 7, 6, 3, 6, 2,
            0, 1, 5, 0, 5, 4
        ]

        return Mesh(vertices: vertices, indices: indices)
    }

    func gpuTriangles(
        material: MaterialID,
        transform: Transform = .identity,
        objectID: UInt32 = 0
    ) -> [GPUTriangle] {
        stride(from: 0, to: indices.count, by: 3).map { offset in
            let i0 = Int(indices[offset])
            let i1 = Int(indices[offset + 1])
            let i2 = Int(indices[offset + 2])
            let v0 = transform.transformPoint(vertices[i0])
            let v1 = transform.transformPoint(vertices[i1])
            let v2 = transform.transformPoint(vertices[i2])
            let localNormal = simd_normalize(simd_cross(
                vertices[i1] - vertices[i0],
                vertices[i2] - vertices[i0]
            ))
            let normal = transform.transformNormal(localNormal)

            return GPUTriangle(
                v0: SIMD4<Float>(v0, 0),
                v1: SIMD4<Float>(v1, 0),
                v2: SIMD4<Float>(v2, 0),
                n0: SIMD4<Float>(normal, 0),
                n1: SIMD4<Float>(normal, 0),
                n2: SIMD4<Float>(normal, 0),
                materialID: material.rawValue,
                objectID: objectID,
                primitiveID: UInt32(offset / 3),
                padding2: 0
            )
        }
    }
}

/// A mesh plus its scene material assignment.
public struct MeshInstance: Sendable {
    /// Mesh geometry.
    public var mesh: Mesh

    /// Material used by the mesh.
    public var material: MaterialID

    /// Local-to-world instance transform.
    public var transform: Transform

    /// Creates a mesh instance.
    public init(
        mesh: Mesh,
        material: MaterialID,
        transform: Transform = .identity
    ) {
        self.mesh = mesh
        self.material = material
        self.transform = transform
    }
}
