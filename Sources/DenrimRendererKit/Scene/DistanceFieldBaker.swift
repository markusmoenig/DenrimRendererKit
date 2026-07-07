import Foundation
import Metal
import simd

/// Preferred backend for baking procedural SDF graphs into renderable field bundles.
public enum DistanceFieldBakeBackend: String, Sendable, Equatable {
    /// Use the fastest available backend for the request, falling back when required.
    case automatic

    /// Use the CPU reference baker.
    case cpuReference = "cpu-reference"

    /// Use the Metal compute baker.
    case metalCompute = "metal-compute"
}

/// Storage target for a baked distance field.
public enum DistanceFieldBakeStorage: Sendable, Equatable {
    /// Dense row-major samples.
    case dense

    /// Sparse bricks extracted from baked samples.
    case sparseBricks(brickSize: Int = 8, narrowBand: Float = 0.1, sampleScale: Int = 1)
}

/// Metadata layout for GPU-resident sparse bakes.
public enum GPUResidentSparseMetadataMode: Sendable, Equatable {
    /// Read compact classification metadata back and build a compact brick list on the CPU.
    case compactedCPU

    /// Build a direct one-slot-per-grid-cell sparse table on the GPU.
    ///
    /// This avoids classification readback and CPU brick-list construction at the
    /// cost of a larger fixed sample buffer. It is intended for live editing.
    case directGridGPU
}

/// A bakeable SDF graph.
///
/// This is intentionally close to `SDFModel` for the first public API. Products
/// such as Denrim Form can compile timeline/operator state into this graph
/// without depending on SceneScript.
public struct DistanceFieldBakeGraph: Sendable, Equatable {
    /// Primitive composition to bake.
    public var model: SDFModel

    /// Optional procedural op tape. When present, the baker evaluates this instead of `model`.
    public var program: DistanceFieldProgram?

    /// Creates a bake graph from an SDF model.
    public init(model: SDFModel = SDFModel()) {
        self.model = model
        self.program = nil
    }

    /// Creates a bake graph from a procedural distance-field program.
    public init(program: DistanceFieldProgram) {
        self.model = SDFModel(attributeLayout: program.resolvedAttributeLayout)
        self.program = program
    }

    /// Creates a bake graph from primitives and an optional attribute layout.
    public init(
        primitives: [SDFPrimitive],
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout()
    ) {
        self.model = SDFModel(primitives: primitives, attributeLayout: attributeLayout)
        self.program = nil
    }
}

/// A request to bake a procedural SDF graph into renderer-owned field storage.
public struct DistanceFieldBakeRequest: Sendable, Equatable {
    /// Source graph.
    public var graph: DistanceFieldBakeGraph

    /// Cubic sample resolution.
    public var resolution: Int

    /// Bounds sampled in graph/model space.
    public var boundsMin: SIMD3<Float>
    public var boundsMax: SIMD3<Float>

    /// Output storage representation.
    public var storage: DistanceFieldBakeStorage

    /// Fallback material used for empty/default field regions.
    public var fallbackMaterial: MaterialID?

    /// Backend preference for this request.
    public var backend: DistanceFieldBakeBackend

    public init(
        graph: DistanceFieldBakeGraph,
        resolution: Int,
        boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1),
        boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 1),
        storage: DistanceFieldBakeStorage = .sparseBricks(),
        fallbackMaterial: MaterialID? = nil,
        backend: DistanceFieldBakeBackend = .automatic
    ) {
        self.graph = graph
        self.resolution = max(resolution, 2)
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.storage = storage
        self.fallbackMaterial = fallbackMaterial
        self.backend = backend
    }
}

/// Result of baking a distance field.
public struct DistanceFieldBakeResult: Sendable {
    /// Renderable field bundle.
    public var bundle: RenderFieldBundle

    /// Backend that actually produced the dense samples.
    public var backend: DistanceFieldBakeBackend

    /// Requested storage representation.
    public var storage: DistanceFieldBakeStorage

    /// Cubic sample resolution used by the bake.
    public var resolution: Int
}

/// Public service for baking procedural SDF graphs into RendererKit field bundles.
public final class DistanceFieldBaker: @unchecked Sendable {
    public let preferredBackend: DistanceFieldBakeBackend

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let sparseClassifyPipeline: MTLComputePipelineState?
    private let sparseBakePipeline: MTLComputePipelineState?
    private let sparseDirectGridBakePipeline: MTLComputePipelineState?
    private let sparseMacroGridPipeline: MTLComputePipelineState?
    private let sparseProgramDirectGridBakePipeline: MTLComputePipelineState?
    private let sparseProgramDirectGridSelectedBakePipeline: MTLComputePipelineState?

    /// Creates a CPU-only baker.
    public convenience init(preferredBackend: DistanceFieldBakeBackend = .automatic) {
        self.init(
            preferredBackend: preferredBackend,
            device: nil,
            commandQueue: nil,
            pipeline: nil,
            sparseClassifyPipeline: nil,
            sparseBakePipeline: nil,
            sparseDirectGridBakePipeline: nil,
            sparseMacroGridPipeline: nil,
            sparseProgramDirectGridBakePipeline: nil,
            sparseProgramDirectGridSelectedBakePipeline: nil
        )
    }

    init(
        preferredBackend: DistanceFieldBakeBackend = .automatic,
        device: MTLDevice?,
        commandQueue: MTLCommandQueue?,
        pipeline: MTLComputePipelineState?,
        sparseClassifyPipeline: MTLComputePipelineState? = nil,
        sparseBakePipeline: MTLComputePipelineState? = nil,
        sparseDirectGridBakePipeline: MTLComputePipelineState? = nil,
        sparseMacroGridPipeline: MTLComputePipelineState? = nil,
        sparseProgramDirectGridBakePipeline: MTLComputePipelineState? = nil,
        sparseProgramDirectGridSelectedBakePipeline: MTLComputePipelineState? = nil
    ) {
        self.preferredBackend = preferredBackend
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.sparseClassifyPipeline = sparseClassifyPipeline
        self.sparseBakePipeline = sparseBakePipeline
        self.sparseDirectGridBakePipeline = sparseDirectGridBakePipeline
        self.sparseMacroGridPipeline = sparseMacroGridPipeline
        self.sparseProgramDirectGridBakePipeline = sparseProgramDirectGridBakePipeline
        self.sparseProgramDirectGridSelectedBakePipeline = sparseProgramDirectGridSelectedBakePipeline
    }

    /// Bakes the request into a renderable field bundle.
    public func bake(_ request: DistanceFieldBakeRequest) throws -> DistanceFieldBakeResult {
        if let program = request.graph.program {
            return try bakeProgram(request, program: program)
        }

        let model = request.graph.model
        guard !model.primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }
        let fallbackMaterial = request.fallbackMaterial ?? model.primitives[0].material
        let backend = resolvedBackend(for: request)
        let bundle: RenderFieldBundle
        switch (backend, request.storage) {
        case (.metalCompute, .sparseBricks(let brickSize, let narrowBand, _))
            where canBakeSparseOnGPU(request):
            let sparse = try bakeSparseOnGPU(
                request,
                brickSize: brickSize,
                narrowBand: narrowBand,
                fallbackMaterial: fallbackMaterial
            )
            bundle = RenderFieldBundle(sparse: sparse, fallbackMaterial: fallbackMaterial)
        default:
            if case .sparseBricks(let brickSize, let narrowBand, let sampleScale) = request.storage {
                let sparse = try DistanceVolumeBuilder.buildSparse(
                    model: model,
                    settings: SparseDistanceVolumeBuildSettings(
                        resolution: request.resolution,
                        brickSize: brickSize,
                        boundsMin: request.boundsMin,
                        boundsMax: request.boundsMax,
                        narrowBand: narrowBand,
                        sampleScale: sampleScale
                    )
                )
                bundle = RenderFieldBundle(sparse: sparse, fallbackMaterial: fallbackMaterial)
            } else {
                let dense: DistanceVolume
                switch backend {
                case .metalCompute:
                    dense = try bakeDenseOnGPU(request, fallbackMaterial: fallbackMaterial)
                case .automatic, .cpuReference:
                    dense = try bakeDenseOnCPU(request)
                }

                bundle = RenderFieldBundle(dense: dense, fallbackMaterial: fallbackMaterial)
            }
        }

        return DistanceFieldBakeResult(
            bundle: bundle,
            backend: backend,
            storage: request.storage,
            resolution: request.resolution
        )
    }

    /// Bakes a sparse field whose large sample payload remains resident on the GPU.
    ///
    /// This is the preferred path for live procedural editors when the graph can be
    /// handled by RendererKit's Metal baker. The returned bundle can be added to a
    /// `RenderScene` like any other `RenderFieldBundle`.
    public func bakeGPUResident(
        _ request: DistanceFieldBakeRequest,
        reusing reusableResource: RenderGPUSparseFieldResource? = nil,
        sampleCapacityMultiplier: Float = 1,
        metadataMode: GPUResidentSparseMetadataMode = .compactedCPU
    ) throws -> DistanceFieldBakeResult {
        if let program = request.graph.program {
            guard case .sparseBricks(let brickSize, let narrowBand, _) = request.storage else {
                throw DenrimRendererError.invalidScene("GPU-resident distance field program baking currently supports sparse-brick storage only.")
            }
            guard metadataMode == .directGridGPU else {
                throw DenrimRendererError.invalidScene("GPU-resident distance field program baking currently requires direct-grid GPU metadata.")
            }
            guard let fallbackMaterial = request.fallbackMaterial ?? DistanceFieldProgramEvaluator.defaultMaterial(for: program) else {
                throw DenrimRendererError.invalidScene("Distance field program must contain at least one material-producing primitive.")
            }
            let resource = try bakeDirectGridProgramResourceOnGPU(
                request,
                program: program,
                brickSize: brickSize,
                narrowBand: narrowBand,
                fallbackMaterial: fallbackMaterial,
                reusing: reusableResource,
                sampleCapacityMultiplier: sampleCapacityMultiplier
            )
            return DistanceFieldBakeResult(
                bundle: RenderFieldBundle(gpuSparse: resource, fallbackMaterial: fallbackMaterial),
                backend: .metalCompute,
                storage: request.storage,
                resolution: request.resolution
            )
        }

        let model = request.graph.model
        guard !model.primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }
        guard case .sparseBricks(let brickSize, let narrowBand, _) = request.storage else {
            throw DenrimRendererError.invalidScene("GPU-resident distance field baking currently supports sparse-brick storage only.")
        }
        guard canBakeSparseOnGPU(request) else {
            throw DenrimRendererError.invalidScene("This distance field bake request cannot currently stay GPU-resident.")
        }

        let fallbackMaterial = request.fallbackMaterial ?? model.primitives[0].material
        let resource: RenderGPUSparseFieldResource
        switch metadataMode {
        case .compactedCPU:
            resource = try bakeSparseResourceOnGPU(
                request,
                brickSize: brickSize,
                narrowBand: narrowBand,
                fallbackMaterial: fallbackMaterial,
                reusing: reusableResource,
                sampleCapacityMultiplier: sampleCapacityMultiplier
            )
        case .directGridGPU:
            resource = try bakeDirectGridSparseResourceOnGPU(
                request,
                brickSize: brickSize,
                narrowBand: narrowBand,
                fallbackMaterial: fallbackMaterial,
                reusing: reusableResource,
                sampleCapacityMultiplier: sampleCapacityMultiplier
            )
        }
        return DistanceFieldBakeResult(
            bundle: RenderFieldBundle(gpuSparse: resource, fallbackMaterial: fallbackMaterial),
            backend: .metalCompute,
            storage: request.storage,
            resolution: request.resolution
        )
    }

    /// Encodes an in-place direct-grid GPU sparse brick rebake for a `DistanceFieldProgram`.
    ///
    /// The resource must have been created by `bakeGPUResident(..., metadataMode: .directGridGPU)`.
    /// This method updates the existing direct-grid brick slots and sample payload for the
    /// supplied brick indices. Set `updatesTopology` to `false` for material/attribute-only
    /// edits whose active brick set is known to be unchanged, which skips the macro-grid rebuild.
    /// Callers should reset progressive accumulation after the command buffer completes.
    public func encodeUpdateGPUResidentProgramBricks(
        _ resource: RenderGPUSparseFieldResource,
        program: DistanceFieldProgram,
        brickIndices requestedBrickIndices: [Int],
        narrowBand requestedNarrowBand: Float,
        fallbackMaterial requestedFallbackMaterial: MaterialID? = nil,
        updatesTopology: Bool = true,
        into commandBuffer: MTLCommandBuffer
    ) throws {
        guard !requestedBrickIndices.isEmpty else {
            return
        }
        guard let device,
              resource.device === device,
              let selectedBakePipeline = sparseProgramDirectGridSelectedBakePipeline else {
            throw DenrimRendererError.invalidScene("Dirty program brick updates require a matching Metal program selected-brick bake pipeline.")
        }
        guard let metadataBuffers = resource.metadataBuffers else {
            throw DenrimRendererError.invalidScene("Dirty program brick updates require direct-grid GPU sparse metadata buffers.")
        }

        let operations = try Self.gpuProgramOperations(for: program)
        let fallbackMaterial = requestedFallbackMaterial
            ?? DistanceFieldProgramEvaluator.defaultMaterial(for: program)
            ?? resource.defaultMaterial.materialA
        let candidateCount = max(metadataBuffers.brickCount, 1)
        var seenBrickIndices = Set<Int>()
        let dirtyBrickIndices = requestedBrickIndices.compactMap { brickIndex -> UInt32? in
            let clamped = max(0, min(brickIndex, candidateCount - 1))
            guard seenBrickIndices.insert(clamped).inserted else {
                return nil
            }
            return UInt32(clamped)
        }
        guard !dirtyBrickIndices.isEmpty else {
            return
        }

        let operationBuffer = try Self.buffer(device: device, values: operations)
        let dirtyBuffer = try Self.buffer(device: device, values: dirtyBrickIndices)
        guard program.resolvedAttributeLayout.packedVectorCount == 0 || resource.attributeSampleBuffer != nil else {
            throw DenrimRendererError.invalidScene("Dirty GPU-resident program attribute updates require an existing resident attribute sample buffer.")
        }
        guard !Self.programWritesMaterialFields(program) || resource.materialFieldSampleBuffer != nil else {
            throw DenrimRendererError.invalidScene("Dirty GPU-resident program material-field updates require an existing resident material-field sample buffer.")
        }
        let attributeBuffer = try Self.gpuResidentProgramAttributeSampleBuffer(
            device: device,
            requiredSampleCount: resource.sampleCount,
            program: program,
            reusing: resource.attributeSampleBuffer
        )
        let attributeArgumentBuffer = try attributeBuffer ?? Self.emptyBuffer(
            device: device,
            element: SIMD4<Float>.self,
            count: 1
        )
        let materialFieldBuffer = try Self.gpuResidentProgramMaterialFieldSampleBuffer(
            device: device,
            requiredSampleCount: resource.sampleCount,
            program: program,
            reusing: resource.materialFieldSampleBuffer
        )
        let materialFieldArgumentBuffer = try materialFieldBuffer ?? Self.emptyBuffer(
            device: device,
            element: GPUVolumeMaterialFieldSample.self,
            count: 1
        )
        var attributeLayout = Self.gpuProgramAttributeLayout(for: program)
        let gridDimensions = SIMD3<Int>(
            (resource.dimensions.x + resource.brickSize.x - 1) / resource.brickSize.x,
            (resource.dimensions.y + resource.brickSize.y - 1) / resource.brickSize.y,
            (resource.dimensions.z + resource.brickSize.z - 1) / resource.brickSize.z
        )
        let maxStoredSampleCount = max(resource.sampleCount / candidateCount, 1)
        let overlap = 2
        var constants = GPUSparseDistanceFieldBakeConstants(
            dimensions: SIMD4<UInt32>(
                UInt32(resource.dimensions.x),
                UInt32(resource.dimensions.y),
                UInt32(resource.dimensions.z),
                UInt32(candidateCount)
            ),
            gridDimensions: SIMD4<UInt32>(
                UInt32(gridDimensions.x),
                UInt32(gridDimensions.y),
                UInt32(gridDimensions.z),
                UInt32(resource.brickSize.x)
            ),
            metadata: SIMD4<UInt32>(
                UInt32(operations.count),
                fallbackMaterial.rawValue,
                UInt32(overlap),
                UInt32(maxStoredSampleCount)
            ),
            boundsMin: SIMD4<Float>(resource.boundsMin, 0),
            extent: SIMD4<Float>(resource.boundsMax - resource.boundsMin, 0),
            settings: SIMD4<Float>(max(requestedNarrowBand, 0), 0, 0, 0)
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create dirty program brick bake command encoder.")
        }
        encoder.setComputePipelineState(selectedBakePipeline)
        encoder.setBuffer(operationBuffer, offset: 0, index: 0)
        encoder.setBuffer(resource.sampleBuffer, offset: 0, index: 1)
        encoder.setBuffer(metadataBuffers.brickBuffer, offset: 0, index: 2)
        encoder.setBuffer(metadataBuffers.attributeDescriptorBuffer, offset: 0, index: 3)
        encoder.setBuffer(metadataBuffers.gridBuffer, offset: 0, index: 4)
        encoder.setBuffer(metadataBuffers.gridIndexBuffer, offset: 0, index: 5)
        encoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 6)
        encoder.setBuffer(dirtyBuffer, offset: 0, index: 7)
        encoder.setBuffer(attributeArgumentBuffer, offset: 0, index: 8)
        encoder.setBytes(&attributeLayout, length: MemoryLayout<GPUDistanceFieldProgramAttributeLayout>.stride, index: 9)
        encoder.setBuffer(materialFieldArgumentBuffer, offset: 0, index: 10)
        let width = min(selectedBakePipeline.maxTotalThreadsPerThreadgroup, 128)
        encoder.dispatchThreadgroups(
            MTLSize(width: dirtyBrickIndices.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
        if updatesTopology {
            try encodeSparseMacroGridBuild(
                gridDimensions: gridDimensions,
                candidateCount: candidateCount,
                gridBuffer: metadataBuffers.gridBuffer,
                gridIndexBuffer: metadataBuffers.gridIndexBuffer,
                constants: &constants,
                into: commandBuffer
            )
        }
    }

    private func bakeProgram(_ request: DistanceFieldBakeRequest, program: DistanceFieldProgram) throws -> DistanceFieldBakeResult {
        let program = program.optimized()
        guard let fallbackMaterial = request.fallbackMaterial ?? DistanceFieldProgramEvaluator.defaultMaterial(for: program) else {
            throw DenrimRendererError.invalidScene("Distance field program must contain at least one material-producing primitive.")
        }
        let bundle: RenderFieldBundle
        switch request.storage {
        case .dense:
            let dense = try DistanceFieldProgramBuilder.build(
                program: program,
                settings: DistanceVolumeBuildSettings(
                    resolution: request.resolution,
                    boundsMin: request.boundsMin,
                    boundsMax: request.boundsMax
                ),
                fallbackMaterial: fallbackMaterial
            )
            bundle = RenderFieldBundle(dense: dense, fallbackMaterial: fallbackMaterial)
        case .sparseBricks(let brickSize, let narrowBand, let sampleScale):
            let sparse = try DistanceFieldProgramBuilder.buildSparse(
                program: program,
                settings: SparseDistanceVolumeBuildSettings(
                    resolution: request.resolution,
                    brickSize: brickSize,
                    boundsMin: request.boundsMin,
                    boundsMax: request.boundsMax,
                    narrowBand: narrowBand,
                    sampleScale: sampleScale
                ),
                fallbackMaterial: fallbackMaterial
            )
            bundle = RenderFieldBundle(sparse: sparse, fallbackMaterial: fallbackMaterial)
        }
        return DistanceFieldBakeResult(
            bundle: bundle,
            backend: .cpuReference,
            storage: request.storage,
            resolution: request.resolution
        )
    }

    private func resolvedBackend(for request: DistanceFieldBakeRequest) -> DistanceFieldBakeBackend {
        let requested = request.backend == .automatic ? preferredBackend : request.backend
        switch requested {
        case .metalCompute:
            return canBakeOnGPU(request) ? .metalCompute : .cpuReference
        case .automatic:
            return canBakeOnGPU(request) ? .metalCompute : .cpuReference
        case .cpuReference:
            return .cpuReference
        }
    }

    private func canBakeOnGPU(_ request: DistanceFieldBakeRequest) -> Bool {
        guard device != nil, commandQueue != nil, pipeline != nil else {
            return false
        }
        let model = request.graph.model
        guard model.attributeLayout.isEmpty else {
            return false
        }
        return model.primitives.allSatisfy { primitive in
            primitive.materialFields.flags == 0 && primitive.attributes.values.isEmpty
        }
    }

    private func canBakeSparseOnGPU(_ request: DistanceFieldBakeRequest) -> Bool {
        guard canBakeOnGPU(request),
              sparseClassifyPipeline != nil,
              sparseBakePipeline != nil else {
            return false
        }
        return true
    }

    private static let sparseMacroCellSize = SIMD3<Int>(repeating: 4)

    private static func sparseMacroGridDimensions(gridDimensions: SIMD3<Int>) -> SIMD3<Int> {
        SIMD3<Int>(
            (gridDimensions.x + sparseMacroCellSize.x - 1) / sparseMacroCellSize.x,
            (gridDimensions.y + sparseMacroCellSize.y - 1) / sparseMacroCellSize.y,
            (gridDimensions.z + sparseMacroCellSize.z - 1) / sparseMacroCellSize.z
        )
    }

    private static func sparseSampleScale(for storage: DistanceFieldBakeStorage) -> Int {
        guard case .sparseBricks(_, _, let sampleScale) = storage else {
            return 1
        }
        return max(sampleScale, 1)
    }

    private static func sparseLayout(
        resolution: Int,
        requestedBrickSize: Int,
        sampleScale: Int
    ) -> (dimensions: SIMD3<Int>, brickSize: SIMD3<Int>) {
        let resolution = max(resolution, 2)
        let sampleScale = max(sampleScale, 1)
        let dimension = (resolution - 1) * sampleScale + 1
        let brickSize = max(requestedBrickSize, 1) * sampleScale
        return (
            SIMD3<Int>(repeating: dimension),
            SIMD3<Int>(repeating: brickSize)
        )
    }

    private func encodeSparseMacroGridBuild(
        gridDimensions: SIMD3<Int>,
        candidateCount: Int,
        gridBuffer: MTLBuffer,
        gridIndexBuffer: MTLBuffer,
        constants: inout GPUSparseDistanceFieldBakeConstants,
        into commandBuffer: MTLCommandBuffer
    ) throws {
        guard let macroGridPipeline = sparseMacroGridPipeline else {
            return
        }
        let macroDimensions = Self.sparseMacroGridDimensions(gridDimensions: gridDimensions)
        let macroCount = macroDimensions.x * macroDimensions.y * macroDimensions.z
        guard macroCount > 0 else {
            return
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create sparse macro-grid build command encoder.")
        }
        encoder.setComputePipelineState(macroGridPipeline)
        encoder.setBuffer(gridBuffer, offset: 0, index: 0)
        encoder.setBuffer(gridIndexBuffer, offset: 0, index: 1)
        constants.dimensions.w = UInt32(candidateCount)
        encoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 2)
        let width = min(macroGridPipeline.maxTotalThreadsPerThreadgroup, 128)
        encoder.dispatchThreads(
            MTLSize(width: macroCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
    }

    private func bakeDenseOnCPU(_ request: DistanceFieldBakeRequest) throws -> DistanceVolume {
        try DistanceVolumeBuilder.build(
            model: request.graph.model,
            settings: DistanceVolumeBuildSettings(
                resolution: request.resolution,
                boundsMin: request.boundsMin,
                boundsMax: request.boundsMax
            )
        )
    }

    private func bakeDenseOnGPU(
        _ request: DistanceFieldBakeRequest,
        fallbackMaterial: MaterialID
    ) throws -> DistanceVolume {
        guard let device, let commandQueue, let pipeline else {
            return try bakeDenseOnCPU(request)
        }

        let dimensions = SIMD3<Int>(repeating: request.resolution)
        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        let primitives = request.graph.model.primitives.map(GPUDistanceFieldBakePrimitive.init)
        guard !primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }

        let primitiveBuffer = try Self.buffer(device: device, values: primitives)
        let sampleBuffer = try Self.emptyBuffer(
            device: device,
            element: GPUDistanceFieldBakeSample.self,
            count: sampleCount
        )
        var constants = GPUDistanceFieldBakeConstants(
            dimensions: SIMD4<UInt32>(
                UInt32(dimensions.x),
                UInt32(dimensions.y),
                UInt32(dimensions.z),
                UInt32(sampleCount)
            ),
            boundsMin: SIMD4<Float>(request.boundsMin, 0),
            extent: SIMD4<Float>(request.boundsMax - request.boundsMin, 0),
            metadata: SIMD4<UInt32>(
                UInt32(primitives.count),
                fallbackMaterial.rawValue,
                0,
                0
            )
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create distance field bake command buffer.")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(primitiveBuffer, offset: 0, index: 0)
        encoder.setBuffer(sampleBuffer, offset: 0, index: 1)
        encoder.setBytes(&constants, length: MemoryLayout<GPUDistanceFieldBakeConstants>.stride, index: 2)

        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadsPerGroup = MTLSize(width: width, height: 1, depth: 1)
        let threadgroups = MTLSize(
            width: (sampleCount + width - 1) / width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let raw = sampleBuffer.contents().bindMemory(
            to: GPUDistanceFieldBakeSample.self,
            capacity: sampleCount
        )
        var distances = [Float](repeating: 0, count: sampleCount)
        var materialSamples = [DistanceVolumeMaterialSample]()
        materialSamples.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let sample = raw[index]
            distances[index] = sample.distance
            materialSamples.append(DistanceVolumeMaterialSample(
                materialA: MaterialID(rawValue: sample.materialA),
                materialB: MaterialID(rawValue: sample.materialB),
                blend: sample.blend
            ))
        }

        return DistanceVolume(
            width: dimensions.x,
            height: dimensions.y,
            depth: dimensions.z,
            distances: distances,
            materialSamples: materialSamples,
            boundsMin: request.boundsMin,
            boundsMax: request.boundsMax
        )
    }

    private func bakeSparseOnGPU(
        _ request: DistanceFieldBakeRequest,
        brickSize requestedBrickSize: Int,
        narrowBand requestedNarrowBand: Float,
        fallbackMaterial: MaterialID
    ) throws -> SparseDistanceVolume {
        guard let device,
              let commandQueue,
              let classifyPipeline = sparseClassifyPipeline,
              let bakePipeline = sparseBakePipeline else {
            return try DistanceVolumeBuilder.buildSparse(
                model: request.graph.model,
                settings: SparseDistanceVolumeBuildSettings(
                    resolution: request.resolution,
                    brickSize: requestedBrickSize,
                    boundsMin: request.boundsMin,
                    boundsMax: request.boundsMax,
                    narrowBand: requestedNarrowBand,
                    sampleScale: Self.sparseSampleScale(for: request.storage)
                )
            )
        }

        let layout = Self.sparseLayout(
            resolution: request.resolution,
            requestedBrickSize: requestedBrickSize,
            sampleScale: Self.sparseSampleScale(for: request.storage)
        )
        let dimensions = layout.dimensions
        let brickSize = layout.brickSize
        let gridDimensions = SIMD3<Int>(
            (dimensions.x + brickSize.x - 1) / brickSize.x,
            (dimensions.y + brickSize.y - 1) / brickSize.y,
            (dimensions.z + brickSize.z - 1) / brickSize.z
        )
        let candidateCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
        let narrowBand = max(requestedNarrowBand, 0)
        let overlap = 2
        let defaultDistance = max(narrowBand, 1)
        let defaultMaterial = DistanceVolumeMaterialSample(materialA: fallbackMaterial)
        let primitives = request.graph.model.primitives.map(GPUDistanceFieldBakePrimitive.init)
        guard !primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }

        let primitiveBuffer = try Self.buffer(device: device, values: primitives)
        let classificationBuffer = try Self.emptyBuffer(
            device: device,
            element: GPUSparseBrickClassification.self,
            count: candidateCount
        )
        var constants = GPUSparseDistanceFieldBakeConstants(
            dimensions: SIMD4<UInt32>(
                UInt32(dimensions.x),
                UInt32(dimensions.y),
                UInt32(dimensions.z),
                UInt32(candidateCount)
            ),
            gridDimensions: SIMD4<UInt32>(
                UInt32(gridDimensions.x),
                UInt32(gridDimensions.y),
                UInt32(gridDimensions.z),
                UInt32(brickSize.x)
            ),
            metadata: SIMD4<UInt32>(
                UInt32(primitives.count),
                fallbackMaterial.rawValue,
                UInt32(overlap),
                0
            ),
            boundsMin: SIMD4<Float>(request.boundsMin, 0),
            extent: SIMD4<Float>(request.boundsMax - request.boundsMin, 0),
            settings: SIMD4<Float>(narrowBand, 0, 0, 0)
        )

        guard let classifyCommandBuffer = commandQueue.makeCommandBuffer(),
              let classifyEncoder = classifyCommandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create sparse distance field classify command buffer.")
        }
        classifyEncoder.setComputePipelineState(classifyPipeline)
        classifyEncoder.setBuffer(primitiveBuffer, offset: 0, index: 0)
        classifyEncoder.setBuffer(classificationBuffer, offset: 0, index: 1)
        classifyEncoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 2)
        let classifyWidth = min(classifyPipeline.maxTotalThreadsPerThreadgroup, 128)
        classifyEncoder.dispatchThreadgroups(
            MTLSize(width: (candidateCount + classifyWidth - 1) / classifyWidth, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: classifyWidth, height: 1, depth: 1)
        )
        classifyEncoder.endEncoding()
        classifyCommandBuffer.commit()
        classifyCommandBuffer.waitUntilCompleted()
        if let error = classifyCommandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let classifications = classificationBuffer.contents().bindMemory(
            to: GPUSparseBrickClassification.self,
            capacity: candidateCount
        )
        var records: [GPUSparseBrickBakeRecord] = []
        var brickMetadata: [(origin: SIMD3<Int>, dimensions: SIMD3<Int>, coreOrigin: SIMD3<Int>, coreDimensions: SIMD3<Int>)] = []
        var sampleOffset = 0
        var maxStoredSampleCount = 1
        records.reserveCapacity(candidateCount / 4)
        brickMetadata.reserveCapacity(candidateCount / 4)

        for candidateIndex in 0..<candidateCount where classifications[candidateIndex].metadata.x != 0 {
            let cell = DistanceFieldBaker.brickCell(index: candidateIndex, gridDimensions: gridDimensions)
            let coreOrigin = SIMD3<Int>(
                cell.x * brickSize.x,
                cell.y * brickSize.y,
                cell.z * brickSize.z
            )
            let coreEnd = SIMD3<Int>(
                min(coreOrigin.x + brickSize.x, dimensions.x),
                min(coreOrigin.y + brickSize.y, dimensions.y),
                min(coreOrigin.z + brickSize.z, dimensions.z)
            )
            let coreWidth = coreEnd.x - coreOrigin.x
            let coreHeight = coreEnd.y - coreOrigin.y
            let coreDepth = coreEnd.z - coreOrigin.z
            let coreDimensions = SIMD3<Int>(coreWidth, coreHeight, coreDepth)
            let storedOrigin = SIMD3<Int>(
                max(coreOrigin.x - overlap, 0),
                max(coreOrigin.y - overlap, 0),
                max(coreOrigin.z - overlap, 0)
            )
            let storedEnd = SIMD3<Int>(
                min(coreEnd.x + overlap, dimensions.x),
                min(coreEnd.y + overlap, dimensions.y),
                min(coreEnd.z + overlap, dimensions.z)
            )
            let storedDimensions = SIMD3<Int>(
                storedEnd.x - storedOrigin.x,
                storedEnd.y - storedOrigin.y,
                storedEnd.z - storedOrigin.z
            )
            let storedSampleCount = storedDimensions.x * storedDimensions.y * storedDimensions.z
            maxStoredSampleCount = max(maxStoredSampleCount, storedSampleCount)
            let originAndSampleOffset = SIMD4<UInt32>(
                UInt32(storedOrigin.x),
                UInt32(storedOrigin.y),
                UInt32(storedOrigin.z),
                UInt32(sampleOffset)
            )
            let dimensionsAndSampleCount = SIMD4<UInt32>(
                UInt32(storedDimensions.x),
                UInt32(storedDimensions.y),
                UInt32(storedDimensions.z),
                UInt32(storedSampleCount)
            )
            let coreOriginRecord = SIMD4<UInt32>(
                UInt32(coreOrigin.x),
                UInt32(coreOrigin.y),
                UInt32(coreOrigin.z),
                0
            )
            let coreDimensionsRecord = SIMD4<UInt32>(
                UInt32(coreDimensions.x),
                UInt32(coreDimensions.y),
                UInt32(coreDimensions.z),
                0
            )
            records.append(GPUSparseBrickBakeRecord(
                originAndSampleOffset: originAndSampleOffset,
                dimensionsAndSampleCount: dimensionsAndSampleCount,
                coreOrigin: coreOriginRecord,
                coreDimensions: coreDimensionsRecord
            ))
            brickMetadata.append((storedOrigin, storedDimensions, coreOrigin, coreDimensions))
            sampleOffset += storedSampleCount
        }

        guard !records.isEmpty else {
            return SparseDistanceVolume(
                dimensions: dimensions,
                brickSize: brickSize,
                boundsMin: request.boundsMin,
                boundsMax: request.boundsMax,
                defaultDistance: defaultDistance,
                defaultMaterial: defaultMaterial,
                bricks: []
            )
        }

        let recordBuffer = try Self.buffer(device: device, values: records)
        let sampleBuffer = try Self.emptyBuffer(
            device: device,
            element: GPUDistanceFieldBakeSample.self,
            count: sampleOffset
        )
        constants.metadata.w = UInt32(records.count)

        guard let bakeCommandBuffer = commandQueue.makeCommandBuffer(),
              let bakeEncoder = bakeCommandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create sparse distance field bake command buffer.")
        }
        bakeEncoder.setComputePipelineState(bakePipeline)
        bakeEncoder.setBuffer(primitiveBuffer, offset: 0, index: 0)
        bakeEncoder.setBuffer(recordBuffer, offset: 0, index: 1)
        bakeEncoder.setBuffer(sampleBuffer, offset: 0, index: 2)
        bakeEncoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 3)
        bakeEncoder.dispatchThreads(
            MTLSize(width: maxStoredSampleCount, height: records.count, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        bakeEncoder.endEncoding()
        bakeCommandBuffer.commit()
        bakeCommandBuffer.waitUntilCompleted()
        if let error = bakeCommandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let rawSamples = sampleBuffer.contents().bindMemory(
            to: GPUDistanceFieldBakeSample.self,
            capacity: sampleOffset
        )
        var bricks: [SparseDistanceVolumeBrick] = []
        bricks.reserveCapacity(records.count)
        for (index, metadata) in brickMetadata.enumerated() {
            let record = records[index]
            let offset = Int(record.originAndSampleOffset.w)
            let count = Int(record.dimensionsAndSampleCount.w)
            var distances = [Float]()
            var materialSamples = [DistanceVolumeMaterialSample]()
            var packedSamples = [PackedDistanceVolumeSample]()
            distances.reserveCapacity(count)
            materialSamples.reserveCapacity(count)
            packedSamples.reserveCapacity(count)
            for sampleIndex in 0..<count {
                let sample = rawSamples[offset + sampleIndex]
                distances.append(sample.distance)
                let materialSample = DistanceVolumeMaterialSample(
                    materialA: MaterialID(rawValue: sample.materialA),
                    materialB: MaterialID(rawValue: sample.materialB),
                    blend: sample.blend
                )
                materialSamples.append(materialSample)
                packedSamples.append(PackedDistanceVolumeSample(
                    distance: sample.distance,
                    materialA: sample.materialA,
                    materialB: sample.materialB,
                    materialBlend: simd_clamp(sample.blend, 0, 1)
                ))
            }
            bricks.append(SparseDistanceVolumeBrick(
                origin: metadata.origin,
                dimensions: metadata.dimensions,
                coreOrigin: metadata.coreOrigin,
                coreDimensions: metadata.coreDimensions,
                distances: distances,
                materialSamples: materialSamples,
                packedSamples: packedSamples
            ))
        }

        return SparseDistanceVolume(
            dimensions: dimensions,
            brickSize: brickSize,
            boundsMin: request.boundsMin,
            boundsMax: request.boundsMax,
            defaultDistance: defaultDistance,
            defaultMaterial: defaultMaterial,
            bricks: bricks
        )
    }

    private func bakeSparseResourceOnGPU(
        _ request: DistanceFieldBakeRequest,
        brickSize requestedBrickSize: Int,
        narrowBand requestedNarrowBand: Float,
        fallbackMaterial: MaterialID,
        reusing reusableResource: RenderGPUSparseFieldResource? = nil,
        sampleCapacityMultiplier: Float = 1
    ) throws -> RenderGPUSparseFieldResource {
        guard let device,
              let commandQueue,
              let classifyPipeline = sparseClassifyPipeline,
              let bakePipeline = sparseBakePipeline else {
            throw DenrimRendererError.invalidScene("GPU-resident sparse baking requires Metal sparse bake pipelines.")
        }

        let layout = Self.sparseLayout(
            resolution: request.resolution,
            requestedBrickSize: requestedBrickSize,
            sampleScale: Self.sparseSampleScale(for: request.storage)
        )
        let dimensions = layout.dimensions
        let brickSize = layout.brickSize
        let gridDimensions = SIMD3<Int>(
            (dimensions.x + brickSize.x - 1) / brickSize.x,
            (dimensions.y + brickSize.y - 1) / brickSize.y,
            (dimensions.z + brickSize.z - 1) / brickSize.z
        )
        let candidateCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
        let narrowBand = max(requestedNarrowBand, 0)
        let overlap = 2
        let primitives = request.graph.model.primitives.map(GPUDistanceFieldBakePrimitive.init)
        guard !primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }

        let primitiveBuffer = try Self.buffer(device: device, values: primitives)
        let classificationBuffer = try Self.emptyBuffer(
            device: device,
            element: GPUSparseBrickClassification.self,
            count: candidateCount
        )
        var constants = GPUSparseDistanceFieldBakeConstants(
            dimensions: SIMD4<UInt32>(
                UInt32(dimensions.x),
                UInt32(dimensions.y),
                UInt32(dimensions.z),
                UInt32(candidateCount)
            ),
            gridDimensions: SIMD4<UInt32>(
                UInt32(gridDimensions.x),
                UInt32(gridDimensions.y),
                UInt32(gridDimensions.z),
                UInt32(brickSize.x)
            ),
            metadata: SIMD4<UInt32>(
                UInt32(primitives.count),
                fallbackMaterial.rawValue,
                UInt32(overlap),
                0
            ),
            boundsMin: SIMD4<Float>(request.boundsMin, 0),
            extent: SIMD4<Float>(request.boundsMax - request.boundsMin, 0),
            settings: SIMD4<Float>(narrowBand, 0, 0, 0)
        )

        guard let classifyCommandBuffer = commandQueue.makeCommandBuffer(),
              let classifyEncoder = classifyCommandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create sparse distance field classify command buffer.")
        }
        classifyEncoder.setComputePipelineState(classifyPipeline)
        classifyEncoder.setBuffer(primitiveBuffer, offset: 0, index: 0)
        classifyEncoder.setBuffer(classificationBuffer, offset: 0, index: 1)
        classifyEncoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 2)
        let classifyWidth = min(classifyPipeline.maxTotalThreadsPerThreadgroup, 128)
        classifyEncoder.dispatchThreadgroups(
            MTLSize(width: (candidateCount + classifyWidth - 1) / classifyWidth, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: classifyWidth, height: 1, depth: 1)
        )
        classifyEncoder.endEncoding()
        classifyCommandBuffer.commit()
        classifyCommandBuffer.waitUntilCompleted()
        if let error = classifyCommandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let classifications = classificationBuffer.contents().bindMemory(
            to: GPUSparseBrickClassification.self,
            capacity: candidateCount
        )
        var records: [GPUSparseBrickBakeRecord] = []
        var bricks: [RenderGPUSparseFieldBrick] = []
        var sampleOffset = 0
        var maxStoredSampleCount = 1
        records.reserveCapacity(candidateCount / 4)
        bricks.reserveCapacity(candidateCount / 4)

        for candidateIndex in 0..<candidateCount where classifications[candidateIndex].metadata.x != 0 {
            let cell = DistanceFieldBaker.brickCell(index: candidateIndex, gridDimensions: gridDimensions)
            let coreOrigin = SIMD3<Int>(
                cell.x * brickSize.x,
                cell.y * brickSize.y,
                cell.z * brickSize.z
            )
            let coreEnd = SIMD3<Int>(
                min(coreOrigin.x + brickSize.x, dimensions.x),
                min(coreOrigin.y + brickSize.y, dimensions.y),
                min(coreOrigin.z + brickSize.z, dimensions.z)
            )
            let coreDimensions = SIMD3<Int>(
                coreEnd.x - coreOrigin.x,
                coreEnd.y - coreOrigin.y,
                coreEnd.z - coreOrigin.z
            )
            let storedOrigin = SIMD3<Int>(
                max(coreOrigin.x - overlap, 0),
                max(coreOrigin.y - overlap, 0),
                max(coreOrigin.z - overlap, 0)
            )
            let storedEnd = SIMD3<Int>(
                min(coreEnd.x + overlap, dimensions.x),
                min(coreEnd.y + overlap, dimensions.y),
                min(coreEnd.z + overlap, dimensions.z)
            )
            let storedDimensions = SIMD3<Int>(
                storedEnd.x - storedOrigin.x,
                storedEnd.y - storedOrigin.y,
                storedEnd.z - storedOrigin.z
            )
            let storedSampleCount = storedDimensions.x * storedDimensions.y * storedDimensions.z
            maxStoredSampleCount = max(maxStoredSampleCount, storedSampleCount)
            records.append(GPUSparseBrickBakeRecord(
                originAndSampleOffset: SIMD4<UInt32>(
                    UInt32(storedOrigin.x),
                    UInt32(storedOrigin.y),
                    UInt32(storedOrigin.z),
                    UInt32(sampleOffset)
                ),
                dimensionsAndSampleCount: SIMD4<UInt32>(
                    UInt32(storedDimensions.x),
                    UInt32(storedDimensions.y),
                    UInt32(storedDimensions.z),
                    UInt32(storedSampleCount)
                ),
                coreOrigin: SIMD4<UInt32>(
                    UInt32(coreOrigin.x),
                    UInt32(coreOrigin.y),
                    UInt32(coreOrigin.z),
                    0
                ),
                coreDimensions: SIMD4<UInt32>(
                    UInt32(coreDimensions.x),
                    UInt32(coreDimensions.y),
                    UInt32(coreDimensions.z),
                    0
                )
            ))
            bricks.append(RenderGPUSparseFieldBrick(
                origin: storedOrigin,
                dimensions: storedDimensions,
                coreOrigin: coreOrigin,
                coreDimensions: coreDimensions,
                sampleOffset: sampleOffset,
                sampleCount: storedSampleCount
            ))
            sampleOffset += storedSampleCount
        }

        guard !records.isEmpty else {
            let sampleBuffer = try Self.gpuResidentSampleBuffer(
                device: device,
                requiredSampleCount: 1,
                sampleCapacityMultiplier: sampleCapacityMultiplier,
                reusing: reusableResource
            )
            return RenderGPUSparseFieldResource(
                device: device,
                dimensions: dimensions,
                brickSize: brickSize,
                boundsMin: request.boundsMin,
                boundsMax: request.boundsMax,
                defaultDistance: max(narrowBand, 1),
                defaultMaterial: DistanceVolumeMaterialSample(materialA: fallbackMaterial),
                bricks: [],
                sampleBuffer: sampleBuffer,
                sampleCount: 1
            )
        }

        let recordBuffer = try Self.buffer(device: device, values: records)
        let sampleBuffer = try Self.gpuResidentSampleBuffer(
            device: device,
            requiredSampleCount: sampleOffset,
            sampleCapacityMultiplier: sampleCapacityMultiplier,
            reusing: reusableResource
        )
        constants.metadata.w = UInt32(records.count)

        guard let bakeCommandBuffer = commandQueue.makeCommandBuffer(),
              let bakeEncoder = bakeCommandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create sparse distance field bake command buffer.")
        }
        bakeEncoder.setComputePipelineState(bakePipeline)
        bakeEncoder.setBuffer(primitiveBuffer, offset: 0, index: 0)
        bakeEncoder.setBuffer(recordBuffer, offset: 0, index: 1)
        bakeEncoder.setBuffer(sampleBuffer, offset: 0, index: 2)
        bakeEncoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 3)
        bakeEncoder.dispatchThreads(
            MTLSize(width: maxStoredSampleCount, height: records.count, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        bakeEncoder.endEncoding()
        bakeCommandBuffer.commit()
        bakeCommandBuffer.waitUntilCompleted()
        if let error = bakeCommandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        return RenderGPUSparseFieldResource(
            device: device,
            dimensions: dimensions,
            brickSize: brickSize,
            boundsMin: request.boundsMin,
            boundsMax: request.boundsMax,
            defaultDistance: max(narrowBand, 1),
            defaultMaterial: DistanceVolumeMaterialSample(materialA: fallbackMaterial),
            bricks: bricks,
            sampleBuffer: sampleBuffer,
            sampleCount: sampleOffset
        )
    }

    private func bakeDirectGridSparseResourceOnGPU(
        _ request: DistanceFieldBakeRequest,
        brickSize requestedBrickSize: Int,
        narrowBand requestedNarrowBand: Float,
        fallbackMaterial: MaterialID,
        reusing reusableResource: RenderGPUSparseFieldResource? = nil,
        sampleCapacityMultiplier: Float = 1
    ) throws -> RenderGPUSparseFieldResource {
        guard let device,
              let commandQueue,
              let directGridBakePipeline = sparseDirectGridBakePipeline else {
            throw DenrimRendererError.invalidScene("Direct-grid GPU sparse baking requires the Metal direct-grid sparse bake pipeline.")
        }

        let layout = Self.sparseLayout(
            resolution: request.resolution,
            requestedBrickSize: requestedBrickSize,
            sampleScale: Self.sparseSampleScale(for: request.storage)
        )
        let dimensions = layout.dimensions
        let brickSize = layout.brickSize
        let gridDimensions = SIMD3<Int>(
            (dimensions.x + brickSize.x - 1) / brickSize.x,
            (dimensions.y + brickSize.y - 1) / brickSize.y,
            (dimensions.z + brickSize.z - 1) / brickSize.z
        )
        let candidateCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
        let narrowBand = max(requestedNarrowBand, 0)
        let overlap = 2
        let primitives = request.graph.model.primitives.map(GPUDistanceFieldBakePrimitive.init)
        guard !primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }

        var maxStoredSampleCount = 1
        for candidateIndex in 0..<candidateCount {
            let cell = DistanceFieldBaker.brickCell(index: candidateIndex, gridDimensions: gridDimensions)
            let coreOrigin = SIMD3<Int>(
                cell.x * brickSize.x,
                cell.y * brickSize.y,
                cell.z * brickSize.z
            )
            let coreEnd = SIMD3<Int>(
                min(coreOrigin.x + brickSize.x, dimensions.x),
                min(coreOrigin.y + brickSize.y, dimensions.y),
                min(coreOrigin.z + brickSize.z, dimensions.z)
            )
            let storedOrigin = SIMD3<Int>(
                max(coreOrigin.x - overlap, 0),
                max(coreOrigin.y - overlap, 0),
                max(coreOrigin.z - overlap, 0)
            )
            let storedEnd = SIMD3<Int>(
                min(coreEnd.x + overlap, dimensions.x),
                min(coreEnd.y + overlap, dimensions.y),
                min(coreEnd.z + overlap, dimensions.z)
            )
            let storedDimensions = SIMD3<Int>(
                storedEnd.x - storedOrigin.x,
                storedEnd.y - storedOrigin.y,
                storedEnd.z - storedOrigin.z
            )
            maxStoredSampleCount = max(
                maxStoredSampleCount,
                storedDimensions.x * storedDimensions.y * storedDimensions.z
            )
        }

        let requiredSampleCount = max(candidateCount * maxStoredSampleCount, 1)
        let macroDimensions = Self.sparseMacroGridDimensions(gridDimensions: gridDimensions)
        let macroCount = macroDimensions.x * macroDimensions.y * macroDimensions.z
        let primitiveBuffer = try Self.buffer(device: device, values: primitives)
        let sampleBuffer = try Self.gpuResidentSampleBuffer(
            device: device,
            requiredSampleCount: requiredSampleCount,
            sampleCapacityMultiplier: sampleCapacityMultiplier,
            reusing: reusableResource
        )
        let previousMetadata = reusableResource?.metadataBuffers
        let brickBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: GPUVolumeBrickDescriptor.self,
            count: candidateCount,
            reusing: previousMetadata?.brickBuffer
        )
        let attributeDescriptorBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: GPUVolumeAttributeDescriptor.self,
            count: candidateCount,
            reusing: previousMetadata?.attributeDescriptorBuffer
        )
        let gridBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: GPUVolumeBrickGrid.self,
            count: 1,
            reusing: previousMetadata?.gridBuffer
        )
        let gridIndexBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: UInt32.self,
            count: candidateCount + macroCount,
            reusing: previousMetadata?.gridIndexBuffer
        )

        var constants = GPUSparseDistanceFieldBakeConstants(
            dimensions: SIMD4<UInt32>(
                UInt32(dimensions.x),
                UInt32(dimensions.y),
                UInt32(dimensions.z),
                UInt32(candidateCount)
            ),
            gridDimensions: SIMD4<UInt32>(
                UInt32(gridDimensions.x),
                UInt32(gridDimensions.y),
                UInt32(gridDimensions.z),
                UInt32(brickSize.x)
            ),
            metadata: SIMD4<UInt32>(
                UInt32(primitives.count),
                fallbackMaterial.rawValue,
                UInt32(overlap),
                UInt32(maxStoredSampleCount)
            ),
            boundsMin: SIMD4<Float>(request.boundsMin, 0),
            extent: SIMD4<Float>(request.boundsMax - request.boundsMin, 0),
            settings: SIMD4<Float>(narrowBand, 0, 0, 0)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create direct-grid sparse distance field bake command buffer.")
        }
        encoder.setComputePipelineState(directGridBakePipeline)
        encoder.setBuffer(primitiveBuffer, offset: 0, index: 0)
        encoder.setBuffer(sampleBuffer, offset: 0, index: 1)
        encoder.setBuffer(brickBuffer, offset: 0, index: 2)
        encoder.setBuffer(attributeDescriptorBuffer, offset: 0, index: 3)
        encoder.setBuffer(gridBuffer, offset: 0, index: 4)
        encoder.setBuffer(gridIndexBuffer, offset: 0, index: 5)
        encoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 6)
        let width = min(directGridBakePipeline.maxTotalThreadsPerThreadgroup, 128)
        encoder.dispatchThreadgroups(
            MTLSize(width: candidateCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
        try encodeSparseMacroGridBuild(
            gridDimensions: gridDimensions,
            candidateCount: candidateCount,
            gridBuffer: gridBuffer,
            gridIndexBuffer: gridIndexBuffer,
            constants: &constants,
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let metadataBuffers = RenderGPUSparseFieldMetadataBuffers(
            brickBuffer: brickBuffer,
            attributeDescriptorBuffer: attributeDescriptorBuffer,
            gridBuffer: gridBuffer,
            gridIndexBuffer: gridIndexBuffer,
            brickCount: candidateCount,
            attributeDescriptorCount: candidateCount,
            gridCount: 1,
            gridIndexCount: candidateCount + macroCount
        )
        return RenderGPUSparseFieldResource(
            device: device,
            dimensions: dimensions,
            brickSize: brickSize,
            boundsMin: request.boundsMin,
            boundsMax: request.boundsMax,
            defaultDistance: max(narrowBand, 1),
            defaultMaterial: DistanceVolumeMaterialSample(materialA: fallbackMaterial),
            bricks: [],
            sampleBuffer: sampleBuffer,
            sampleCount: requiredSampleCount,
            metadataBuffers: metadataBuffers
        )
    }

    private func bakeDirectGridProgramResourceOnGPU(
        _ request: DistanceFieldBakeRequest,
        program: DistanceFieldProgram,
        brickSize requestedBrickSize: Int,
        narrowBand requestedNarrowBand: Float,
        fallbackMaterial: MaterialID,
        reusing reusableResource: RenderGPUSparseFieldResource? = nil,
        sampleCapacityMultiplier: Float = 1
    ) throws -> RenderGPUSparseFieldResource {
        guard let device,
              let commandQueue,
              let directGridBakePipeline = sparseProgramDirectGridBakePipeline else {
            throw DenrimRendererError.invalidScene("Direct-grid GPU distance field program baking requires the Metal program bake pipeline.")
        }

        let operations = try Self.gpuProgramOperations(for: program)
        let layout = Self.sparseLayout(
            resolution: request.resolution,
            requestedBrickSize: requestedBrickSize,
            sampleScale: Self.sparseSampleScale(for: request.storage)
        )
        let dimensions = layout.dimensions
        let brickSize = layout.brickSize
        let gridDimensions = SIMD3<Int>(
            (dimensions.x + brickSize.x - 1) / brickSize.x,
            (dimensions.y + brickSize.y - 1) / brickSize.y,
            (dimensions.z + brickSize.z - 1) / brickSize.z
        )
        let candidateCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
        let narrowBand = max(requestedNarrowBand, 0)
        let overlap = 2

        var maxStoredSampleCount = 1
        for candidateIndex in 0..<candidateCount {
            let cell = DistanceFieldBaker.brickCell(index: candidateIndex, gridDimensions: gridDimensions)
            let coreOrigin = SIMD3<Int>(
                cell.x * brickSize.x,
                cell.y * brickSize.y,
                cell.z * brickSize.z
            )
            let coreEnd = SIMD3<Int>(
                min(coreOrigin.x + brickSize.x, dimensions.x),
                min(coreOrigin.y + brickSize.y, dimensions.y),
                min(coreOrigin.z + brickSize.z, dimensions.z)
            )
            let storedOrigin = SIMD3<Int>(
                max(coreOrigin.x - overlap, 0),
                max(coreOrigin.y - overlap, 0),
                max(coreOrigin.z - overlap, 0)
            )
            let storedEnd = SIMD3<Int>(
                min(coreEnd.x + overlap, dimensions.x),
                min(coreEnd.y + overlap, dimensions.y),
                min(coreEnd.z + overlap, dimensions.z)
            )
            let storedDimensions = SIMD3<Int>(
                storedEnd.x - storedOrigin.x,
                storedEnd.y - storedOrigin.y,
                storedEnd.z - storedOrigin.z
            )
            maxStoredSampleCount = max(
                maxStoredSampleCount,
                storedDimensions.x * storedDimensions.y * storedDimensions.z
            )
        }

        let requiredSampleCount = max(candidateCount * maxStoredSampleCount, 1)
        let macroDimensions = Self.sparseMacroGridDimensions(gridDimensions: gridDimensions)
        let macroCount = macroDimensions.x * macroDimensions.y * macroDimensions.z
        let operationBuffer = try Self.buffer(device: device, values: operations)
        let sampleBuffer = try Self.gpuResidentSampleBuffer(
            device: device,
            requiredSampleCount: requiredSampleCount,
            sampleCapacityMultiplier: sampleCapacityMultiplier,
            reusing: reusableResource
        )
        let attributeBuffer = try Self.gpuResidentProgramAttributeSampleBuffer(
            device: device,
            requiredSampleCount: requiredSampleCount,
            program: program,
            reusing: reusableResource?.attributeSampleBuffer
        )
        let attributeArgumentBuffer = try attributeBuffer ?? Self.emptyBuffer(
            device: device,
            element: SIMD4<Float>.self,
            count: 1
        )
        let materialFieldBuffer = try Self.gpuResidentProgramMaterialFieldSampleBuffer(
            device: device,
            requiredSampleCount: requiredSampleCount,
            program: program,
            reusing: reusableResource?.materialFieldSampleBuffer
        )
        let materialFieldArgumentBuffer = try materialFieldBuffer ?? Self.emptyBuffer(
            device: device,
            element: GPUVolumeMaterialFieldSample.self,
            count: 1
        )
        var attributeLayout = Self.gpuProgramAttributeLayout(for: program)
        let previousMetadata = reusableResource?.metadataBuffers
        let brickBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: GPUVolumeBrickDescriptor.self,
            count: candidateCount,
            reusing: previousMetadata?.brickBuffer
        )
        let attributeDescriptorBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: GPUVolumeAttributeDescriptor.self,
            count: candidateCount,
            reusing: previousMetadata?.attributeDescriptorBuffer
        )
        let gridBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: GPUVolumeBrickGrid.self,
            count: 1,
            reusing: previousMetadata?.gridBuffer
        )
        let gridIndexBuffer = try Self.gpuResidentBuffer(
            device: device,
            element: UInt32.self,
            count: candidateCount + macroCount,
            reusing: previousMetadata?.gridIndexBuffer
        )

        var constants = GPUSparseDistanceFieldBakeConstants(
            dimensions: SIMD4<UInt32>(
                UInt32(dimensions.x),
                UInt32(dimensions.y),
                UInt32(dimensions.z),
                UInt32(candidateCount)
            ),
            gridDimensions: SIMD4<UInt32>(
                UInt32(gridDimensions.x),
                UInt32(gridDimensions.y),
                UInt32(gridDimensions.z),
                UInt32(brickSize.x)
            ),
            metadata: SIMD4<UInt32>(
                UInt32(operations.count),
                fallbackMaterial.rawValue,
                UInt32(overlap),
                UInt32(maxStoredSampleCount)
            ),
            boundsMin: SIMD4<Float>(request.boundsMin, 0),
            extent: SIMD4<Float>(request.boundsMax - request.boundsMin, 0),
            settings: SIMD4<Float>(narrowBand, 0, 0, 0)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create direct-grid distance field program bake command buffer.")
        }
        encoder.setComputePipelineState(directGridBakePipeline)
        encoder.setBuffer(operationBuffer, offset: 0, index: 0)
        encoder.setBuffer(sampleBuffer, offset: 0, index: 1)
        encoder.setBuffer(brickBuffer, offset: 0, index: 2)
        encoder.setBuffer(attributeDescriptorBuffer, offset: 0, index: 3)
        encoder.setBuffer(gridBuffer, offset: 0, index: 4)
        encoder.setBuffer(gridIndexBuffer, offset: 0, index: 5)
        encoder.setBytes(&constants, length: MemoryLayout<GPUSparseDistanceFieldBakeConstants>.stride, index: 6)
        encoder.setBuffer(attributeArgumentBuffer, offset: 0, index: 7)
        encoder.setBytes(&attributeLayout, length: MemoryLayout<GPUDistanceFieldProgramAttributeLayout>.stride, index: 8)
        encoder.setBuffer(materialFieldArgumentBuffer, offset: 0, index: 9)
        let width = min(directGridBakePipeline.maxTotalThreadsPerThreadgroup, 128)
        encoder.dispatchThreadgroups(
            MTLSize(width: candidateCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
        try encodeSparseMacroGridBuild(
            gridDimensions: gridDimensions,
            candidateCount: candidateCount,
            gridBuffer: gridBuffer,
            gridIndexBuffer: gridIndexBuffer,
            constants: &constants,
            into: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DenrimRendererError.commandBufferFailed(error.localizedDescription)
        }

        let metadataBuffers = RenderGPUSparseFieldMetadataBuffers(
            brickBuffer: brickBuffer,
            attributeDescriptorBuffer: attributeDescriptorBuffer,
            gridBuffer: gridBuffer,
            gridIndexBuffer: gridIndexBuffer,
            brickCount: candidateCount,
            attributeDescriptorCount: candidateCount,
            gridCount: 1,
            gridIndexCount: candidateCount + macroCount
        )
        return RenderGPUSparseFieldResource(
            device: device,
            dimensions: dimensions,
            brickSize: brickSize,
            boundsMin: request.boundsMin,
            boundsMax: request.boundsMax,
            defaultDistance: max(narrowBand, 1),
            defaultMaterial: DistanceVolumeMaterialSample(materialA: fallbackMaterial),
            bricks: [],
            sampleBuffer: sampleBuffer,
            sampleCount: requiredSampleCount,
            materialFieldSampleBuffer: materialFieldBuffer,
            materialFieldSampleCount: materialFieldBuffer == nil ? 0 : requiredSampleCount,
            attributeSampleBuffer: attributeBuffer,
            attributeSampleCount: requiredSampleCount * program.resolvedAttributeLayout.packedVectorCount,
            metadataBuffers: metadataBuffers
        )
    }

    private static func sparseVolume(
        from dense: DistanceVolume,
        brickSize requestedBrickSize: Int,
        narrowBand requestedNarrowBand: Float,
        fallbackMaterial: MaterialID
    ) throws -> SparseDistanceVolume {
        let dimensions = dense.dimensions
        let brickSize = SIMD3<Int>(repeating: max(requestedBrickSize, 1))
        let narrowBand = max(requestedNarrowBand, 0)
        let defaultDistance = max(narrowBand, 1)
        let defaultMaterial = DistanceVolumeMaterialSample(materialA: fallbackMaterial)
        let packedVectorCount = dense.attributeLayout.packedVectorCount
        let overlap = 2
        var bricks: [SparseDistanceVolumeBrick] = []

        var originZ = 0
        while originZ < dimensions.z {
            var originY = 0
            while originY < dimensions.y {
                var originX = 0
                while originX < dimensions.x {
                    let coreDimensions = SIMD3<Int>(
                        min(brickSize.x, dimensions.x - originX),
                        min(brickSize.y, dimensions.y - originY),
                        min(brickSize.z, dimensions.z - originZ)
                    )
                    let storedOrigin = SIMD3<Int>(
                        max(originX - overlap, 0),
                        max(originY - overlap, 0),
                        max(originZ - overlap, 0)
                    )
                    let storedEnd = SIMD3<Int>(
                        min(originX + coreDimensions.x + overlap, dimensions.x),
                        min(originY + coreDimensions.y + overlap, dimensions.y),
                        min(originZ + coreDimensions.z + overlap, dimensions.z)
                    )
                    let storedDimensions = SIMD3<Int>(
                        storedEnd.x - storedOrigin.x,
                        storedEnd.y - storedOrigin.y,
                        storedEnd.z - storedOrigin.z
                    )
                    let sampleCount = storedDimensions.x * storedDimensions.y * storedDimensions.z
                    var distances = [Float]()
                    var materialSamples = [DistanceVolumeMaterialSample]()
                    var attributeSamples = [SIMD4<Float>]()
                    var packedSamples = [PackedDistanceVolumeSample]()
                    distances.reserveCapacity(sampleCount)
                    materialSamples.reserveCapacity(sampleCount)
                    packedSamples.reserveCapacity(sampleCount)
                    if packedVectorCount > 0 {
                        attributeSamples.reserveCapacity(sampleCount * packedVectorCount)
                    }

                    var minDistance = Float.greatestFiniteMagnitude
                    var maxDistance = -Float.greatestFiniteMagnitude
                    for z in 0..<storedDimensions.z {
                        for y in 0..<storedDimensions.y {
                            for x in 0..<storedDimensions.x {
                                let sourceX = storedOrigin.x + x
                                let sourceY = storedOrigin.y + y
                                let sourceZ = storedOrigin.z + z
                                let sourceIndex = sourceX + sourceY * dimensions.x + sourceZ * dimensions.x * dimensions.y
                                let distance = dense.distances[sourceIndex]
                                minDistance = min(minDistance, distance)
                                maxDistance = max(maxDistance, distance)
                                distances.append(distance)
                                if dense.materialSamples.indices.contains(sourceIndex) {
                                    let materialSample = dense.materialSamples[sourceIndex]
                                    materialSamples.append(materialSample)
                                    packedSamples.append(PackedDistanceVolumeSample(distance: distance, material: materialSample))
                                } else {
                                    materialSamples.append(defaultMaterial)
                                    packedSamples.append(PackedDistanceVolumeSample(distance: distance, material: defaultMaterial))
                                }
                                if packedVectorCount > 0 {
                                    let attributeIndex = sourceIndex * packedVectorCount
                                    for vectorIndex in 0..<packedVectorCount {
                                        attributeSamples.append(dense.attributeSamples[attributeIndex + vectorIndex])
                                    }
                                }
                            }
                        }
                    }

                    if minDistance <= narrowBand && maxDistance >= -narrowBand {
                        bricks.append(SparseDistanceVolumeBrick(
                            origin: storedOrigin,
                            dimensions: storedDimensions,
                            coreOrigin: SIMD3<Int>(originX, originY, originZ),
                            coreDimensions: coreDimensions,
                            distances: distances,
                            materialSamples: materialSamples,
                            attributeSamples: attributeSamples,
                            packedSamples: packedSamples
                        ))
                    }

                    originX += brickSize.x
                }
                originY += brickSize.y
            }
            originZ += brickSize.z
        }

        return SparseDistanceVolume(
            dimensions: dimensions,
            brickSize: brickSize,
            boundsMin: dense.boundsMin,
            boundsMax: dense.boundsMax,
            defaultDistance: defaultDistance,
            defaultMaterial: defaultMaterial,
            attributeLayout: dense.attributeLayout,
            defaultAttributeSample: dense.attributeLayout.defaultPackedSample(),
            bricks: bricks
        )
    }

    private static func buffer<T>(device: MTLDevice, values: [T]) throws -> MTLBuffer {
        try values.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let buffer = device.makeBuffer(
                    bytes: baseAddress,
                    length: rawBuffer.count,
                    options: [.storageModeShared]
                  ) else {
                throw DenrimRendererError.commandBufferFailed("Could not allocate distance field bake buffer.")
            }
            return buffer
        }
    }

    private static func gpuProgramOperations(for program: DistanceFieldProgram) throws -> [GPUDistanceFieldProgramOperation] {
        if !program.instructions.isEmpty {
            return DistanceFieldProgramOptimizer.optimizedInstructions(program.instructions)
                .map(gpuInstructionOperation)
        }

        guard !program.operations.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field program must contain at least one operation or instruction.")
        }

        return program.operations.map { operation in
            switch operation {
            case .resetDomain:
                return GPUDistanceFieldProgramOperation(
                    metadata: SIMD4<UInt32>(1, 0, 0, 0)
                )
            case .transform(let transform):
                let localToProgram = transform.matrix
                let programToLocal = localToProgram.inverse
                return GPUDistanceFieldProgramOperation(
                    metadata: SIMD4<UInt32>(2, 0, 0, 0),
                    p0: programToLocal.columns.0,
                    p1: programToLocal.columns.1,
                    p2: programToLocal.columns.2,
                    p3: programToLocal.columns.3,
                    p4: SIMD4<Float>(distanceScale(for: localToProgram), 0, 0, 0)
                )
            case .twistY(let strength):
                return GPUDistanceFieldProgramOperation(
                    metadata: SIMD4<UInt32>(3, 0, 0, 0),
                    p0: SIMD4<Float>(strength, 0, 0, 0)
                )
            case .sphere(let radius, let material, let smoothUnionRadius, let combineOperation):
                return GPUDistanceFieldProgramOperation(
                    metadata: SIMD4<UInt32>(10, operationID(for: combineOperation), material.rawValue, 0),
                    p0: SIMD4<Float>(radius, smoothUnionRadius, 0, 0)
                )
            case .box(let halfExtents, let cornerRadius, let material, let smoothUnionRadius, let combineOperation):
                return GPUDistanceFieldProgramOperation(
                    metadata: SIMD4<UInt32>(11, operationID(for: combineOperation), material.rawValue, 0),
                    p0: SIMD4<Float>(halfExtents, cornerRadius),
                    p1: SIMD4<Float>(smoothUnionRadius, 0, 0, 0)
                )
            case .cylinder(let radius, let halfHeight, let material, let smoothUnionRadius, let combineOperation):
                return GPUDistanceFieldProgramOperation(
                    metadata: SIMD4<UInt32>(12, operationID(for: combineOperation), material.rawValue, 0),
                    p0: SIMD4<Float>(radius, halfHeight, smoothUnionRadius, 0)
                )
            }
        }
    }

    private static func gpuInstructionOperation(_ instruction: DistanceFieldProgramInstruction) -> GPUDistanceFieldProgramOperation {
        switch instruction {
        case .loadPosition(let destination):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(100, destination.rawValue, 0, 0))
        case .setFloat(let destination, let value):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(101, destination.rawValue, 0, 0),
                p0: SIMD4<Float>(value, 0, 0, 0)
            )
        case .setVector(let destination, let value):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(102, destination.rawValue, 0, 0),
                p0: SIMD4<Float>(value, 0)
            )
        case .addFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(110, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .subtractFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(111, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .multiplyFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(112, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .divideFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(113, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .negateFloat(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(114, destination.rawValue, source.rawValue, 0))
        case .minFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(115, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .maxFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(116, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .absFloat(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(117, destination.rawValue, source.rawValue, 0))
        case .sinFloat(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(118, destination.rawValue, source.rawValue, 0))
        case .cosFloat(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(119, destination.rawValue, source.rawValue, 0))
        case .clampFloat(let destination, let source, let minimum, let maximum):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(120, 0, 0, 0),
                indices: SIMD4<UInt32>(destination.rawValue, source.rawValue, minimum.rawValue, maximum.rawValue)
            )
        case .mixFloat(let destination, let lhs, let rhs, let amount):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(121, 0, 0, 0),
                indices: SIMD4<UInt32>(destination.rawValue, lhs.rawValue, rhs.rawValue, amount.rawValue)
            )
        case .smoothstep(let destination, let edge0, let edge1, let x):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(122, 0, 0, 0),
                indices: SIMD4<UInt32>(destination.rawValue, edge0.rawValue, edge1.rawValue, x.rawValue)
            )
        case .step(let destination, let edge, let x):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(123, destination.rawValue, edge.rawValue, x.rawValue)
            )
        case .saturate(let destination, let source):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(124, destination.rawValue, source.rawValue, 0)
            )
        case .fractFloat(let destination, let source):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(125, destination.rawValue, source.rawValue, 0)
            )
        case .floorFloat(let destination, let source):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(126, destination.rawValue, source.rawValue, 0)
            )
        case .modFloat(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(127, destination.rawValue, lhs.rawValue, rhs.rawValue)
            )
        case .addVector(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(130, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .subtractVector(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(131, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .multiplyVectorFloat(let destination, let source, let amount):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(132, destination.rawValue, source.rawValue, amount.rawValue))
        case .absVector(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(133, destination.rawValue, source.rawValue, 0))
        case .maxVectorFloat(let destination, let source, let value):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(134, destination.rawValue, source.rawValue, value.rawValue))
        case .minVectorFloat(let destination, let source, let value):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(135, destination.rawValue, source.rawValue, value.rawValue))
        case .composeVector(let destination, let x, let y, let z):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(136, 0, 0, 0),
                indices: SIMD4<UInt32>(destination.rawValue, x.rawValue, y.rawValue, z.rawValue)
            )
        case .extractX(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(137, destination.rawValue, source.rawValue, 0))
        case .extractY(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(138, destination.rawValue, source.rawValue, 0))
        case .extractZ(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(139, destination.rawValue, source.rawValue, 0))
        case .length(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(140, destination.rawValue, source.rawValue, 0))
        case .dot(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(145, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .normalize(let destination, let source):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(146, destination.rawValue, source.rawValue, 0))
        case .distance(let destination, let lhs, let rhs):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(147, destination.rawValue, lhs.rawValue, rhs.rawValue))
        case .valueNoise3D(let destination, let position, let scale, let seed):
            return GPUDistanceFieldProgramOperation(metadata: SIMD4<UInt32>(172, destination.rawValue, position.rawValue, scale.rawValue), indices: SIMD4<UInt32>(seed.rawValue, 0, 0, 0))
        case .fbm3D(let destination, let position, let scale, let octaves, let lacunarity, let gain, let seed):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(173, destination.rawValue, position.rawValue, scale.rawValue),
                indices: SIMD4<UInt32>(octaves.rawValue, lacunarity.rawValue, gain.rawValue, seed.rawValue)
            )
        case .cellular3D(let distance, let secondDistance, let cellID, let position, let scale, let seed):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(174, distance.rawValue, secondDistance.rawValue, cellID.rawValue),
                indices: SIMD4<UInt32>(position.rawValue, scale.rawValue, seed.rawValue, 0)
            )
        case .boxDistance(let destination, let position, let halfExtents, let cornerRadius):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(141, 0, 0, 0),
                indices: SIMD4<UInt32>(destination.rawValue, position.rawValue, halfExtents.rawValue, cornerRadius.rawValue)
            )
        case .cylinderDistance(let destination, let position, let radius, let halfHeight):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(142, 0, 0, 0),
                indices: SIMD4<UInt32>(destination.rawValue, position.rawValue, radius.rawValue, halfHeight.rawValue)
            )
        case .taperedCapsuleDistance(let destination, let position, let start, let end, let startRadius, let endRadius):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(143, destination.rawValue, position.rawValue, start.rawValue),
                indices: SIMD4<UInt32>(end.rawValue, startRadius.rawValue, endRadius.rawValue, 0)
            )
        case .splineTubeDistance(let destination, let position, let control0, let control1, let control2, let control3, let startRadius, let endRadius):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(144, destination.rawValue, position.rawValue, control0.rawValue),
                indices: SIMD4<UInt32>(control1.rawValue, control2.rawValue, control3.rawValue, startRadius.rawValue),
                p0: SIMD4<Float>(Float(endRadius.rawValue), 0, 0, 0)
            )
        case .emit(let distance, let material, let smoothUnionRadius, let combineOperation, let attributes):
            let clampedAttributes = Array(attributes.prefix(DistanceVolumeAttributeLayout.maximumChannelCount))
            var channels0 = SIMD4<UInt32>(repeating: UInt32.max)
            var registers0 = SIMD4<Float>(repeating: 0)
            var channels1 = SIMD4<Float>(repeating: Float(UInt32.max))
            var registers1 = SIMD4<Float>(repeating: 0)
            for (index, attribute) in clampedAttributes.enumerated() {
                let channel = UInt32(max(attribute.channel, 0))
                let register = Float(attribute.value.rawValue)
                if index < 4 {
                    channels0[index] = channel
                    registers0[index] = register
                } else {
                    channels1[index - 4] = Float(channel)
                    registers1[index - 4] = register
                }
            }
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(150, distance.rawValue, material.rawValue, operationID(for: combineOperation)),
                indices: channels0,
                p0: SIMD4<Float>(smoothUnionRadius, Float(clampedAttributes.count), 0, 0),
                p1: registers0,
                p2: channels1,
                p3: registers1
            )
        case .writeAttribute(let channel, let value):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(160, UInt32(max(channel, 0)), value.rawValue, 0)
            )
        case .writeMaterialField(let field, let value):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(170, field.rawValue, value.rawValue, 0)
            )
        case .writeMaterialFieldVector(let field, let value):
            return GPUDistanceFieldProgramOperation(
                metadata: SIMD4<UInt32>(171, field.rawValue, value.rawValue, 0)
            )
        }
    }

    private static func operationID(for operation: SDFPrimitiveOperation) -> UInt32 {
        operation == .subtract ? 1 : 0
    }

    private static func distanceScale(for matrix: simd_float4x4) -> Float {
        let sx = simd_length(SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z))
        let sy = simd_length(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        let sz = simd_length(SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        return max(min(sx, min(sy, sz)), 1e-6)
    }

    private static func gpuResidentSampleBuffer(
        device: MTLDevice,
        requiredSampleCount: Int,
        sampleCapacityMultiplier: Float,
        reusing reusableResource: RenderGPUSparseFieldResource?
    ) throws -> MTLBuffer {
        let requiredSampleCount = max(requiredSampleCount, 1)
        if let reusableResource,
           reusableResource.device === device,
           reusableResource.sampleCapacity >= requiredSampleCount {
            return reusableResource.sampleBuffer
        }

        let multiplier = max(sampleCapacityMultiplier, 1)
        let capacity = max(
            requiredSampleCount,
            Int(ceil(Float(requiredSampleCount) * multiplier))
        )
        return try emptyBuffer(
            device: device,
            element: GPUDistanceFieldBakeSample.self,
            count: capacity
        )
    }

    private static func gpuResidentProgramAttributeSampleBuffer(
        device: MTLDevice,
        requiredSampleCount: Int,
        program: DistanceFieldProgram,
        reusing reusableBuffer: MTLBuffer?
    ) throws -> MTLBuffer? {
        let layout = program.resolvedAttributeLayout
        let packedVectorCount = layout.packedVectorCount
        guard packedVectorCount > 0 else {
            return nil
        }
        let requiredCount = max(requiredSampleCount * packedVectorCount, 1)
        let requiredLength = MemoryLayout<SIMD4<Float>>.stride * requiredCount
        if let reusableBuffer,
           reusableBuffer.device === device,
           reusableBuffer.length >= requiredLength {
            return reusableBuffer
        }
        return try emptyBuffer(
            device: device,
            element: SIMD4<Float>.self,
            count: requiredCount
        )
    }

    private static func gpuResidentProgramMaterialFieldSampleBuffer(
        device: MTLDevice,
        requiredSampleCount: Int,
        program: DistanceFieldProgram,
        reusing reusableBuffer: MTLBuffer?
    ) throws -> MTLBuffer? {
        guard programWritesMaterialFields(program) else {
            return nil
        }
        let requiredCount = max(requiredSampleCount, 1)
        let requiredLength = MemoryLayout<GPUVolumeMaterialFieldSample>.stride * requiredCount
        if let reusableBuffer,
           reusableBuffer.device === device,
           reusableBuffer.length >= requiredLength {
            return reusableBuffer
        }
        return try emptyBuffer(
            device: device,
            element: GPUVolumeMaterialFieldSample.self,
            count: requiredCount
        )
    }

    private static func programWritesMaterialFields(_ program: DistanceFieldProgram) -> Bool {
        program.instructions.contains { instruction in
            switch instruction {
            case .writeMaterialField, .writeMaterialFieldVector:
                return true
            default:
                return false
            }
        }
    }

    private static func gpuProgramAttributeLayout(for program: DistanceFieldProgram) -> GPUDistanceFieldProgramAttributeLayout {
        let layout = program.resolvedAttributeLayout
        return GPUDistanceFieldProgramAttributeLayout(
            metadata: SIMD4<UInt32>(
                UInt32(layout.packedVectorCount),
                UInt32(layout.channelCount),
                programWritesMaterialFields(program) ? 1 : 0,
                0
            ),
            reserved0: SIMD4<UInt32>(repeating: 0),
            reserved1: SIMD4<UInt32>(repeating: 0)
        )
    }

    private static func gpuResidentBuffer<T>(
        device: MTLDevice,
        element: T.Type,
        count: Int,
        reusing reusableBuffer: MTLBuffer?
    ) throws -> MTLBuffer {
        let requiredLength = MemoryLayout<T>.stride * max(count, 1)
        if let reusableBuffer,
           reusableBuffer.device === device,
           reusableBuffer.length >= requiredLength {
            return reusableBuffer
        }
        guard let buffer = device.makeBuffer(
            length: requiredLength,
            options: [.storageModeShared]
        ) else {
            throw DenrimRendererError.commandBufferFailed("Could not allocate GPU-resident metadata buffer.")
        }
        return buffer
    }

    private static func emptyBuffer<T>(device: MTLDevice, element: T.Type, count: Int) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(
            length: MemoryLayout<T>.stride * max(count, 1),
            options: [.storageModeShared]
        ) else {
            throw DenrimRendererError.commandBufferFailed("Could not allocate distance field bake output buffer.")
        }
        return buffer
    }

    private static func brickCell(index: Int, gridDimensions: SIMD3<Int>) -> SIMD3<Int> {
        let xy = gridDimensions.x * gridDimensions.y
        let z = index / xy
        let remainder = index - z * xy
        let y = remainder / gridDimensions.x
        let x = remainder - y * gridDimensions.x
        return SIMD3<Int>(x, y, z)
    }
}

private struct GPUDistanceFieldBakeConstants {
    var dimensions: SIMD4<UInt32>
    var boundsMin: SIMD4<Float>
    var extent: SIMD4<Float>
    var metadata: SIMD4<UInt32>
}

private struct GPUDistanceFieldBakePrimitive {
    var worldToPrimitive0: SIMD4<Float>
    var worldToPrimitive1: SIMD4<Float>
    var worldToPrimitive2: SIMD4<Float>
    var worldToPrimitive3: SIMD4<Float>
    var parameters: SIMD4<Float>
    var metadata: SIMD4<UInt32>
    var controls: SIMD4<Float>

    init(_ primitive: SDFPrimitive) {
        let worldToPrimitive = primitive.transform.matrix.inverse
        self.worldToPrimitive0 = worldToPrimitive.columns.0
        self.worldToPrimitive1 = worldToPrimitive.columns.1
        self.worldToPrimitive2 = worldToPrimitive.columns.2
        self.worldToPrimitive3 = worldToPrimitive.columns.3
        let shapeID: UInt32
        let parameters: SIMD4<Float>
        switch primitive.shape {
        case .sphere(let radius):
            shapeID = 1
            parameters = SIMD4<Float>(radius, 0, 0, 0)
        case .box(let halfExtents, let cornerRadius):
            shapeID = 2
            parameters = SIMD4<Float>(halfExtents, cornerRadius)
        case .cylinder(let radius, let halfHeight):
            shapeID = 3
            parameters = SIMD4<Float>(radius, halfHeight, 0, 0)
        }
        let operationID: UInt32 = primitive.operation == .subtract ? 1 : 0
        self.parameters = parameters
        self.metadata = SIMD4<UInt32>(
            shapeID,
            operationID,
            primitive.material.rawValue,
            0
        )
        self.controls = SIMD4<Float>(
            primitive.smoothUnionRadius,
            Self.distanceScale(for: primitive.transform.matrix),
            0,
            0
        )
    }

    private static func distanceScale(for matrix: simd_float4x4) -> Float {
        let sx = simd_length(SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z))
        let sy = simd_length(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        let sz = simd_length(SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        return max(min(sx, min(sy, sz)), 1e-6)
    }
}

private struct GPUDistanceFieldProgramOperation {
    var metadata: SIMD4<UInt32>
    var indices: SIMD4<UInt32>
    var p0: SIMD4<Float>
    var p1: SIMD4<Float>
    var p2: SIMD4<Float>
    var p3: SIMD4<Float>
    var p4: SIMD4<Float>

    init(
        metadata: SIMD4<UInt32>,
        indices: SIMD4<UInt32> = SIMD4<UInt32>(repeating: 0),
        p0: SIMD4<Float> = SIMD4<Float>(repeating: 0),
        p1: SIMD4<Float> = SIMD4<Float>(repeating: 0),
        p2: SIMD4<Float> = SIMD4<Float>(repeating: 0),
        p3: SIMD4<Float> = SIMD4<Float>(repeating: 0),
        p4: SIMD4<Float> = SIMD4<Float>(repeating: 0)
    ) {
        self.metadata = metadata
        self.indices = indices
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
        self.p4 = p4
    }
}

private struct GPUDistanceFieldProgramAttributeLayout {
    var metadata: SIMD4<UInt32>
    var reserved0: SIMD4<UInt32>
    var reserved1: SIMD4<UInt32>
}

private struct GPUDistanceFieldBakeSample {
    var distance: Float
    var materialA: UInt32
    var materialB: UInt32
    var blend: Float
}

private struct GPUSparseDistanceFieldBakeConstants {
    var dimensions: SIMD4<UInt32>
    var gridDimensions: SIMD4<UInt32>
    var metadata: SIMD4<UInt32>
    var boundsMin: SIMD4<Float>
    var extent: SIMD4<Float>
    var settings: SIMD4<Float>
}

private struct GPUSparseBrickClassification {
    var metadata: SIMD4<UInt32>
}

private struct GPUSparseBrickBakeRecord {
    var originAndSampleOffset: SIMD4<UInt32>
    var dimensionsAndSampleCount: SIMD4<UInt32>
    var coreOrigin: SIMD4<UInt32>
    var coreDimensions: SIMD4<UInt32>
}
