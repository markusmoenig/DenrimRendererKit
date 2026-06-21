import Foundation

struct AccelerationBuild {
    var triangles: [GPUTriangle]
    var materials: [GPUMaterial]
    var bvh: FlatBVH
    var instanceAcceleration: InstanceAcceleration
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

        return AccelerationBuild(
            triangles: triangles,
            materials: scene.materials.map(\.gpuMaterial),
            bvh: flatBVH,
            instanceAcceleration: instanceAcceleration
        )
    }
}
