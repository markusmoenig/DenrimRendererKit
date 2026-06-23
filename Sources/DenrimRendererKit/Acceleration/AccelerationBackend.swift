import Foundation
import simd

struct AccelerationBuild {
    var triangles: [GPUTriangle]
    var materials: [GPUMaterial]
    var textureDescriptors: [GPUTextureDescriptor]
    var texturePixels: [SIMD4<Float>]
    var lights: [GPULightRecord]
    var bvh: FlatBVH
    var instanceAcceleration: InstanceAcceleration
    var metalRayTracingExperiment: MetalRayTracingExperiment?
}

protocol AccelerationBackend {
    func build(scene: RenderScene) throws -> AccelerationBuild
}

struct LinearTriangleAccelerationBackend: AccelerationBackend {
    var buildsFlatBVH: Bool = true

    func build(scene: RenderScene) throws -> AccelerationBuild {
        let instanceAcceleration = try InstanceAccelerationBuilder(
            buildsLocalBVH: buildsFlatBVH
        ).build(scene: scene)
        let triangles = instanceAcceleration.materializedTriangles()
        let flatBVH = buildsFlatBVH
            ? BVHFlattener().flatten(BVHBuilder().build(triangles: triangles))
            : FlatBVH(nodes: [], primitiveIndices: [])
        let materialResources = Self.gpuMaterialsAndTextures(scene: scene)

        return AccelerationBuild(
            triangles: triangles,
            materials: materialResources.materials,
            textureDescriptors: materialResources.descriptors,
            texturePixels: materialResources.pixels,
            lights: Self.lightRecords(
                triangles: triangles,
                materials: materialResources.materials
            ),
            bvh: flatBVH,
            instanceAcceleration: instanceAcceleration,
            metalRayTracingExperiment: nil
        )
    }

    private static func gpuMaterialsAndTextures(
        scene: RenderScene
    ) -> (
        materials: [GPUMaterial],
        descriptors: [GPUTextureDescriptor],
        pixels: [SIMD4<Float>]
    ) {
        var descriptors: [GPUTextureDescriptor] = []
        var pixels: [SIMD4<Float>] = []

        func append(_ texture: Texture2D?) -> Int? {
            guard let texture, texture.width > 0, texture.height > 0 else {
                return nil
            }
            let expectedPixelCount = texture.width * texture.height
            guard expectedPixelCount > 0, texture.pixels.count >= expectedPixelCount else {
                return nil
            }

            let index = descriptors.count
            descriptors.append(GPUTextureDescriptor(
                metadata: SIMD4<UInt32>(
                    UInt32(pixels.count),
                    UInt32(texture.width),
                    UInt32(texture.height),
                    texture.samplingMode.rawValue
                )
            ))
            pixels.append(contentsOf: texture.pixels.prefix(expectedPixelCount))
            return index
        }

        let materials = scene.materials.map { material in
            let baseColorTextureIndex = append(material.baseColorTexture)
            let normalMapIndex = append(material.normalMap)
            return material.gpuMaterial(
                baseColorTextureIndex: baseColorTextureIndex,
                normalMapIndex: normalMapIndex
            )
        }

        return (materials, descriptors, pixels)
    }

    private static func lightRecords(
        triangles: [GPUTriangle],
        materials: [GPUMaterial]
    ) -> [GPULightRecord] {
        guard !materials.isEmpty else {
            return []
        }

        return triangles.enumerated().compactMap { index, triangle -> GPULightRecord? in
            let materialIndex = min(Int(triangle.materialID), materials.count - 1)
            let material = materials[materialIndex]
            guard max(material.emission.x, material.emission.y, material.emission.z) > 0 else {
                return nil
            }
            let area = triangleArea(triangle)
            guard area > 0 else {
                return nil
            }
            return GPULightRecord(
                triangleIndex: UInt32(index),
                materialIndex: UInt32(materialIndex),
                area: area,
                padding: 0,
                normal: SIMD4<Float>(triangleNormal(triangle), 0)
            )
        }
    }

    private static func triangleArea(_ triangle: GPUTriangle) -> Float {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_length(simd_cross(a, b)) * 0.5
    }

    private static func triangleNormal(_ triangle: GPUTriangle) -> SIMD3<Float> {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_normalize(simd_cross(a, b))
    }
}
