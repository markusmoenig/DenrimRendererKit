import Foundation
import Metal
import simd

/// A progressive render session for one scene and settings snapshot.
public final class RenderSession {
    /// Settings used by this session.
    public let settings: RenderSettings

    /// Number of accumulated samples.
    public private(set) var sampleCount: Int = 0

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let camera: GPUCamera
    private let previousCamera: GPUCamera
    private let triangleBuffer: MTLBuffer
    private let materialBuffer: MTLBuffer
    private let accelerationNodeBuffer: MTLBuffer?
    private let primitiveIndexBuffer: MTLBuffer?
    private let accumulationTexture: MTLTexture
    private let depthTexture: MTLTexture
    private let normalTexture: MTLTexture
    private let albedoTexture: MTLTexture
    private let materialIDTexture: MTLTexture
    private let objectIDTexture: MTLTexture
    private let motionVectorTexture: MTLTexture
    private let triangleCount: Int
    private let materialCount: Int
    private let accelerationNodeCount: Int

    var accelerationDebugInfo: (nodeCount: Int, hasNodeBuffer: Bool, hasPrimitiveIndexBuffer: Bool) {
        (
            nodeCount: accelerationNodeCount,
            hasNodeBuffer: accelerationNodeBuffer != nil,
            hasPrimitiveIndexBuffer: primitiveIndexBuffer != nil
        )
    }

    var aovDebugInfo: (
        hasDepth: Bool,
        hasNormal: Bool,
        hasAlbedo: Bool,
        hasMaterialID: Bool,
        hasObjectID: Bool,
        hasMotionVector: Bool
    ) {
        (
            hasDepth: true,
            hasNormal: true,
            hasAlbedo: true,
            hasMaterialID: true,
            hasObjectID: true,
            hasMotionVector: true
        )
    }

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: MTLComputePipelineState,
        scene: RenderScene,
        settings: RenderSettings
    ) throws {
        guard settings.width > 0, settings.height > 0 else {
            throw DenrimRendererError.invalidScene("Render dimensions must be positive.")
        }

        let accelerationBackend = LinearTriangleAccelerationBackend()
        let compiled = try accelerationBackend.build(scene: scene)
        guard !compiled.triangles.isEmpty else {
            throw DenrimRendererError.invalidScene("Scene contains no triangles.")
        }
        guard !compiled.materials.isEmpty else {
            throw DenrimRendererError.invalidScene("Scene contains no materials.")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.settings = settings
        self.camera = scene.camera.gpuCamera(width: settings.width, height: settings.height)
        self.previousCamera = (settings.previousCamera ?? scene.camera).gpuCamera(
            width: settings.width,
            height: settings.height
        )
        self.triangleCount = compiled.triangles.count
        self.materialCount = compiled.materials.count
        self.accelerationNodeCount = compiled.bvh.nodes.count

        self.triangleBuffer = device.makeBuffer(
            bytes: compiled.triangles,
            length: MemoryLayout<GPUTriangle>.stride * compiled.triangles.count,
            options: .storageModeShared
        )!
        self.materialBuffer = device.makeBuffer(
            bytes: compiled.materials,
            length: MemoryLayout<GPUMaterial>.stride * compiled.materials.count,
            options: .storageModeShared
        )!
        self.accelerationNodeBuffer = Self.makeBuffer(
            device: device,
            values: compiled.bvh.nodes
        )
        self.primitiveIndexBuffer = Self.makeBuffer(
            device: device,
            values: compiled.bvh.primitiveIndices
        )

        let textureDescriptor = MTLTextureDescriptor.denrimAccumulationTarget(
            width: settings.width,
            height: settings.height
        )
        guard let accumulationTexture = device.makeTexture(descriptor: textureDescriptor),
              let depthTexture = device.makeTexture(descriptor: textureDescriptor),
              let normalTexture = device.makeTexture(descriptor: textureDescriptor),
              let albedoTexture = device.makeTexture(descriptor: textureDescriptor),
              let materialIDTexture = device.makeTexture(descriptor: textureDescriptor),
              let objectIDTexture = device.makeTexture(descriptor: textureDescriptor),
              let motionVectorTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw DenrimRendererError.invalidScene("Could not create render textures.")
        }
        self.accumulationTexture = accumulationTexture
        self.depthTexture = depthTexture
        self.normalTexture = normalTexture
        self.albedoTexture = albedoTexture
        self.materialIDTexture = materialIDTexture
        self.objectIDTexture = objectIDTexture
        self.motionVectorTexture = motionVectorTexture
    }

    /// Resets progressive accumulation to sample zero.
    public func resetAccumulation() {
        sampleCount = 0
    }

    /// Renders one additional progressive sample.
    public func renderNextSample() throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create command encoder.")
        }

        var constants = GPURenderConstants(
            width: UInt32(settings.width),
            height: UInt32(settings.height),
            triangleCount: UInt32(triangleCount),
            materialCount: UInt32(materialCount),
            sampleIndex: UInt32(sampleCount),
            maxBounces: UInt32(max(1, settings.maxBounces)),
            frameSeed: UInt32(0x1234ABCD),
            accelerationNodeCount: UInt32(accelerationNodeCount)
        )
        var camera = camera
        var previousCamera = previousCamera

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(accumulationTexture, index: 0)
        encoder.setTexture(depthTexture, index: 1)
        encoder.setTexture(normalTexture, index: 2)
        encoder.setTexture(albedoTexture, index: 3)
        encoder.setTexture(materialIDTexture, index: 4)
        encoder.setTexture(objectIDTexture, index: 5)
        encoder.setTexture(motionVectorTexture, index: 6)
        encoder.setBytes(&constants, length: MemoryLayout<GPURenderConstants>.stride, index: 0)
        encoder.setBytes(&camera, length: MemoryLayout<GPUCamera>.stride, index: 1)
        encoder.setBuffer(triangleBuffer, offset: 0, index: 2)
        encoder.setBuffer(materialBuffer, offset: 0, index: 3)
        encoder.setBuffer(accelerationNodeBuffer, offset: 0, index: 4)
        encoder.setBuffer(primitiveIndexBuffer, offset: 0, index: 5)
        encoder.setBytes(&previousCamera, length: MemoryLayout<GPUCamera>.stride, index: 6)

        let threadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: settings.width, height: settings.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        sampleCount += 1
    }

    /// Renders a fixed number of additional samples.
    public func render(samples: Int) throws {
        guard samples >= 0 else {
            throw DenrimRendererError.invalidScene("Sample count must not be negative.")
        }
        for _ in 0..<samples {
            try renderNextSample()
        }
    }

    /// Renders samples and writes the current result as a PNG.
    public func render(samples: Int, to url: URL) throws {
        try render(samples: samples)
        try writePNG(to: url)
    }

    /// Writes the current accumulated image as a PNG.
    public func writePNG(to url: URL) throws {
        try writePNG(output: .beauty, to: url)
    }

    /// Writes a render output as a PNG.
    public func writePNG(output: RenderOutput, to url: URL) throws {
        let image = try PNGWriter.image(from: texture(for: output), output: output, device: device)
        try PNGWriter.write(image: image, to: url)
    }

    /// Reads a render output back as floating-point RGBA pixels.
    public func pixels(for output: RenderOutput) throws -> [RenderOutputPixel] {
        try TextureReadback.floatPixels(from: texture(for: output), device: device)
    }

    func debugAOVPixels() throws -> (
        depth: [RenderOutputPixel],
        normal: [RenderOutputPixel],
        albedo: [RenderOutputPixel]
    ) {
        (
            depth: try pixels(for: .depth),
            normal: try pixels(for: .normal),
            albedo: try pixels(for: .albedo)
        )
    }

    private func texture(for output: RenderOutput) -> MTLTexture {
        switch output {
        case .beauty:
            accumulationTexture
        case .depth:
            depthTexture
        case .normal:
            normalTexture
        case .albedo:
            albedoTexture
        case .materialID:
            materialIDTexture
        case .objectID:
            objectIDTexture
        case .motionVector:
            motionVectorTexture
        }
    }

    private static func makeBuffer<T>(
        device: MTLDevice,
        values: [T]
    ) -> MTLBuffer? {
        guard !values.isEmpty else {
            return nil
        }
        return values.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: .storageModeShared
            )
        }
    }
}
