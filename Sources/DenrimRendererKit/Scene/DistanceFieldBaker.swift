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
    case sparseBricks(brickSize: Int = 8, narrowBand: Float = 0.1)
}

/// A bakeable SDF graph.
///
/// This is intentionally close to `SDFModel` for the first public API. Products
/// such as Denrim Form can compile timeline/operator state into this graph
/// without depending on SceneScript.
public struct DistanceFieldBakeGraph: Sendable, Equatable {
    /// Primitive composition to bake.
    public var model: SDFModel

    /// Creates a bake graph from an SDF model.
    public init(model: SDFModel = SDFModel()) {
        self.model = model
    }

    /// Creates a bake graph from primitives and an optional attribute layout.
    public init(
        primitives: [SDFPrimitive],
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout()
    ) {
        self.model = SDFModel(primitives: primitives, attributeLayout: attributeLayout)
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
public struct DistanceFieldBakeResult: Sendable, Equatable {
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

    /// Creates a CPU-only baker.
    public convenience init(preferredBackend: DistanceFieldBakeBackend = .automatic) {
        self.init(
            preferredBackend: preferredBackend,
            device: nil,
            commandQueue: nil,
            pipeline: nil
        )
    }

    init(
        preferredBackend: DistanceFieldBakeBackend = .automatic,
        device: MTLDevice?,
        commandQueue: MTLCommandQueue?,
        pipeline: MTLComputePipelineState?
    ) {
        self.preferredBackend = preferredBackend
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
    }

    /// Bakes the request into a renderable field bundle.
    public func bake(_ request: DistanceFieldBakeRequest) throws -> DistanceFieldBakeResult {
        let model = request.graph.model
        guard !model.primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field bake graph must contain at least one primitive.")
        }
        let fallbackMaterial = request.fallbackMaterial ?? model.primitives[0].material
        let backend = resolvedBackend(for: request)
        let dense: DistanceVolume

        switch backend {
        case .metalCompute:
            dense = try bakeDenseOnGPU(request, fallbackMaterial: fallbackMaterial)
        case .automatic, .cpuReference:
            dense = try bakeDenseOnCPU(request)
        }

        let bundle: RenderFieldBundle
        switch request.storage {
        case .dense:
            bundle = RenderFieldBundle(dense: dense, fallbackMaterial: fallbackMaterial)
        case .sparseBricks(let brickSize, let narrowBand):
            let sparse = try Self.sparseVolume(
                from: dense,
                brickSize: brickSize,
                narrowBand: narrowBand,
                fallbackMaterial: fallbackMaterial
            )
            bundle = RenderFieldBundle(sparse: sparse, fallbackMaterial: fallbackMaterial)
        }

        return DistanceFieldBakeResult(
            bundle: bundle,
            backend: backend,
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
                    distances.reserveCapacity(sampleCount)
                    materialSamples.reserveCapacity(sampleCount)
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
                                    materialSamples.append(dense.materialSamples[sourceIndex])
                                } else {
                                    materialSamples.append(defaultMaterial)
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
                            attributeSamples: attributeSamples
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

    private static func emptyBuffer<T>(device: MTLDevice, element: T.Type, count: Int) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(
            length: MemoryLayout<T>.stride * max(count, 1),
            options: [.storageModeShared]
        ) else {
            throw DenrimRendererError.commandBufferFailed("Could not allocate distance field bake output buffer.")
        }
        return buffer
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

private struct GPUDistanceFieldBakeSample {
    var distance: Float
    var materialA: UInt32
    var materialB: UInt32
    var blend: Float
}
