import Foundation
import Metal
import simd

struct MetalRayTracingBLASPlan {
    var triangleCount: Int
    var vertexBufferLength: Int
    var accelerationStructureSize: Int
    var buildScratchBufferSize: Int
}

struct MetalRayTracingTLASPlan {
    var instanceCount: Int
    var instanceDescriptorBufferLength: Int
    var accelerationStructureSize: Int
    var buildScratchBufferSize: Int
}

struct MetalRayTracingBLASResource {
    var meshIndex: Int
    var plan: MetalRayTracingBLASPlan
    var vertexBuffer: MTLBuffer
    var accelerationStructure: MTLAccelerationStructure
}

struct MetalRayTracingTLASResource {
    var plan: MetalRayTracingTLASPlan
    var instanceDescriptorBuffer: MTLBuffer
    var accelerationStructure: MTLAccelerationStructure
}

struct MetalRayTracingSceneBuffers {
    var localTriangleBuffer: MTLBuffer
    var instanceBuffer: MTLBuffer
    var localTriangleCount: Int
    var instanceCount: Int
}

struct MetalRayTracingExperiment {
    var supportsRayTracing: Bool
    var blasPlans: [MetalRayTracingBLASPlan]
    var tlasPlan: MetalRayTracingTLASPlan?
    var blasResources: [MetalRayTracingBLASResource]
    var tlasResource: MetalRayTracingTLASResource?
    var sceneBuffers: MetalRayTracingSceneBuffers?

    var totalAccelerationStructureSize: Int {
        blasPlans.reduce(tlasPlan?.accelerationStructureSize ?? 0) {
            $0 + $1.accelerationStructureSize
        }
    }

    var totalBuildScratchBufferSize: Int {
        blasPlans.reduce(tlasPlan?.buildScratchBufferSize ?? 0) {
            $0 + $1.buildScratchBufferSize
        }
    }
}

struct MetalRayTracingAccelerationBackend: AccelerationBackend {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue?
    var buildsFlatBVH: Bool

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue? = nil,
        buildsFlatBVH: Bool = true
    ) {
        self.device = device
        self.commandQueue = commandQueue ?? device.makeCommandQueue()
        self.buildsFlatBVH = buildsFlatBVH
    }

    var supportsRayTracing: Bool {
        device.supportsRaytracing
    }

    func build(scene: RenderScene) throws -> AccelerationBuild {
        var build = try LinearTriangleAccelerationBackend(buildsFlatBVH: buildsFlatBVH).build(scene: scene)
        build.metalRayTracingExperiment = try makeExperiment(
            instanceAcceleration: build.instanceAcceleration
        )
        return build
    }

    private func makeExperiment(
        instanceAcceleration: InstanceAcceleration
    ) throws -> MetalRayTracingExperiment {
        guard supportsRayTracing else {
            return MetalRayTracingExperiment(
                supportsRayTracing: false,
                blasPlans: [],
                tlasPlan: nil,
                blasResources: [],
                tlasResource: nil,
                sceneBuffers: nil
            )
        }

        let blasResources = try buildBLASResources(instanceAcceleration: instanceAcceleration)
        let tlasResource = try buildTLASResource(
            instanceAcceleration: instanceAcceleration,
            blasResources: blasResources
        )
        let sceneBuffers = try makeSceneBuffers(instanceAcceleration: instanceAcceleration)

        return MetalRayTracingExperiment(
            supportsRayTracing: true,
            blasPlans: blasResources.map(\.plan),
            tlasPlan: tlasResource?.plan,
            blasResources: blasResources,
            tlasResource: tlasResource,
            sceneBuffers: sceneBuffers
        )
    }

    private struct BLASBuildInput {
        var meshIndex: Int
        var plan: MetalRayTracingBLASPlan
        var descriptor: MTLPrimitiveAccelerationStructureDescriptor
        var vertexBuffer: MTLBuffer
        var accelerationStructure: MTLAccelerationStructure
        var scratchBuffer: MTLBuffer
    }

    private func buildBLASResources(
        instanceAcceleration: InstanceAcceleration
    ) throws -> [MetalRayTracingBLASResource] {
        let inputs = try instanceAcceleration.meshes.enumerated().compactMap { meshIndex, mesh in
            try makeBLASBuildInput(meshIndex: meshIndex, mesh: mesh)
        }
        guard !inputs.isEmpty else {
            return []
        }

        try encodeAccelerationStructureBuilds(inputs.map { input in
            (
                accelerationStructure: input.accelerationStructure,
                descriptor: input.descriptor,
                scratchBuffer: input.scratchBuffer
            )
        })

        return inputs.map { input in
            MetalRayTracingBLASResource(
                meshIndex: input.meshIndex,
                plan: input.plan,
                vertexBuffer: input.vertexBuffer,
                accelerationStructure: input.accelerationStructure
            )
        }
    }

    private func buildTLASResource(
        instanceAcceleration: InstanceAcceleration,
        blasResources: [MetalRayTracingBLASResource]
    ) throws -> MetalRayTracingTLASResource? {
        guard !instanceAcceleration.instances.isEmpty else {
            return nil
        }

        let blasIndexByMeshIndex = Dictionary(
            uniqueKeysWithValues: blasResources.enumerated().map { blasIndex, resource in
                (resource.meshIndex, blasIndex)
            }
        )
        let instanceDescriptors = try instanceAcceleration.instances.enumerated().map { instanceIndex, instance in
            guard let blasIndex = blasIndexByMeshIndex[instance.meshIndex] else {
                throw DenrimRendererError.invalidScene("Instance references mesh without Metal ray tracing BLAS.")
            }

            var descriptor = MTLAccelerationStructureUserIDInstanceDescriptor()
            descriptor.transformationMatrix = Self.packedFloat4x3(from: instance.transform.matrix)
            descriptor.options = .opaque
            descriptor.mask = 0xFF
            descriptor.intersectionFunctionTableOffset = 0
            descriptor.accelerationStructureIndex = UInt32(blasIndex)
            descriptor.userID = UInt32(instanceIndex)
            return descriptor
        }

        let instanceDescriptorBufferLength =
            MemoryLayout<MTLAccelerationStructureUserIDInstanceDescriptor>.stride * instanceDescriptors.count
        guard let instanceDescriptorBuffer = device.makeBuffer(
            bytes: instanceDescriptors,
            length: instanceDescriptorBufferLength,
            options: .storageModeShared
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing instance descriptor buffer.")
        }

        let descriptor = MTLInstanceAccelerationStructureDescriptor()
        descriptor.instanceDescriptorBuffer = instanceDescriptorBuffer
        descriptor.instanceDescriptorStride = MemoryLayout<MTLAccelerationStructureUserIDInstanceDescriptor>.stride
        descriptor.instanceDescriptorType = .userID
        descriptor.instanceCount = instanceDescriptors.count
        descriptor.instancedAccelerationStructures = blasResources.map(\.accelerationStructure)
        descriptor.usage = .preferFastBuild

        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let accelerationStructure = device.makeAccelerationStructure(
            size: sizes.accelerationStructureSize
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing TLAS resource.")
        }
        guard let scratchBuffer = device.makeBuffer(
            length: sizes.buildScratchBufferSize,
            options: .storageModePrivate
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing TLAS scratch buffer.")
        }

        try encodeAccelerationStructureBuilds([(
            accelerationStructure: accelerationStructure,
            descriptor: descriptor,
            scratchBuffer: scratchBuffer
        )])

        return MetalRayTracingTLASResource(
            plan: MetalRayTracingTLASPlan(
                instanceCount: instanceDescriptors.count,
                instanceDescriptorBufferLength: instanceDescriptorBufferLength,
                accelerationStructureSize: sizes.accelerationStructureSize,
                buildScratchBufferSize: sizes.buildScratchBufferSize
            ),
            instanceDescriptorBuffer: instanceDescriptorBuffer,
            accelerationStructure: accelerationStructure
        )
    }

    private func makeSceneBuffers(
        instanceAcceleration: InstanceAcceleration
    ) throws -> MetalRayTracingSceneBuffers? {
        var localTriangles: [GPUTriangle] = []
        var meshTriangleOffsets = Array(repeating: UInt32(0), count: instanceAcceleration.meshes.count)

        for (meshIndex, mesh) in instanceAcceleration.meshes.enumerated() {
            meshTriangleOffsets[meshIndex] = UInt32(localTriangles.count)
            localTriangles.append(contentsOf: mesh.localTriangles)
        }

        guard !localTriangles.isEmpty, !instanceAcceleration.instances.isEmpty else {
            return nil
        }

        var materializedTriangleOffset: UInt32 = 0
        let instances = instanceAcceleration.instances.map { instance in
            let normalTransform = instance.transform.matrix.transpose.inverse
            let instanceRecord = GPURayTracingInstance(
                metadata: SIMD4<UInt32>(
                    meshTriangleOffsets[instance.meshIndex],
                    instance.material.rawValue,
                    instance.objectID,
                    materializedTriangleOffset
                ),
                normalTransform0: normalTransform.columns.0,
                normalTransform1: normalTransform.columns.1,
                normalTransform2: normalTransform.columns.2,
                normalTransform3: normalTransform.columns.3
            )
            materializedTriangleOffset += UInt32(instanceAcceleration.meshes[instance.meshIndex].localTriangles.count)
            return instanceRecord
        }

        guard let localTriangleBuffer = device.makeBuffer(
            bytes: localTriangles,
            length: MemoryLayout<GPUTriangle>.stride * localTriangles.count,
            options: .storageModeShared
        ), let instanceBuffer = device.makeBuffer(
            bytes: instances,
            length: MemoryLayout<GPURayTracingInstance>.stride * instances.count,
            options: .storageModeShared
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing scene buffers.")
        }

        return MetalRayTracingSceneBuffers(
            localTriangleBuffer: localTriangleBuffer,
            instanceBuffer: instanceBuffer,
            localTriangleCount: localTriangles.count,
            instanceCount: instances.count
        )
    }

    private func makeBLASBuildInput(
        meshIndex: Int,
        mesh: MeshAccelerationRecord
    ) throws -> BLASBuildInput? {
        guard !mesh.localTriangles.isEmpty else {
            return nil
        }

        let vertices = mesh.localTriangles.flatMap { triangle in
            [
                triangle.v0.xyz,
                triangle.v1.xyz,
                triangle.v2.xyz
            ]
        }
        let vertexBufferLength = MemoryLayout<SIMD3<Float>>.stride * vertices.count
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertexBufferLength,
            options: .storageModeShared
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing vertex buffer.")
        }

        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertexBuffer
        geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
        geometry.vertexFormat = .float3
        geometry.triangleCount = mesh.localTriangles.count

        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        descriptor.usage = .preferFastBuild

        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let accelerationStructure = device.makeAccelerationStructure(
            size: sizes.accelerationStructureSize
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing BLAS resource.")
        }
        guard let scratchBuffer = device.makeBuffer(
            length: sizes.buildScratchBufferSize,
            options: .storageModePrivate
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing BLAS scratch buffer.")
        }

        let plan = MetalRayTracingBLASPlan(
            triangleCount: mesh.localTriangles.count,
            vertexBufferLength: vertexBufferLength,
            accelerationStructureSize: sizes.accelerationStructureSize,
            buildScratchBufferSize: sizes.buildScratchBufferSize
        )

        return BLASBuildInput(
            meshIndex: meshIndex,
            plan: plan,
            descriptor: descriptor,
            vertexBuffer: vertexBuffer,
            accelerationStructure: accelerationStructure,
            scratchBuffer: scratchBuffer
        )
    }

    private func encodeAccelerationStructureBuilds(
        _ builds: [(
            accelerationStructure: MTLAccelerationStructure,
            descriptor: MTLAccelerationStructureDescriptor,
            scratchBuffer: MTLBuffer
        )]
    ) throws {
        guard !builds.isEmpty else {
            return
        }
        guard let commandQueue else {
            throw DenrimRendererError.noMetalDevice
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create Metal ray tracing build encoder.")
        }

        for build in builds {
            encoder.build(
                accelerationStructure: build.accelerationStructure,
                descriptor: build.descriptor,
                scratchBuffer: build.scratchBuffer,
                scratchBufferOffset: 0
            )
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            let reason = commandBuffer.error?.localizedDescription ?? "Unknown Metal ray tracing build failure."
            throw DenrimRendererError.commandBufferFailed(reason)
        }
    }

    private static func packedFloat4x3(from matrix: simd_float4x4) -> MTLPackedFloat4x3 {
        MTLPackedFloat4x3(columns: (
            MTLPackedFloat3Make(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            MTLPackedFloat3Make(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            MTLPackedFloat3Make(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z),
            MTLPackedFloat3Make(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        ))
    }
}
