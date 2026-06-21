import Foundation
import Metal
import simd

struct MetalRayTracingTraversalProbeResult: Equatable {
    var hit: Bool
    var distance: Float
    var primitiveID: UInt32
    var instanceID: UInt32
    var geometryID: UInt32
}

private struct GPURayTracingProbeRay {
    var origin: SIMD4<Float>
    var direction: SIMD4<Float>
}

struct MetalRayTracingTraversalProbe {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipeline: MTLComputePipelineState

    init(device: MTLDevice, commandQueue: MTLCommandQueue? = nil) throws {
        guard let commandQueue = commandQueue ?? device.makeCommandQueue() else {
            throw DenrimRendererError.noMetalDevice
        }

        let library = try Self.makeLibrary(device: device)
        guard let function = library.makeFunction(name: "metalRayTracingProbeKernel") else {
            throw DenrimRendererError.missingShaderFunction("metalRayTracingProbeKernel")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    func trace(scene: RenderScene, ray: Ray) throws -> MetalRayTracingTraversalProbeResult? {
        guard device.supportsRaytracing else {
            return nil
        }

        let build = try MetalRayTracingAccelerationBackend(
            device: device,
            commandQueue: commandQueue
        ).build(scene: scene)
        guard let tlasResource = build.metalRayTracingExperiment?.tlasResource else {
            return nil
        }

        return try trace(accelerationStructure: tlasResource.accelerationStructure, ray: ray)
    }

    private func trace(
        accelerationStructure: MTLAccelerationStructure,
        ray: Ray
    ) throws -> MetalRayTracingTraversalProbeResult {
        var probeRay = GPURayTracingProbeRay(
            origin: SIMD4<Float>(ray.origin, 0),
            direction: SIMD4<Float>(ray.direction, 0)
        )
        guard let hitIDBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<UInt32>>.stride,
            options: .storageModeShared
        ), let hitDistanceBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw DenrimRendererError.invalidScene("Could not create Metal ray tracing probe buffers.")
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create Metal ray tracing probe encoder.")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setAccelerationStructure(accelerationStructure, bufferIndex: 0)
        encoder.setBytes(&probeRay, length: MemoryLayout<GPURayTracingProbeRay>.stride, index: 1)
        encoder.setBuffer(hitIDBuffer, offset: 0, index: 2)
        encoder.setBuffer(hitDistanceBuffer, offset: 0, index: 3)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let ids = hitIDBuffer.contents().assumingMemoryBound(to: SIMD4<UInt32>.self).pointee
        let distance = hitDistanceBuffer.contents().assumingMemoryBound(to: Float.self).pointee
        return MetalRayTracingTraversalProbeResult(
            hit: ids.x == 1,
            distance: distance,
            primitiveID: ids.y,
            instanceID: ids.z,
            geometryID: ids.w
        )
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        let shaderURL = Bundle.module.url(
            forResource: "MetalRayTracingProbe",
            withExtension: "metal",
            subdirectory: "Shaders"
        ) ?? Bundle.module.url(forResource: "MetalRayTracingProbe", withExtension: "metal")

        guard let shaderURL else {
            throw DenrimRendererError.missingShaderFunction("MetalRayTracingProbe.metal")
        }

        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        return try device.makeLibrary(source: source, options: nil)
    }
}
