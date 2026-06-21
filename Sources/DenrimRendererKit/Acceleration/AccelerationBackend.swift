import Foundation
import simd

struct AccelerationBuild {
    var triangles: [GPUTriangle]
    var materials: [GPUMaterial]
    var textureDescriptors: [GPUTextureDescriptor]
    var texturePixels: [SIMD4<Float>]
    var lightTriangleIndices: [UInt32]
    var bvh: FlatBVH
    var instanceAcceleration: InstanceAcceleration
    var metalRayTracingExperiment: MetalRayTracingExperiment?
}

protocol AccelerationBackend {
    func build(scene: RenderScene) throws -> AccelerationBuild
}

struct LinearTriangleAccelerationBackend: AccelerationBackend {
    func build(scene: RenderScene) throws -> AccelerationBuild {
        let instanceAcceleration = try InstanceAccelerationBuilder().build(scene: scene)
        let triangles = instanceAcceleration.materializedTriangles()
        let bvh = BVHBuilder().build(triangles: triangles)
        let flatBVH = BVHFlattener().flatten(bvh)
        let materialResources = Self.gpuMaterialsAndTextures(scene: scene)

        return AccelerationBuild(
            triangles: triangles,
            materials: materialResources.materials,
            textureDescriptors: materialResources.descriptors,
            texturePixels: materialResources.pixels,
            lightTriangleIndices: Self.lightTriangleIndices(
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

    private static func lightTriangleIndices(
        triangles: [GPUTriangle],
        materials: [GPUMaterial]
    ) -> [UInt32] {
        guard !materials.isEmpty else {
            return []
        }

        return triangles.enumerated().compactMap { index, triangle -> UInt32? in
            let materialIndex = min(Int(triangle.materialID), materials.count - 1)
            let material = materials[materialIndex]
            guard max(material.emission.x, material.emission.y, material.emission.z) > 0 else {
                return nil
            }
            guard triangleArea(triangle) > 0 else {
                return nil
            }
            return UInt32(index)
        }
    }

    private static func triangleArea(_ triangle: GPUTriangle) -> Float {
        let a = triangle.v1.xyz - triangle.v0.xyz
        let b = triangle.v2.xyz - triangle.v0.xyz
        return simd_length(simd_cross(a, b)) * 0.5
    }
}
