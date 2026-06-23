import Foundation
import Metal
#if canImport(MetalPerformanceShaders)
import MetalPerformanceShaders
#endif

/// Built-in denoiser backend used for beauty output.
public enum RenderDenoiser: Sendable, Equatable {
    /// Do not denoise the accumulated beauty output.
    case none

    /// Experimental GPU bilateral filter guided by beauty, depth, normal, and albedo outputs.
    case simpleSpatial

    /// Apple Metal Performance Shaders SVGF denoiser.
    case appleSVGF

}

/// User-facing denoising controls.
public struct DenoiseSettings: Sendable, Equatable {
    /// Selected denoiser backend.
    public var denoiser: RenderDenoiser

    /// Filter radius in pixels. Larger values smooth more aggressively.
    public var radius: Int

    /// How strongly normal changes preserve geometric edges.
    public var normalSigma: Float

    /// How strongly depth changes preserve geometric edges.
    public var depthSigma: Float

    /// How strongly albedo changes preserve material edges.
    public var albedoSigma: Float

    /// How strongly beauty color differences preserve high-frequency detail.
    public var colorSigma: Float

    /// Number of à-trous filter passes. More passes smooth larger low-frequency noise.
    public var iterations: Int

    /// Creates denoising settings.
    public init(
        denoiser: RenderDenoiser = .none,
        radius: Int = 2,
        normalSigma: Float = 0.18,
        depthSigma: Float = 0.03,
        albedoSigma: Float = 0.25,
        colorSigma: Float = 1.0,
        iterations: Int = 3
    ) {
        self.denoiser = denoiser
        self.radius = radius
        self.normalSigma = normalSigma
        self.depthSigma = depthSigma
        self.albedoSigma = albedoSigma
        self.colorSigma = colorSigma
        self.iterations = iterations
    }

    /// No denoising.
    public static let none = DenoiseSettings()

    /// Experimental spatial denoising for low-sample preview output.
    public static let simpleSpatial = DenoiseSettings(denoiser: .simpleSpatial)

    /// Apple Metal Performance Shaders SVGF denoising.
    public static let appleSVGF = DenoiseSettings(
        denoiser: .appleSVGF,
        radius: 2,
        normalSigma: 0.18,
        depthSigma: 0.08,
        albedoSigma: 0.25,
        colorSigma: 4.0,
        iterations: 5
    )

}

struct GPUDenoiseConstants {
    var width: UInt32
    var height: UInt32
    var radius: UInt32
    var padding: UInt32
    var normalSigma: Float
    var depthSigma: Float
    var albedoSigma: Float
    var colorSigma: Float
    var stepWidth: UInt32
    var padding2: UInt32
    var padding3: UInt32
    var padding4: UInt32
}

final class SimpleSpatialDenoiser {
    private let pipeline: MTLComputePipelineState

    init(pipeline: MTLComputePipelineState) {
        self.pipeline = pipeline
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        depth: MTLTexture,
        normal: MTLTexture,
        albedo: MTLTexture,
        destination: MTLTexture,
        settings: DenoiseSettings
    ) throws {
        let iterations = max(1, min(settings.iterations, 5))
        let descriptor = MTLTextureDescriptor.denrimFloatTarget(
            width: source.width,
            height: source.height
        )
        guard let temporaryA = source.device.makeTexture(descriptor: descriptor),
              let temporaryB = source.device.makeTexture(descriptor: descriptor) else {
            throw DenrimRendererError.commandBufferFailed("Could not create denoise temporary texture.")
        }

        var currentSource = source
        for iteration in 0..<iterations {
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw DenrimRendererError.commandBufferFailed("Could not create denoise command encoder.")
            }

            let currentDestination: MTLTexture
            if iteration == iterations - 1 {
                currentDestination = destination
            } else {
                currentDestination = iteration.isMultiple(of: 2) ? temporaryA : temporaryB
            }
            var constants = GPUDenoiseConstants(
                width: UInt32(source.width),
                height: UInt32(source.height),
                radius: UInt32(max(1, min(settings.radius, 2))),
                padding: 0,
                normalSigma: max(settings.normalSigma, 0.0001),
                depthSigma: max(settings.depthSigma, 0.0001),
                albedoSigma: max(settings.albedoSigma, 0.0001),
                colorSigma: max(settings.colorSigma, 0.0001),
                stepWidth: UInt32(1 << iteration),
                padding2: 0,
                padding3: 0,
                padding4: 0
            )

            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(currentSource, index: 0)
            encoder.setTexture(depth, index: 1)
            encoder.setTexture(normal, index: 2)
            encoder.setTexture(albedo, index: 3)
            encoder.setTexture(currentDestination, index: 4)
            encoder.setBytes(&constants, length: MemoryLayout<GPUDenoiseConstants>.stride, index: 0)

            let threadgroup = MTLSize(width: 8, height: 8, depth: 1)
            let grid = MTLSize(width: source.width, height: source.height, depth: 1)
            encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
            encoder.endEncoding()
            currentSource = currentDestination
        }
    }
}

#if canImport(MetalPerformanceShaders)
final class AppleSVGFDenoiser {
    private let device: MTLDevice
    private let packDepthNormalPipeline: MTLComputePipelineState
    private let copyOutputPipeline: MTLComputePipelineState
    private let denoiser: MPSSVGFDenoiser
    private var depthNormalTextures: [MTLTexture] = []
    private var nextDepthNormalTextureIndex = 0
    private var previousDepthNormalTexture: MTLTexture?

    init(
        device: MTLDevice,
        packDepthNormalPipeline: MTLComputePipelineState,
        copyOutputPipeline: MTLComputePipelineState
    ) {
        self.device = device
        self.packDepthNormalPipeline = packDepthNormalPipeline
        self.copyOutputPipeline = copyOutputPipeline
        self.denoiser = MPSSVGFDenoiser(device: device)
        self.denoiser.svgf.channelCount = 3
        self.denoiser.svgf.temporalWeighting = .exponentialMovingAverage
        self.denoiser.svgf.temporalReprojectionBlendFactor = 0.2
    }

    func reset() {
        denoiser.clearTemporalHistory()
        previousDepthNormalTexture = nil
        nextDepthNormalTextureIndex = 0
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        depth: MTLTexture,
        normal: MTLTexture,
        motionVector: MTLTexture,
        destination: MTLTexture,
        settings: DenoiseSettings
    ) throws {
        try ensureDepthNormalTextures(width: source.width, height: source.height)
        let depthNormalTexture = depthNormalTextures[nextDepthNormalTextureIndex]
        nextDepthNormalTextureIndex = (nextDepthNormalTextureIndex + 1) % depthNormalTextures.count

        try encodeDepthNormalPack(
            commandBuffer: commandBuffer,
            depth: depth,
            normal: normal,
            destination: depthNormalTexture
        )

        configure(settings: settings)
        let reprojectMotionVector = previousDepthNormalTexture == nil ? nil : motionVector
        let output = denoiser.encode(
            commandBuffer: commandBuffer,
            sourceTexture: source,
            motionVectorTexture: reprojectMotionVector,
            depthNormalTexture: depthNormalTexture,
            previousDepthNormalTexture: previousDepthNormalTexture
        )

        try encodeOutputCopy(
            commandBuffer: commandBuffer,
            source: output,
            alphaSource: source,
            destination: destination
        )
        previousDepthNormalTexture = depthNormalTexture
    }

    private func configure(settings: DenoiseSettings) {
        denoiser.bilateralFilterIterations = max(1, min(settings.iterations, 5))
        denoiser.svgf.bilateralFilterRadius = max(1, min(settings.radius, 4))
        denoiser.svgf.varianceEstimationRadius = max(1, min(settings.radius, 4))
        denoiser.svgf.depthWeight = max(settings.depthSigma, 0.0001)
        denoiser.svgf.normalWeight = max(1, min(512, 1 / max(settings.normalSigma, 0.0001) * 24))
        denoiser.svgf.luminanceWeight = max(settings.colorSigma, 0.0001)
        denoiser.svgf.bilateralFilterSigma = 1.2
        denoiser.svgf.varianceEstimationSigma = 2.0
        denoiser.svgf.variancePrefilterSigma = 1.33
    }

    private func ensureDepthNormalTextures(width: Int, height: Int) throws {
        if depthNormalTextures.count == 2,
           depthNormalTextures.allSatisfy({ $0.width == width && $0.height == height }) {
            return
        }

        let descriptor = MTLTextureDescriptor.denrimFloatTarget(width: width, height: height)
        guard let first = device.makeTexture(descriptor: descriptor),
              let second = device.makeTexture(descriptor: descriptor) else {
            throw DenrimRendererError.commandBufferFailed("Could not create Apple SVGF depth-normal textures.")
        }
        depthNormalTextures = [first, second]
        reset()
    }

    private func encodeDepthNormalPack(
        commandBuffer: MTLCommandBuffer,
        depth: MTLTexture,
        normal: MTLTexture,
        destination: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create Apple SVGF pack command encoder.")
        }
        encoder.setComputePipelineState(packDepthNormalPipeline)
        encoder.setTexture(depth, index: 0)
        encoder.setTexture(normal, index: 1)
        encoder.setTexture(destination, index: 2)
        let threadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: destination.width, height: destination.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()
    }

    private func encodeOutputCopy(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        alphaSource: MTLTexture,
        destination: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create Apple SVGF output command encoder.")
        }
        encoder.setComputePipelineState(copyOutputPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(alphaSource, index: 1)
        encoder.setTexture(destination, index: 2)
        let threadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: destination.width, height: destination.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()
    }
}
#endif
