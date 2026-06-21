import Foundation
import simd

struct CPUIntersector {
    static func closestHit(
        ray: Ray,
        mesh: Mesh,
        material: MaterialID,
        transform: Transform = .identity
    ) -> SurfaceHit? {
        var closest: SurfaceHit?

        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            guard offset + 2 < mesh.indices.count else {
                break
            }
            let primitiveIndex = offset / 3
            let i0 = Int(mesh.indices[offset])
            let i1 = Int(mesh.indices[offset + 1])
            let i2 = Int(mesh.indices[offset + 2])

            guard i0 < mesh.vertices.count, i1 < mesh.vertices.count, i2 < mesh.vertices.count else {
                continue
            }

            guard let hit = intersectTriangle(
                ray: ray,
                v0: transform.transformPoint(mesh.vertices[i0]),
                v1: transform.transformPoint(mesh.vertices[i1]),
                v2: transform.transformPoint(mesh.vertices[i2]),
                material: material,
                primitiveIndex: primitiveIndex
            ) else {
                continue
            }

            if closest == nil || hit.distance < closest!.distance {
                closest = hit
            }
        }

        return closest
    }

    private static func intersectTriangle(
        ray: Ray,
        v0: SIMD3<Float>,
        v1: SIMD3<Float>,
        v2: SIMD3<Float>,
        material: MaterialID,
        primitiveIndex: Int
    ) -> SurfaceHit? {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let p = simd_cross(ray.direction, edge2)
        let determinant = simd_dot(edge1, p)

        guard abs(determinant) >= 1e-7 else {
            return nil
        }

        let inverseDeterminant = 1 / determinant
        let s = ray.origin - v0
        let u = inverseDeterminant * simd_dot(s, p)

        guard u >= 0, u <= 1 else {
            return nil
        }

        let q = simd_cross(s, edge1)
        let v = inverseDeterminant * simd_dot(ray.direction, q)

        guard v >= 0, u + v <= 1 else {
            return nil
        }

        let distance = inverseDeterminant * simd_dot(edge2, q)
        guard distance > 0.0005 else {
            return nil
        }

        var normal = simd_normalize(simd_cross(edge1, edge2))
        if simd_dot(normal, ray.direction) > 0 {
            normal = -normal
        }

        return SurfaceHit(
            distance: distance,
            position: ray.origin + distance * ray.direction,
            normal: normal,
            material: material,
            primitiveIndex: primitiveIndex
        )
    }
}
