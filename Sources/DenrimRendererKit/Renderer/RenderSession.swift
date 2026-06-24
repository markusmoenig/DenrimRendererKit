import Foundation
import Metal
import simd

/// Acceleration backend request for diagnostics, benchmarks, and parity testing.
///
/// Most applications should use `automatic`.
public enum RenderAccelerationMode: String, Sendable {
    /// Use the best supported backend for the current device.
    case automatic = "automatic"

    /// Force the software-built flat BVH Metal compute traversal path.
    case flatBVH = "flat-bvh"

    /// Request Metal ray tracing TLAS / BLAS traversal where available.
    case metalRayTracing = "metal-ray-tracing"
}

/// Runtime acceleration backend state for a render session.
public struct RenderAccelerationInfo: Sendable {
    /// Backend requested when the session was created.
    public var requestedMode: RenderAccelerationMode

    /// Backend actively used by the path tracing kernel.
    public var activeMode: RenderAccelerationMode

    /// Whether the current Metal device reports ray tracing support.
    public var supportsMetalRayTracing: Bool

    /// Whether a Metal ray tracing TLAS was built.
    public var hasMetalTLAS: Bool

    /// Whether flat BVH fallback buffers were built.
    public var hasFlatBVH: Bool

    /// Number of flat BVH nodes, or zero when no flat BVH was built.
    public var flatBVHNodeCount: Int
}

/// A progressive render session for one scene and settings snapshot.
public final class RenderSession {
    /// Settings used by this session.
    public let settings: RenderSettings

    /// Number of accumulated samples.
    public private(set) var sampleCount: Int = 0

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let hardwareRayTracingPipeline: MTLComputePipelineState?
    private let simpleSpatialDenoisePipeline: MTLComputePipelineState?
    private let svgfDepthNormalPipeline: MTLComputePipelineState?
    private let svgfOutputCopyPipeline: MTLComputePipelineState?
    private let camera: GPUCamera
    private let previousCamera: GPUCamera
    private let triangleBuffer: MTLBuffer
    private let materialBuffer: MTLBuffer
    private let textureDescriptorBuffer: MTLBuffer?
    private let texturePixelBuffer: MTLBuffer?
    private let lightBuffer: MTLBuffer?
    private let environmentSampleBuffer: MTLBuffer?
    private let accelerationNodeBuffer: MTLBuffer?
    private let primitiveIndexBuffer: MTLBuffer?
    private let accumulationTexture: MTLTexture
    private let denoisedBeautyTexture: MTLTexture?
    private let depthTexture: MTLTexture
    private let normalTexture: MTLTexture
    private let albedoTexture: MTLTexture
    private let materialIDTexture: MTLTexture
    private let objectIDTexture: MTLTexture
    private let motionVectorTexture: MTLTexture
    private let triangleCount: Int
    private let materialCount: Int
    private let textureDescriptorCount: Int
    private let texturePixelCount: Int
    private let environmentTextureIndexPlusOne: UInt32
    private let environmentDistributionCount: Int
    private let environmentIntensity: Float
    private let environmentRotationY: Float
    private let environmentMaxRadiance: Float
    private let lightCount: Int
    private let accelerationNodeCount: Int
    private let metalRayTracingExperiment: MetalRayTracingExperiment?
    private let accelerationMode: RenderAccelerationMode
    private let simpleSpatialDenoiser: SimpleSpatialDenoiser?
    #if canImport(MetalPerformanceShaders)
    private let appleSVGFDenoiser: AppleSVGFDenoiser?
    #endif
    private var denoisedBeautyIsCurrent = false

    var accelerationDebugInfo: (nodeCount: Int, hasNodeBuffer: Bool, hasPrimitiveIndexBuffer: Bool) {
        (
            nodeCount: accelerationNodeCount,
            hasNodeBuffer: accelerationNodeBuffer != nil,
            hasPrimitiveIndexBuffer: primitiveIndexBuffer != nil
        )
    }

    var metalRayTracingDebugInfo: (
        supportsRayTracing: Bool,
        hasTLAS: Bool,
        hasSceneBuffers: Bool,
        usesProductionHardwareTraversal: Bool
    ) {
        (
            supportsRayTracing: device.supportsRaytracing,
            hasTLAS: metalRayTracingExperiment?.tlasResource != nil,
            hasSceneBuffers: metalRayTracingExperiment?.sceneBuffers != nil,
            usesProductionHardwareTraversal: canUseHardwareRayTracing
        )
    }

    private var canUseHardwareRayTracing: Bool {
        switch accelerationMode {
        case .automatic, .metalRayTracing:
            hardwareRayTracingPipeline != nil
                && metalRayTracingExperiment?.tlasResource != nil
                && metalRayTracingExperiment?.sceneBuffers != nil
        case .flatBVH:
            false
        }
    }

    /// Runtime acceleration backend selected for this session.
    public var accelerationInfo: RenderAccelerationInfo {
        RenderAccelerationInfo(
            requestedMode: accelerationMode,
            activeMode: canUseHardwareRayTracing ? .metalRayTracing : .flatBVH,
            supportsMetalRayTracing: device.supportsRaytracing,
            hasMetalTLAS: metalRayTracingExperiment?.tlasResource != nil,
            hasFlatBVH: accelerationNodeBuffer != nil && primitiveIndexBuffer != nil,
            flatBVHNodeCount: accelerationNodeCount
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

    var denoisingDebugInfo: (
        requested: RenderDenoiser,
        hasSimpleSpatialPipeline: Bool,
        hasAppleSVGFPipelines: Bool,
        hasDenoisedBeautyTexture: Bool
    ) {
        (
            requested: settings.denoise.denoiser,
            hasSimpleSpatialPipeline: simpleSpatialDenoisePipeline != nil,
            hasAppleSVGFPipelines: svgfDepthNormalPipeline != nil && svgfOutputCopyPipeline != nil,
            hasDenoisedBeautyTexture: denoisedBeautyTexture != nil
        )
    }

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: MTLComputePipelineState,
        hardwareRayTracingPipeline: MTLComputePipelineState?,
        simpleSpatialDenoisePipeline: MTLComputePipelineState?,
        svgfDepthNormalPipeline: MTLComputePipelineState?,
        svgfOutputCopyPipeline: MTLComputePipelineState?,
        scene: RenderScene,
        settings: RenderSettings,
        accelerationMode: RenderAccelerationMode = .automatic
    ) throws {
        guard settings.width > 0, settings.height > 0 else {
            throw DenrimRendererError.invalidScene("Render dimensions must be positive.")
        }

        let canBuildHardwareAcceleration = hardwareRayTracingPipeline != nil
            && device.supportsRaytracing
            && accelerationMode != .flatBVH
        let accelerationBackend: AccelerationBackend = canBuildHardwareAcceleration
            ? MetalRayTracingAccelerationBackend(
                device: device,
                commandQueue: commandQueue,
                buildsFlatBVH: false
            )
            : LinearTriangleAccelerationBackend()
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
        self.hardwareRayTracingPipeline = hardwareRayTracingPipeline
        self.simpleSpatialDenoisePipeline = simpleSpatialDenoisePipeline
        self.svgfDepthNormalPipeline = svgfDepthNormalPipeline
        self.svgfOutputCopyPipeline = svgfOutputCopyPipeline
        self.settings = settings
        self.accelerationMode = accelerationMode
        self.camera = scene.camera.gpuCamera(width: settings.width, height: settings.height)
        self.previousCamera = (settings.previousCamera ?? scene.camera).gpuCamera(
            width: settings.width,
            height: settings.height
        )
        self.triangleCount = compiled.triangles.count
        self.materialCount = compiled.materials.count
        self.textureDescriptorCount = compiled.textureDescriptors.count
        self.texturePixelCount = compiled.texturePixels.count
        self.environmentTextureIndexPlusOne = compiled.environmentTextureIndexPlusOne
        self.environmentDistributionCount = compiled.environmentSamples.count
        self.environmentIntensity = scene.environment.intensity
        self.environmentRotationY = scene.environment.rotationY
        self.environmentMaxRadiance = scene.environment.maxRadiance
        self.lightCount = compiled.lights.count
        self.accelerationNodeCount = compiled.bvh.nodes.count
        self.metalRayTracingExperiment = compiled.metalRayTracingExperiment

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
        self.textureDescriptorBuffer = Self.makeBuffer(
            device: device,
            values: compiled.textureDescriptors
        )
        self.texturePixelBuffer = Self.makeBuffer(
            device: device,
            values: compiled.texturePixels
        )
        self.lightBuffer = Self.makeBuffer(
            device: device,
            values: compiled.lights
        )
        self.environmentSampleBuffer = Self.makeBuffer(
            device: device,
            values: compiled.environmentSamples
        )
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
        let needsDenoisedBeautyTexture = settings.denoise.denoiser != .none
        guard let accumulationTexture = device.makeTexture(descriptor: textureDescriptor),
              let depthTexture = device.makeTexture(descriptor: textureDescriptor),
              let normalTexture = device.makeTexture(descriptor: textureDescriptor),
              let albedoTexture = device.makeTexture(descriptor: textureDescriptor),
              let materialIDTexture = device.makeTexture(descriptor: textureDescriptor),
              let objectIDTexture = device.makeTexture(descriptor: textureDescriptor),
              let motionVectorTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw DenrimRendererError.invalidScene("Could not create render textures.")
        }
        let denoisedBeautyTexture = needsDenoisedBeautyTexture
            ? device.makeTexture(descriptor: textureDescriptor)
            : nil
        if needsDenoisedBeautyTexture && denoisedBeautyTexture == nil {
            throw DenrimRendererError.invalidScene("Could not create denoised beauty texture.")
        }
        self.accumulationTexture = accumulationTexture
        self.denoisedBeautyTexture = denoisedBeautyTexture
        self.depthTexture = depthTexture
        self.normalTexture = normalTexture
        self.albedoTexture = albedoTexture
        self.materialIDTexture = materialIDTexture
        self.objectIDTexture = objectIDTexture
        self.motionVectorTexture = motionVectorTexture
        switch settings.denoise.denoiser {
        case .none:
            self.simpleSpatialDenoiser = nil
            #if canImport(MetalPerformanceShaders)
            self.appleSVGFDenoiser = nil
            #endif
        case .simpleSpatial:
            guard let simpleSpatialDenoisePipeline else {
                throw DenrimRendererError.missingShaderFunction("simpleSpatialDenoiseKernel")
            }
            self.simpleSpatialDenoiser = SimpleSpatialDenoiser(pipeline: simpleSpatialDenoisePipeline)
            #if canImport(MetalPerformanceShaders)
            self.appleSVGFDenoiser = nil
            #endif
        case .appleSVGF:
            self.simpleSpatialDenoiser = nil
            #if canImport(MetalPerformanceShaders)
            guard let svgfDepthNormalPipeline, let svgfOutputCopyPipeline else {
                throw DenrimRendererError.missingShaderFunction("Apple SVGF support kernels")
            }
            self.appleSVGFDenoiser = AppleSVGFDenoiser(
                device: device,
                packDepthNormalPipeline: svgfDepthNormalPipeline,
                copyOutputPipeline: svgfOutputCopyPipeline
            )
            #else
            throw DenrimRendererError.invalidScene("Apple SVGF denoising is not available on this platform.")
            #endif
        }
    }

    /// Resets progressive accumulation to sample zero.
    public func resetAccumulation() {
        sampleCount = 0
        denoisedBeautyIsCurrent = false
        #if canImport(MetalPerformanceShaders)
        appleSVGFDenoiser?.reset()
        #endif
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
            accelerationNodeCount: UInt32(accelerationNodeCount),
            transparentBackground: settings.transparentBackground ? 1 : 0,
            lightCount: UInt32(lightCount),
            environmentTextureIndexPlusOne: environmentTextureIndexPlusOne,
            environmentDistributionCount: UInt32(environmentDistributionCount),
            environmentIntensity: environmentIntensity,
            environmentRotationY: environmentRotationY,
            environmentMaxRadiance: environmentMaxRadiance,
            sampleRadianceClamp: settings.resolvedSampleRadianceClamp,
            padding1: settings.denoise.denoiser == .none ? 0 : 1
        )
        var camera = camera
        var previousCamera = previousCamera

        let useHardwareRayTracing = canUseHardwareRayTracing
        encoder.setComputePipelineState(useHardwareRayTracing ? hardwareRayTracingPipeline! : pipeline)
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
        encoder.setBuffer(textureDescriptorBuffer, offset: 0, index: 10)
        encoder.setBuffer(texturePixelBuffer, offset: 0, index: 11)
        encoder.setBuffer(lightBuffer, offset: 0, index: 12)
        encoder.setBuffer(environmentSampleBuffer, offset: 0, index: 13)
        if useHardwareRayTracing,
           let tlasResource = metalRayTracingExperiment?.tlasResource,
           let sceneBuffers = metalRayTracingExperiment?.sceneBuffers {
            encoder.setAccelerationStructure(tlasResource.accelerationStructure, bufferIndex: 7)
            encoder.setBuffer(sceneBuffers.localTriangleBuffer, offset: 0, index: 8)
            encoder.setBuffer(sceneBuffers.instanceBuffer, offset: 0, index: 9)
            for blasResource in metalRayTracingExperiment?.blasResources ?? [] {
                encoder.useResource(blasResource.accelerationStructure, usage: .read)
            }
        }

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
        denoisedBeautyIsCurrent = false
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

    private func texture(for output: RenderOutput) throws -> MTLTexture {
        switch output {
        case .beauty:
            try ensureDenoisedBeautyIsCurrent()
            if denoisedBeautyIsCurrent, let denoisedBeautyTexture {
                return denoisedBeautyTexture
            } else {
                return accumulationTexture
            }
        case .depth:
            return depthTexture
        case .normal:
            return normalTexture
        case .albedo:
            return albedoTexture
        case .materialID:
            return materialIDTexture
        case .objectID:
            return objectIDTexture
        case .motionVector:
            return motionVectorTexture
        }
    }

    private func ensureDenoisedBeautyIsCurrent() throws {
        guard let denoisedBeautyTexture else {
            return
        }
        guard !denoisedBeautyIsCurrent else {
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw DenrimRendererError.commandBufferFailed("Could not create denoise command buffer.")
        }

        switch settings.denoise.denoiser {
        case .none:
            return
        case .simpleSpatial:
            guard let simpleSpatialDenoiser else {
                return
            }
            try simpleSpatialDenoiser.encode(
                commandBuffer: commandBuffer,
                source: accumulationTexture,
                depth: depthTexture,
                normal: normalTexture,
                albedo: albedoTexture,
                destination: denoisedBeautyTexture,
                settings: settings.denoise
            )
        case .appleSVGF:
            #if canImport(MetalPerformanceShaders)
            guard let appleSVGFDenoiser else {
                return
            }
            try appleSVGFDenoiser.encode(
                commandBuffer: commandBuffer,
                source: accumulationTexture,
                depth: depthTexture,
                normal: normalTexture,
                motionVector: motionVectorTexture,
                destination: denoisedBeautyTexture,
                settings: settings.denoise
            )
            #else
            throw DenrimRendererError.invalidScene("Apple SVGF denoising is not available on this platform.")
            #endif
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }
        denoisedBeautyIsCurrent = true
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
