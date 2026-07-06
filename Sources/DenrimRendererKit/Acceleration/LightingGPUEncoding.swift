import Foundation
import simd

extension LinearTriangleAccelerationBackend {
    static func lightRecordsAndTaggedTriangles(
        triangles: [GPUTriangle],
        materials: [GPUMaterial]
    ) -> (triangles: [GPUTriangle], lights: [GPULightRecord]) {
        guard !materials.isEmpty else {
            return (triangles, [])
        }

        let candidates = triangles.enumerated().compactMap { index, triangle -> (
            triangleIndex: UInt32,
            materialIndex: UInt32,
            area: Float,
            weight: Float,
            normal: SIMD4<Float>
        )? in
            let materialIndex = min(Int(triangle.materialID), materials.count - 1)
            let material = materials[materialIndex]
            guard max(material.emission.x, material.emission.y, material.emission.z) > 0 else {
                return nil
            }
            let area = triangleArea(triangle)
            guard area > 0 else {
                return nil
            }
            let power = luminance(material.emission.xyz) * area
            guard power > 0 else {
                return nil
            }
            return (
                UInt32(index),
                UInt32(materialIndex),
                area,
                power,
                SIMD4<Float>(triangleNormal(triangle), 0)
            )
        }

        let totalWeight = candidates.reduce(Float(0)) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return (triangles, [])
        }

        var cumulativeWeight: Float = 0
        var taggedTriangles = triangles
        let lights = candidates.enumerated().map { index, light in
            cumulativeWeight += light.weight
            let cdf = index == candidates.count - 1
                ? 1
                : min(cumulativeWeight / totalWeight, 1)
            taggedTriangles[Int(light.triangleIndex)].padding2 = UInt32(index + 1)
            return GPULightRecord(
                triangleIndex: light.triangleIndex,
                materialIndex: light.materialIndex,
                area: light.area,
                selectionCDF: cdf,
                normal: light.normal
            )
        }
        return (taggedTriangles, lights)
    }

    static func environmentSamples(scene: RenderScene) -> [GPUEnvironmentSample] {
        guard let texture = scene.environment.texture,
              texture.width > 0,
              texture.height > 0,
              texture.pixels.count >= texture.width * texture.height else {
            return []
        }

        let width = texture.width
        let height = texture.height
        let intensity = max(scene.environment.intensity, 0)
        let maxRadiance = max(scene.environment.maxRadiance, 0)
        let deltaTheta = Float.pi / Float(height)
        let deltaPhi = 2 * Float.pi / Float(width)

        var weights: [Float] = []
        weights.reserveCapacity(width * height)
        var totalWeight: Float = 0

        for y in 0..<height {
            let theta = (Float(y) + 0.5) * deltaTheta
            let solidAngle = max(sin(theta) * deltaTheta * deltaPhi, 1e-8)
            for x in 0..<width {
                let texel = texture.pixels[y * width + x]
                var color = texel.xyz * intensity
                if maxRadiance > 0 {
                    color = simd_min(color, SIMD3<Float>(repeating: maxRadiance))
                }
                let weight = max(luminance(color), 0) * solidAngle
                weights.append(weight)
                totalWeight += weight
            }
        }

        guard totalWeight > 0 else {
            return []
        }

        var cumulative: Float = 0
        return weights.enumerated().map { index, weight in
            cumulative += weight
            let y = index / width
            let theta = (Float(y) + 0.5) * deltaTheta
            let solidAngle = max(sin(theta) * deltaTheta * deltaPhi, 1e-8)
            let probability = weight / totalWeight
            let pdfSolidAngle = probability / solidAngle
            return GPUEnvironmentSample(
                distribution: SIMD2<Float>(
                    min(cumulative / totalWeight, 1),
                    pdfSolidAngle
                )
            )
        }
    }

    static func luminance(_ value: SIMD3<Float>) -> Float {
        simd_dot(value, SIMD3<Float>(0.2126, 0.7152, 0.0722))
    }

    static func triangleArea(_ triangle: GPUTriangle) -> Float {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_length(simd_cross(a, b)) * 0.5
    }

    static func triangleNormal(_ triangle: GPUTriangle) -> SIMD3<Float> {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_normalize(simd_cross(a, b))
    }
}
