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

    static func closestHit(
        ray: Ray,
        volume: DistanceVolume,
        material: MaterialID,
        transform: Transform = .identity
    ) -> SurfaceHit? {
        let worldBounds = transformedBounds(
            minimum: volume.boundsMin,
            maximum: volume.boundsMax,
            transform: transform
        )
        guard let interval = intersectBounds(
            ray: ray,
            minimum: worldBounds.minimum,
            maximum: worldBounds.maximum
        ) else {
            return nil
        }

        let worldToLocal = transform.matrix.inverse
        let localRayStep4 = worldToLocal * SIMD4<Float>(ray.direction, 0)
        let localUnitsPerWorldUnit = max(simd_length(SIMD3<Float>(
            localRayStep4.x,
            localRayStep4.y,
            localRayStep4.z
        )), 1e-6)
        let extent = simd_max(volume.boundsMax - volume.boundsMin, SIMD3<Float>(repeating: 1e-6))
        let cellSize = min(
            extent.x / Float(max(volume.dimensions.x - 1, 1)),
            min(
                extent.y / Float(max(volume.dimensions.y - 1, 1)),
                extent.z / Float(max(volume.dimensions.z - 1, 1))
            )
        )
        let minimumStep = max(cellSize * 0.10 / localUnitsPerWorldUnit, 0.0005)

        var previousDistanceAlongRay = max(interval.near, 0.0005)
        let previousPosition = ray.origin + ray.direction * previousDistanceAlongRay
        let previousLocal4 = worldToLocal * SIMD4<Float>(previousPosition, 1)
        let previousLocalPosition = SIMD3<Float>(previousLocal4.x, previousLocal4.y, previousLocal4.z)
        var previousSDF = sample(volume: volume, at: previousLocalPosition)
        var distanceAlongRay = previousDistanceAlongRay
            + max(abs(previousSDF) / localUnitsPerWorldUnit * 0.9, minimumStep)

        while distanceAlongRay <= interval.far {
            let position = ray.origin + ray.direction * distanceAlongRay
            let local4 = worldToLocal * SIMD4<Float>(position, 1)
            let localPosition = SIMD3<Float>(local4.x, local4.y, local4.z)
            let sdf = sample(volume: volume, at: localPosition)

            let crossedSurface = (previousSDF > 0 && sdf <= 0) || (previousSDF < 0 && sdf >= 0)
            if crossedSurface {
                var lowT = previousDistanceAlongRay
                var highT = distanceAlongRay
                var lowSDF = previousSDF
                for _ in 0..<10 {
                    let midT = (lowT + highT) * 0.5
                    let midPosition = ray.origin + ray.direction * midT
                    let midLocal4 = worldToLocal * SIMD4<Float>(midPosition, 1)
                    let midLocalPosition = SIMD3<Float>(midLocal4.x, midLocal4.y, midLocal4.z)
                    let midSDF = sample(volume: volume, at: midLocalPosition)
                    if (lowSDF > 0 && midSDF > 0) || (lowSDF < 0 && midSDF < 0) {
                        lowT = midT
                        lowSDF = midSDF
                    } else {
                        highT = midT
                    }
                }

                let hitDistance = (lowT + highT) * 0.5
                let hitPosition = ray.origin + ray.direction * hitDistance
                let hitLocal4 = worldToLocal * SIMD4<Float>(hitPosition, 1)
                let hitLocalPosition = SIMD3<Float>(hitLocal4.x, hitLocal4.y, hitLocal4.z)
                var normal = volumeNormal(volume: volume, at: hitLocalPosition, transform: transform)
                if simd_dot(normal, ray.direction) > 0 {
                    normal = -normal
                }
                return SurfaceHit(
                    distance: hitDistance,
                    position: hitPosition,
                    normal: normal,
                    material: material,
                    primitiveIndex: 0
                )
            }

            previousDistanceAlongRay = distanceAlongRay
            previousSDF = sdf
            distanceAlongRay += max(abs(sdf) / localUnitsPerWorldUnit * 0.8, minimumStep)
        }

        return nil
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

    private static func intersectBounds(
        ray: Ray,
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>
    ) -> (near: Float, far: Float)? {
        let inverseDirection = SIMD3<Float>(repeating: 1) / ray.direction
        let t0 = (minimum - ray.origin) * inverseDirection
        let t1 = (maximum - ray.origin) * inverseDirection
        let near3 = simd_min(t0, t1)
        let far3 = simd_max(t0, t1)
        let near = max(max(near3.x, near3.y), max(near3.z, 0))
        let far = min(far3.x, min(far3.y, far3.z))
        return near <= far ? (near, far) : nil
    }

    private static func sample(volume: DistanceVolume, at position: SIMD3<Float>) -> Float {
        let dimensions = volume.dimensions
        let extent = simd_max(volume.boundsMax - volume.boundsMin, SIMD3<Float>(repeating: 1e-6))
        let uvw = simd_clamp(
            (position - volume.boundsMin) / extent,
            SIMD3<Float>(repeating: 0),
            SIMD3<Float>(repeating: 1)
        )
        let grid = uvw * SIMD3<Float>(
            Float(dimensions.x - 1),
            Float(dimensions.y - 1),
            Float(dimensions.z - 1)
        )
        let base = SIMD3<Int>(
            Int(floor(grid.x)),
            Int(floor(grid.y)),
            Int(floor(grid.z))
        )
        let next = SIMD3<Int>(
            min(base.x + 1, dimensions.x - 1),
            min(base.y + 1, dimensions.y - 1),
            min(base.z + 1, dimensions.z - 1)
        )
        let fraction = grid - SIMD3<Float>(Float(base.x), Float(base.y), Float(base.z))

        func value(_ x: Int, _ y: Int, _ z: Int) -> Float {
            volume.distances[x + y * dimensions.x + z * dimensions.x * dimensions.y]
        }

        let c00 = mix(value(base.x, base.y, base.z), value(next.x, base.y, base.z), t: fraction.x)
        let c10 = mix(value(base.x, next.y, base.z), value(next.x, next.y, base.z), t: fraction.x)
        let c01 = mix(value(base.x, base.y, next.z), value(next.x, base.y, next.z), t: fraction.x)
        let c11 = mix(value(base.x, next.y, next.z), value(next.x, next.y, next.z), t: fraction.x)
        let c0 = mix(c00, c10, t: fraction.y)
        let c1 = mix(c01, c11, t: fraction.y)
        return mix(c0, c1, t: fraction.z)
    }

    private static func volumeNormal(
        volume: DistanceVolume,
        at position: SIMD3<Float>,
        transform: Transform
    ) -> SIMD3<Float> {
        let extent = simd_max(volume.boundsMax - volume.boundsMin, SIMD3<Float>(repeating: 1e-6))
        let spacing = extent / SIMD3<Float>(
            Float(max(volume.dimensions.x - 1, 1)),
            Float(max(volume.dimensions.y - 1, 1)),
            Float(max(volume.dimensions.z - 1, 1))
        )
        let localNormal = SIMD3<Float>(
            sample(volume: volume, at: position + SIMD3<Float>(spacing.x, 0, 0))
                - sample(volume: volume, at: position - SIMD3<Float>(spacing.x, 0, 0)),
            sample(volume: volume, at: position + SIMD3<Float>(0, spacing.y, 0))
                - sample(volume: volume, at: position - SIMD3<Float>(0, spacing.y, 0)),
            sample(volume: volume, at: position + SIMD3<Float>(0, 0, spacing.z))
                - sample(volume: volume, at: position - SIMD3<Float>(0, 0, spacing.z))
        )
        if simd_length_squared(localNormal) <= 1e-10 {
            return SIMD3<Float>(0, 1, 0)
        }
        return transform.transformNormal(simd_normalize(localNormal))
    }

    private static func transformedBounds(
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>,
        transform: Transform
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var transformedMinimum = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var transformedMaximum = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for x in [minimum.x, maximum.x] {
            for y in [minimum.y, maximum.y] {
                for z in [minimum.z, maximum.z] {
                    let point = transform.transformPoint(SIMD3<Float>(x, y, z))
                    transformedMinimum = simd_min(transformedMinimum, point)
                    transformedMaximum = simd_max(transformedMaximum, point)
                }
            }
        }
        return (transformedMinimum, transformedMaximum)
    }

    private static func mix(_ lhs: Float, _ rhs: Float, t: Float) -> Float {
        lhs + (rhs - lhs) * t
    }
}
