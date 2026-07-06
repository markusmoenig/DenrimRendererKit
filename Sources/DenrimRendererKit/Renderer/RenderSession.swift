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

/// Coarse GPU-side SDF traversal counters collected by a render session.
public struct SDFTraversalStats: Sendable, Equatable, Codable {
    public var denseVolumeTests: UInt32
    public var denseMarchSteps: UInt32
    public var sparseGridCellsVisited: UInt32
    public var sparseGridEmptyCells: UInt32
    public var sparseGridMacroSkips: UInt32
    public var sparseBrickTests: UInt32
    public var sparseBrickInvalid: UInt32
    public var sparseBrickRangeCulls: UInt32
    public var sparseBrickMarches: UInt32
    public var sparseBrickMarchSteps: UInt32
    public var sparseBrickHits: UInt32
    public var primarySceneQueries: UInt32
    public var bounceSceneQueries: UInt32
    public var shadowSceneQueries: UInt32

    public static let zero = SDFTraversalStats(
        denseVolumeTests: 0,
        denseMarchSteps: 0,
        sparseGridCellsVisited: 0,
        sparseGridEmptyCells: 0,
        sparseGridMacroSkips: 0,
        sparseBrickTests: 0,
        sparseBrickInvalid: 0,
        sparseBrickRangeCulls: 0,
        sparseBrickMarches: 0,
        sparseBrickMarchSteps: 0,
        sparseBrickHits: 0,
        primarySceneQueries: 0,
        bounceSceneQueries: 0,
        shadowSceneQueries: 0
    )
}

private enum SDFTraversalCounter: Int, CaseIterable {
    case denseVolumeTests
    case denseMarchSteps
    case sparseGridCellsVisited
    case sparseGridMacroSkips
    case sparseBrickTests
    case sparseBrickInvalid
    case sparseBrickRangeCulls
    case sparseBrickMarches
    case sparseBrickMarchSteps
    case sparseBrickHits
    case primarySceneQueries
    case bounceSceneQueries
    case shadowSceneQueries
}

/// Pixel rectangle rendered by a tiled progressive render call.
public struct RenderTile: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = max(x, 0)
        self.y = max(y, 0)
        self.width = max(width, 0)
        self.height = max(height, 0)
    }
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
    private var volumeBuffer: MTLBuffer
    private var volumeSampleBuffer: MTLBuffer
    private var volumeAttributeDescriptorBuffer: MTLBuffer
    private var volumeAttributeSampleBuffer: MTLBuffer
    private var volumeBrickBuffer: MTLBuffer
    private var volumeBrickSampleBuffer: MTLBuffer
    private var volumeBrickMaterialFieldSampleBuffer: MTLBuffer
    private var volumeBrickAttributeDescriptorBuffer: MTLBuffer
    private var volumeBrickAttributeSampleBuffer: MTLBuffer
    private var volumeBrickBVHNodeBuffer: MTLBuffer
    private var volumeBrickBVHIndexBuffer: MTLBuffer
    private var volumeBrickGridBuffer: MTLBuffer
    private var volumeBrickGridIndexBuffer: MTLBuffer
    private let materialBuffer: MTLBuffer
    private let materialSemanticBuffer: MTLBuffer
    private let textureDescriptorBuffer: MTLBuffer
    private let texturePixelBuffer: MTLBuffer
    private let lightBuffer: MTLBuffer
    private let environmentSampleBuffer: MTLBuffer
    private let sdfTraversalStatsBuffer: MTLBuffer
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
    private var volumeCount: Int
    private var volumeSampleCount: Int
    private var volumeAttributeSampleCount: Int
    private var volumeBrickCount: Int
    private var volumeBrickSampleCount: Int
    private var volumeBrickMaterialFieldSampleCount: Int
    private var volumeBrickAttributeSampleCount: Int
    private var volumeBrickBVHNodeCount: Int
    private var volumeBrickBVHIndexCount: Int
    private var volumeBrickGridCount: Int
    private var volumeBrickGridIndexCount: Int
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
            hasNodeBuffer: accelerationNodeCount > 0 && accelerationNodeBuffer != nil,
            hasPrimitiveIndexBuffer: accelerationNodeCount > 0 && primitiveIndexBuffer != nil
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
            hasFlatBVH: accelerationNodeCount > 0 && accelerationNodeBuffer != nil && primitiveIndexBuffer != nil,
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

    var sdfResourceDebugInfo: (
        volumeBuffer: MTLBuffer,
        volumeBrickBuffer: MTLBuffer,
        volumeBrickSampleBuffer: MTLBuffer,
        volumeBrickAttributeDescriptorBuffer: MTLBuffer,
        volumeBrickGridBuffer: MTLBuffer,
        volumeBrickGridIndexBuffer: MTLBuffer,
        volumeBrickCount: Int,
        volumeBrickGridIndexCount: Int
    ) {
        (
            volumeBuffer,
            volumeBrickBuffer,
            volumeBrickSampleBuffer,
            volumeBrickAttributeDescriptorBuffer,
            volumeBrickGridBuffer,
            volumeBrickGridIndexBuffer,
            volumeBrickCount,
            volumeBrickGridIndexCount
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
            && scene.volumeInstances.isEmpty
            && scene.sparseVolumeInstances.isEmpty
            && scene.gpuSparseVolumeInstances.isEmpty
        let accelerationBackend: AccelerationBackend = canBuildHardwareAcceleration
            ? MetalRayTracingAccelerationBackend(
                device: device,
                commandQueue: commandQueue,
                buildsFlatBVH: false
            )
            : LinearTriangleAccelerationBackend(buildsVolumeBrickBVH: false)
        let compiled = try accelerationBackend.build(scene: scene)
        guard !compiled.triangles.isEmpty || !compiled.volumes.isEmpty else {
            throw DenrimRendererError.invalidScene("Scene contains no renderable geometry.")
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
        self.volumeCount = compiled.volumes.count
        self.volumeSampleCount = compiled.volumeSamples.count
        self.volumeAttributeSampleCount = compiled.volumeAttributeSamples.count
        self.volumeBrickCount = compiled.gpuVolumeBrickCount ?? compiled.volumeBricks.count
        self.volumeBrickSampleCount = compiled.gpuVolumeBrickSampleCount ?? compiled.volumeBrickSamples.count
        self.volumeBrickMaterialFieldSampleCount = compiled.volumeBrickMaterialFieldSamples.count
        self.volumeBrickAttributeSampleCount = compiled.gpuVolumeBrickAttributeSampleCount ?? compiled.volumeBrickAttributeSamples.count
        self.volumeBrickBVHNodeCount = compiled.volumeBrickBVH.nodes.count
        self.volumeBrickBVHIndexCount = compiled.volumeBrickBVH.primitiveIndices.count
        self.volumeBrickGridCount = compiled.gpuVolumeBrickGridCount ?? compiled.volumeBrickGrids.count
        self.volumeBrickGridIndexCount = compiled.gpuVolumeBrickGridIndexCount ?? compiled.volumeBrickGridIndices.count
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

        self.triangleBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.triangles
        )
        self.volumeBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumes
        )
        self.volumeSampleBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumeSamples
        )
        self.volumeAttributeDescriptorBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumeAttributeDescriptors
        )
        self.volumeAttributeSampleBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumeAttributeSamples
        )
        if let gpuVolumeBrickBuffer = compiled.gpuVolumeBrickBuffer {
            guard gpuVolumeBrickBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field brick metadata buffer belongs to a different Metal device.")
            }
            self.volumeBrickBuffer = gpuVolumeBrickBuffer
        } else {
            self.volumeBrickBuffer = try Self.makeRequiredShaderBindingBuffer(
                device: device,
                values: compiled.volumeBricks
            )
        }
        if let gpuVolumeBrickSampleBuffer = compiled.gpuVolumeBrickSampleBuffer {
            guard gpuVolumeBrickSampleBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field sample buffer belongs to a different Metal device.")
            }
            self.volumeBrickSampleBuffer = gpuVolumeBrickSampleBuffer
        } else {
            self.volumeBrickSampleBuffer = try Self.makeRequiredShaderBindingBuffer(
                device: device,
                values: compiled.volumeBrickSamples
            )
        }
        self.volumeBrickMaterialFieldSampleBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumeBrickMaterialFieldSamples
        )
        if let gpuVolumeBrickAttributeDescriptorBuffer = compiled.gpuVolumeBrickAttributeDescriptorBuffer {
            guard gpuVolumeBrickAttributeDescriptorBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field attribute metadata buffer belongs to a different Metal device.")
            }
            self.volumeBrickAttributeDescriptorBuffer = gpuVolumeBrickAttributeDescriptorBuffer
        } else {
            self.volumeBrickAttributeDescriptorBuffer = try Self.makeRequiredShaderBindingBuffer(
                device: device,
                values: compiled.volumeBrickAttributeDescriptors
            )
        }
        if let gpuVolumeBrickAttributeSampleBuffer = compiled.gpuVolumeBrickAttributeSampleBuffer {
            guard gpuVolumeBrickAttributeSampleBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field attribute sample buffer belongs to a different Metal device.")
            }
            self.volumeBrickAttributeSampleBuffer = gpuVolumeBrickAttributeSampleBuffer
        } else {
            self.volumeBrickAttributeSampleBuffer = try Self.makeRequiredShaderBindingBuffer(
                device: device,
                values: compiled.volumeBrickAttributeSamples
            )
        }
        self.volumeBrickBVHNodeBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumeBrickBVH.nodes
        )
        self.volumeBrickBVHIndexBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.volumeBrickBVH.primitiveIndices
        )
        if let gpuVolumeBrickGridBuffer = compiled.gpuVolumeBrickGridBuffer {
            guard gpuVolumeBrickGridBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field grid metadata buffer belongs to a different Metal device.")
            }
            self.volumeBrickGridBuffer = gpuVolumeBrickGridBuffer
        } else {
            self.volumeBrickGridBuffer = try Self.makeRequiredShaderBindingBuffer(
                device: device,
                values: compiled.volumeBrickGrids
            )
        }
        if let gpuVolumeBrickGridIndexBuffer = compiled.gpuVolumeBrickGridIndexBuffer {
            guard gpuVolumeBrickGridIndexBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field grid index metadata buffer belongs to a different Metal device.")
            }
            self.volumeBrickGridIndexBuffer = gpuVolumeBrickGridIndexBuffer
        } else {
            self.volumeBrickGridIndexBuffer = try Self.makeRequiredShaderBindingBuffer(
                device: device,
                values: compiled.volumeBrickGridIndices
            )
        }
        self.materialBuffer = device.makeBuffer(
            bytes: compiled.materials,
            length: MemoryLayout<GPUMaterial>.stride * compiled.materials.count,
            options: .storageModeShared
        )!
        self.materialSemanticBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.materialSemantics
        )
        self.textureDescriptorBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.textureDescriptors
        )
        self.texturePixelBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.texturePixels
        )
        self.lightBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.lights
        )
        self.environmentSampleBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.environmentSamples
        )
        guard let sdfTraversalStatsBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * SDFTraversalCounter.allCases.count,
            options: .storageModeShared
        ) else {
            throw DenrimRendererError.commandBufferFailed("Could not create SDF traversal stats buffer.")
        }
        memset(sdfTraversalStatsBuffer.contents(), 0, sdfTraversalStatsBuffer.length)
        self.sdfTraversalStatsBuffer = sdfTraversalStatsBuffer
        self.accelerationNodeBuffer = try Self.makeRequiredShaderBindingBuffer(
            device: device,
            values: compiled.bvh.nodes
        )
        self.primitiveIndexBuffer = try Self.makeRequiredShaderBindingBuffer(
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

    /// Resets accumulated SDF traversal counters to zero.
    public func resetSDFTraversalStats() {
        memset(sdfTraversalStatsBuffer.contents(), 0, sdfTraversalStatsBuffer.length)
    }

    /// Refreshes only mutable distance-volume buffers while preserving render targets and accumulated resources.
    ///
    /// This supports live topology edits for GPU-resident sparse fields. Geometry,
    /// materials, lights, camera, textures, and triangle acceleration are expected
    /// to remain compatible with the current session.
    func replaceDistanceFieldResources(from scene: RenderScene) throws {
        guard !scene.gpuSparseVolumeInstances.isEmpty else {
            throw DenrimRendererError.invalidScene("In-place distance field replacement requires a GPU-resident sparse field.")
        }

        let compiled = try LinearTriangleAccelerationBackend(
            buildsFlatBVH: false,
            buildsVolumeBrickBVH: false
        ).build(scene: scene)

        guard compiled.triangles.count == triangleCount else {
            throw DenrimRendererError.invalidScene("In-place distance field replacement cannot change triangle geometry.")
        }
        guard compiled.materials.count == materialCount,
              compiled.textureDescriptors.count == textureDescriptorCount,
              compiled.texturePixels.count == texturePixelCount,
              compiled.environmentTextureIndexPlusOne == environmentTextureIndexPlusOne,
              compiled.environmentSamples.count == environmentDistributionCount,
              compiled.lights.count == lightCount else {
            throw DenrimRendererError.invalidScene("In-place distance field replacement cannot change materials, textures, environment, or lights.")
        }

        let newVolumeBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeBuffer,
            device: device,
            values: compiled.volumes
        )
        let newVolumeSampleBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeSampleBuffer,
            device: device,
            values: compiled.volumeSamples
        )
        let newVolumeAttributeDescriptorBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeAttributeDescriptorBuffer,
            device: device,
            values: compiled.volumeAttributeDescriptors
        )
        let newVolumeAttributeSampleBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeAttributeSampleBuffer,
            device: device,
            values: compiled.volumeAttributeSamples
        )
        let newVolumeBrickBuffer: MTLBuffer
        if let gpuVolumeBrickBuffer = compiled.gpuVolumeBrickBuffer {
            guard gpuVolumeBrickBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field brick metadata buffer belongs to a different Metal device.")
            }
            newVolumeBrickBuffer = gpuVolumeBrickBuffer
        } else {
            newVolumeBrickBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
                existing: volumeBrickBuffer,
                device: device,
                values: compiled.volumeBricks
            )
        }
        let newVolumeBrickSampleBuffer: MTLBuffer
        if let gpuVolumeBrickSampleBuffer = compiled.gpuVolumeBrickSampleBuffer {
            guard gpuVolumeBrickSampleBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field sample buffer belongs to a different Metal device.")
            }
            newVolumeBrickSampleBuffer = gpuVolumeBrickSampleBuffer
        } else {
            newVolumeBrickSampleBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
                existing: volumeBrickSampleBuffer,
                device: device,
                values: compiled.volumeBrickSamples
            )
        }
        let newVolumeBrickMaterialFieldSampleBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeBrickMaterialFieldSampleBuffer,
            device: device,
            values: compiled.volumeBrickMaterialFieldSamples
        )
        let newVolumeBrickAttributeDescriptorBuffer: MTLBuffer
        if let gpuVolumeBrickAttributeDescriptorBuffer = compiled.gpuVolumeBrickAttributeDescriptorBuffer {
            guard gpuVolumeBrickAttributeDescriptorBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field attribute metadata buffer belongs to a different Metal device.")
            }
            newVolumeBrickAttributeDescriptorBuffer = gpuVolumeBrickAttributeDescriptorBuffer
        } else {
            newVolumeBrickAttributeDescriptorBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
                existing: volumeBrickAttributeDescriptorBuffer,
                device: device,
                values: compiled.volumeBrickAttributeDescriptors
            )
        }
        let newVolumeBrickAttributeSampleBuffer: MTLBuffer
        if let gpuVolumeBrickAttributeSampleBuffer = compiled.gpuVolumeBrickAttributeSampleBuffer {
            guard gpuVolumeBrickAttributeSampleBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field attribute sample buffer belongs to a different Metal device.")
            }
            newVolumeBrickAttributeSampleBuffer = gpuVolumeBrickAttributeSampleBuffer
        } else {
            newVolumeBrickAttributeSampleBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
                existing: volumeBrickAttributeSampleBuffer,
                device: device,
                values: compiled.volumeBrickAttributeSamples
            )
        }
        let newVolumeBrickBVHNodeBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeBrickBVHNodeBuffer,
            device: device,
            values: compiled.volumeBrickBVH.nodes
        )
        let newVolumeBrickBVHIndexBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
            existing: volumeBrickBVHIndexBuffer,
            device: device,
            values: compiled.volumeBrickBVH.primitiveIndices
        )
        let newVolumeBrickGridBuffer: MTLBuffer
        if let gpuVolumeBrickGridBuffer = compiled.gpuVolumeBrickGridBuffer {
            guard gpuVolumeBrickGridBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field grid metadata buffer belongs to a different Metal device.")
            }
            newVolumeBrickGridBuffer = gpuVolumeBrickGridBuffer
        } else {
            newVolumeBrickGridBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
                existing: volumeBrickGridBuffer,
                device: device,
                values: compiled.volumeBrickGrids
            )
        }
        let newVolumeBrickGridIndexBuffer: MTLBuffer
        if let gpuVolumeBrickGridIndexBuffer = compiled.gpuVolumeBrickGridIndexBuffer {
            guard gpuVolumeBrickGridIndexBuffer.device === device else {
                throw DenrimRendererError.invalidScene("GPU sparse distance field grid index metadata buffer belongs to a different Metal device.")
            }
            newVolumeBrickGridIndexBuffer = gpuVolumeBrickGridIndexBuffer
        } else {
            newVolumeBrickGridIndexBuffer = try Self.reuseOrMakeRequiredShaderBindingBuffer(
                existing: volumeBrickGridIndexBuffer,
                device: device,
                values: compiled.volumeBrickGridIndices
            )
        }

        volumeBuffer = newVolumeBuffer
        volumeSampleBuffer = newVolumeSampleBuffer
        volumeAttributeDescriptorBuffer = newVolumeAttributeDescriptorBuffer
        volumeAttributeSampleBuffer = newVolumeAttributeSampleBuffer
        volumeBrickBuffer = newVolumeBrickBuffer
        volumeBrickSampleBuffer = newVolumeBrickSampleBuffer
        volumeBrickMaterialFieldSampleBuffer = newVolumeBrickMaterialFieldSampleBuffer
        volumeBrickAttributeDescriptorBuffer = newVolumeBrickAttributeDescriptorBuffer
        volumeBrickAttributeSampleBuffer = newVolumeBrickAttributeSampleBuffer
        volumeBrickBVHNodeBuffer = newVolumeBrickBVHNodeBuffer
        volumeBrickBVHIndexBuffer = newVolumeBrickBVHIndexBuffer
        volumeBrickGridBuffer = newVolumeBrickGridBuffer
        volumeBrickGridIndexBuffer = newVolumeBrickGridIndexBuffer

        volumeCount = compiled.volumes.count
        volumeSampleCount = compiled.volumeSamples.count
        volumeAttributeSampleCount = compiled.volumeAttributeSamples.count
        volumeBrickCount = compiled.gpuVolumeBrickCount ?? compiled.volumeBricks.count
        volumeBrickSampleCount = compiled.gpuVolumeBrickSampleCount ?? compiled.volumeBrickSamples.count
        volumeBrickMaterialFieldSampleCount = compiled.volumeBrickMaterialFieldSamples.count
        volumeBrickAttributeSampleCount = compiled.gpuVolumeBrickAttributeSampleCount ?? compiled.volumeBrickAttributeSamples.count
        volumeBrickBVHNodeCount = compiled.volumeBrickBVH.nodes.count
        volumeBrickBVHIndexCount = compiled.volumeBrickBVH.primitiveIndices.count
        volumeBrickGridCount = compiled.gpuVolumeBrickGridCount ?? compiled.volumeBrickGrids.count
        volumeBrickGridIndexCount = compiled.gpuVolumeBrickGridIndexCount ?? compiled.volumeBrickGridIndices.count

        resetAccumulation()
    }

    /// Reads accumulated SDF traversal counters.
    public func sdfTraversalStats() -> SDFTraversalStats {
        let counters = sdfTraversalStatsBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: SDFTraversalCounter.allCases.count
        )
        let sparseGridCellsVisited = counters[SDFTraversalCounter.sparseGridCellsVisited.rawValue]
        let sparseBrickTests = counters[SDFTraversalCounter.sparseBrickTests.rawValue]
        return SDFTraversalStats(
            denseVolumeTests: counters[SDFTraversalCounter.denseVolumeTests.rawValue],
            denseMarchSteps: counters[SDFTraversalCounter.denseMarchSteps.rawValue],
            sparseGridCellsVisited: sparseGridCellsVisited,
            sparseGridEmptyCells: sparseGridCellsVisited - min(sparseGridCellsVisited, sparseBrickTests),
            sparseGridMacroSkips: counters[SDFTraversalCounter.sparseGridMacroSkips.rawValue],
            sparseBrickTests: sparseBrickTests,
            sparseBrickInvalid: counters[SDFTraversalCounter.sparseBrickInvalid.rawValue],
            sparseBrickRangeCulls: counters[SDFTraversalCounter.sparseBrickRangeCulls.rawValue],
            sparseBrickMarches: counters[SDFTraversalCounter.sparseBrickMarches.rawValue],
            sparseBrickMarchSteps: counters[SDFTraversalCounter.sparseBrickMarchSteps.rawValue],
            sparseBrickHits: counters[SDFTraversalCounter.sparseBrickHits.rawValue],
            primarySceneQueries: counters[SDFTraversalCounter.primarySceneQueries.rawValue],
            bounceSceneQueries: counters[SDFTraversalCounter.bounceSceneQueries.rawValue],
            shadowSceneQueries: counters[SDFTraversalCounter.shadowSceneQueries.rawValue]
        )
    }

    /// Renders one additional progressive sample.
    public func renderNextSample() throws {
        let previousSampleCount = sampleCount
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw DenrimRendererError.commandBufferFailed("Could not create command buffer.")
        }

        try encodeNextSample(into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            sampleCount = previousSampleCount
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }
    }

    /// Encodes one additional progressive sample into an application-owned command buffer.
    ///
    /// Use this from live Metal integrations that want renderer work and presentation work ordered
    /// in the same frame without blocking on `waitUntilCompleted()`.
    public func encodeNextSample(into commandBuffer: MTLCommandBuffer) throws {
        try encodeNextSample(
            tile: RenderTile(x: 0, y: 0, width: settings.width, height: settings.height),
            completesSample: true,
            into: commandBuffer
        )
    }

    /// Encodes one tile of the current progressive sample.
    ///
    /// `completesSample` should be `true` only for the final tile in a full-frame tile sweep.
    /// Until then, `sampleCount` remains unchanged so each tile in the sweep accumulates with
    /// the same sample weight.
    public func encodeNextTile(
        _ tile: RenderTile,
        completesSample: Bool,
        into commandBuffer: MTLCommandBuffer
    ) throws {
        try encodeNextSample(tile: tile, completesSample: completesSample, into: commandBuffer)
    }

    /// Renders one tile synchronously.
    public func renderNextTile(_ tile: RenderTile, completesSample: Bool) throws {
        let previousSampleCount = sampleCount
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw DenrimRendererError.commandBufferFailed("Could not create command buffer.")
        }
        try encodeNextTile(tile, completesSample: completesSample, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            sampleCount = previousSampleCount
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }
    }

    private func encodeNextSample(
        tile requestedTile: RenderTile,
        completesSample: Bool,
        into commandBuffer: MTLCommandBuffer
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create command encoder.")
        }
        let tileX = max(0, min(requestedTile.x, settings.width))
        let tileY = max(0, min(requestedTile.y, settings.height))
        let tileWidth = max(0, min(requestedTile.width, settings.width - tileX))
        let tileHeight = max(0, min(requestedTile.height, settings.height - tileY))
        guard tileWidth > 0, tileHeight > 0 else {
            encoder.endEncoding()
            return
        }

        var constants = GPURenderConstants(
            width: UInt32(settings.width),
            height: UInt32(settings.height),
            triangleCount: UInt32(triangleCount),
            volumeCount: UInt32(volumeCount),
            materialCount: UInt32(materialCount),
            sampleIndex: UInt32(sampleCount),
            maxBounces: UInt32(max(1, settings.maxBounces)),
            renderQuality: settings.shaderQualityLevel,
            frameSeed: UInt32(0x1234ABCD),
            accelerationNodeCount: UInt32(accelerationNodeCount),
            transparentBackground: settings.transparentBackground ? 1 : 0,
            showsEnvironmentBackground: settings.showsEnvironmentBackground ? 1 : 0,
            lightCount: UInt32(lightCount),
            environmentTextureIndexPlusOne: environmentTextureIndexPlusOne,
            environmentDistributionCount: UInt32(environmentDistributionCount),
            environmentIntensity: environmentIntensity,
            environmentRotationY: environmentRotationY,
            environmentMaxRadiance: environmentMaxRadiance,
            sampleRadianceClamp: settings.resolvedSampleRadianceClamp,
            backgroundColor: SIMD4<Float>(settings.backgroundColor, 1),
            volumeSampleCount: UInt32(volumeSampleCount),
            volumeAttributeSampleCount: UInt32(volumeAttributeSampleCount),
            volumeBrickCount: UInt32(volumeBrickCount),
            volumeBrickSampleCount: UInt32(volumeBrickSampleCount),
            volumeBrickMaterialFieldSampleCount: UInt32(volumeBrickMaterialFieldSampleCount),
            volumeBrickAttributeSampleCount: UInt32(volumeBrickAttributeSampleCount),
            volumeBrickBVHNodeCount: UInt32(volumeBrickBVHNodeCount),
            volumeBrickBVHIndexCount: UInt32(volumeBrickBVHIndexCount),
            volumeBrickGridCount: UInt32(volumeBrickGridCount),
            volumeBrickGridIndexCount: UInt32(volumeBrickGridIndexCount),
            denoiserEnabled: settings.denoise.denoiser == .none ? 0 : 1,
            sdfTraversalStatsEnabled: settings.collectsSDFTraversalStats ? 1 : 0,
            tileX: UInt32(tileX),
            tileY: UInt32(tileY),
            tileWidth: UInt32(tileWidth),
            tileHeight: UInt32(tileHeight)
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
        encoder.setBuffer(volumeBuffer, offset: 0, index: 14)
        encoder.setBuffer(volumeSampleBuffer, offset: 0, index: 15)
        encoder.setBuffer(volumeBrickBuffer, offset: 0, index: 16)
        encoder.setBuffer(volumeBrickSampleBuffer, offset: 0, index: 17)
        encoder.setBuffer(materialSemanticBuffer, offset: 0, index: 18)
        encoder.setBuffer(volumeAttributeDescriptorBuffer, offset: 0, index: 19)
        encoder.setBuffer(volumeAttributeSampleBuffer, offset: 0, index: 20)
        encoder.setBuffer(volumeBrickAttributeDescriptorBuffer, offset: 0, index: 21)
        encoder.setBuffer(volumeBrickAttributeSampleBuffer, offset: 0, index: 22)
        encoder.setBuffer(volumeBrickBVHNodeBuffer, offset: 0, index: 23)
        encoder.setBuffer(volumeBrickBVHIndexBuffer, offset: 0, index: 24)
        encoder.setBuffer(volumeBrickGridBuffer, offset: 0, index: 25)
        encoder.setBuffer(volumeBrickGridIndexBuffer, offset: 0, index: 26)
        encoder.setBuffer(volumeBrickMaterialFieldSampleBuffer, offset: 0, index: 27)
        encoder.setBuffer(sdfTraversalStatsBuffer, offset: 0, index: 28)
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
        let grid = MTLSize(width: tileWidth, height: tileHeight, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()

        if completesSample {
            sampleCount += 1
        }
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

    /// Returns the current Metal texture for a render output.
    ///
    /// Host applications can use this for live progressive display without forcing a CPU readback.
    /// For `.beauty`, this returns the denoised texture when denoising is enabled and current;
    /// otherwise it returns the accumulated beauty texture.
    public func metalTexture(for output: RenderOutput = .beauty) throws -> MTLTexture {
        try texture(for: output)
    }

    /// Returns the current Metal texture without encoding any additional renderer work.
    ///
    /// Use this immediately after `encodeNextSample(into:)` when the caller owns a frame command
    /// buffer and wants to sample the renderer output later in that same command buffer. For
    /// `.beauty`, this always returns the raw accumulated beauty texture instead of launching a
    /// denoise pass on a separate command buffer.
    public func liveMetalTexture(for output: RenderOutput = .beauty) -> MTLTexture {
        rawTexture(for: output)
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

    private func rawTexture(for output: RenderOutput) -> MTLTexture {
        switch output {
        case .beauty:
            return accumulationTexture
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

    private static func makeRequiredShaderBindingBuffer<T>(
        device: MTLDevice,
        values: [T]
    ) throws -> MTLBuffer {
        if let buffer = makeBuffer(device: device, values: values) {
            return buffer
        }
        guard let buffer = device.makeBuffer(
            length: max(MemoryLayout<T>.stride, 1),
            options: .storageModeShared
        ) else {
            throw DenrimRendererError.commandBufferFailed("Could not create empty shader binding buffer.")
        }
        return buffer
    }

    private static func reuseOrMakeRequiredShaderBindingBuffer<T>(
        existing: MTLBuffer,
        device: MTLDevice,
        values: [T]
    ) throws -> MTLBuffer {
        let requiredLength = max(MemoryLayout<T>.stride * values.count, MemoryLayout<T>.stride, 1)
        guard existing.device === device, existing.length >= requiredLength else {
            return try makeRequiredShaderBindingBuffer(device: device, values: values)
        }

        guard !values.isEmpty else {
            return existing
        }
        values.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress, rawBuffer.count > 0 {
                memcpy(existing.contents(), baseAddress, rawBuffer.count)
                #if os(macOS)
                if existing.storageMode == .managed {
                    existing.didModifyRange(0..<rawBuffer.count)
                }
                #endif
            }
        }
        return existing
    }
}
