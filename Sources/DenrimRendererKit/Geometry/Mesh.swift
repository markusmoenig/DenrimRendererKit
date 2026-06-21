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

    /// Optional vertex texture coordinates.
    public var texcoords: [SIMD2<Float>]

    /// Creates a triangle mesh.
    public init(
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        normals: [SIMD3<Float>] = [],
        texcoords: [SIMD2<Float>] = []
    ) {
        self.vertices = vertices
        self.indices = indices
        self.normals = normals
        self.texcoords = texcoords
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
            indices: [0, 1, 2, 0, 2, 3],
            texcoords: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(1, 0),
                SIMD2<Float>(1, 1),
                SIMD2<Float>(0, 1)
            ]
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
            let uv0 = texcoord(at: i0)
            let uv1 = texcoord(at: i1)
            let uv2 = texcoord(at: i2)
            let localNormal = simd_normalize(simd_cross(
                vertices[i1] - vertices[i0],
                vertices[i2] - vertices[i0]
            ))
            let normal = transform.transformNormal(localNormal)
            let localTangentFrame = tangentFrame(
                p0: vertices[i0],
                p1: vertices[i1],
                p2: vertices[i2],
                uv0: uv0,
                uv1: uv1,
                uv2: uv2,
                normal: localNormal
            )
            let tangent = transform.transformNormal(localTangentFrame.tangent)
            let bitangent = transform.transformNormal(localTangentFrame.bitangent)

            return GPUTriangle(
                v0: SIMD4<Float>(v0, 0),
                v1: SIMD4<Float>(v1, 0),
                v2: SIMD4<Float>(v2, 0),
                n0: SIMD4<Float>(normal, 0),
                n1: SIMD4<Float>(normal, 0),
                n2: SIMD4<Float>(normal, 0),
                uv0: SIMD4<Float>(uv0.x, uv0.y, 0, 0),
                uv1: SIMD4<Float>(uv1.x, uv1.y, 0, 0),
                uv2: SIMD4<Float>(uv2.x, uv2.y, 0, 0),
                tangent: SIMD4<Float>(tangent, 0),
                bitangent: SIMD4<Float>(bitangent, 0),
                materialID: material.rawValue,
                objectID: objectID,
                primitiveID: UInt32(offset / 3),
                padding2: 0
            )
        }
    }

    private func texcoord(at index: Int) -> SIMD2<Float> {
        guard index < texcoords.count else {
            return SIMD2<Float>(0, 0)
        }
        return texcoords[index]
    }

    private func tangentFrame(
        p0: SIMD3<Float>,
        p1: SIMD3<Float>,
        p2: SIMD3<Float>,
        uv0: SIMD2<Float>,
        uv1: SIMD2<Float>,
        uv2: SIMD2<Float>,
        normal: SIMD3<Float>
    ) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
        let edge1 = p1 - p0
        let edge2 = p2 - p0
        let deltaUV1 = uv1 - uv0
        let deltaUV2 = uv2 - uv0
        let denominator = deltaUV1.x * deltaUV2.y - deltaUV2.x * deltaUV1.y

        guard abs(denominator) > 1e-6 else {
            let helper = abs(normal.y) < 0.999 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let tangent = simd_normalize(simd_cross(helper, normal))
            return (tangent, simd_cross(normal, tangent))
        }

        let factor = 1 / denominator
        let tangent = simd_normalize(factor * (deltaUV2.y * edge1 - deltaUV1.y * edge2))
        let bitangent = simd_normalize(factor * (-deltaUV2.x * edge1 + deltaUV1.x * edge2))
        return (tangent, bitangent)
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
