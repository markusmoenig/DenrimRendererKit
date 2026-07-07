import Foundation
import Metal
import simd

/// One scalar channel in a compact volume attribute layout.
public struct DistanceVolumeAttributeChannel: Sendable, Equatable {
    public var name: String
    public var defaultValue: Float

    public init(
        name: String,
        defaultValue: Float = 0
    ) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// Compact scalar attribute layout for SDF volumes.
///
/// Samples are packed as `SIMD4<Float>` groups. For each voxel, all groups for
/// that voxel are stored consecutively, so the packed index is
/// `sampleIndex * packedVectorCount + vectorIndex`.
public struct DistanceVolumeAttributeLayout: Sendable, Equatable {
    public var channels: [DistanceVolumeAttributeChannel]

    public init(channels: [DistanceVolumeAttributeChannel] = []) {
        self.channels = Array(channels.prefix(Self.maximumChannelCount))
    }

    public var channelCount: Int {
        channels.count
    }

    public var packedVectorCount: Int {
        (channels.count + 3) / 4
    }

    public var isEmpty: Bool {
        channels.isEmpty
    }

    public func channelIndex(named name: String) -> Int? {
        channels.firstIndex { $0.name == name }
    }

    public func defaultPackedSample() -> [SIMD4<Float>] {
        packedAttributeSample(values: DistanceVolumeAttributeValues(), layout: self)
    }

    public static let maximumChannelCount = 8

}

/// Named scalar values emitted by an SDF primitive or operator.
public struct DistanceVolumeAttributeValues: Sendable, Equatable {
    public var values: [String: Float]

    public init(_ values: [String: Float] = [:]) {
        self.values = values
    }

    public subscript(_ name: String) -> Float? {
        get { values[name] }
        set { values[name] = newValue }
    }
}

public func packedAttributeSample(
    values: DistanceVolumeAttributeValues,
    layout: DistanceVolumeAttributeLayout
) -> [SIMD4<Float>] {
    guard !layout.isEmpty else {
        return []
    }

    var packed = [SIMD4<Float>](
        repeating: SIMD4<Float>(repeating: 0),
        count: layout.packedVectorCount
    )
    for (channelIndex, channel) in layout.channels.enumerated() {
        let value = values.values[channel.name] ?? channel.defaultValue
        let vectorIndex = channelIndex / 4
        let laneIndex = channelIndex % 4
        packed[vectorIndex][laneIndex] = value
    }
    return packed
}

/// Optional material channels baked alongside a signed-distance sample.
///
/// These fields are applied after the renderer resolves `materialA/materialB`,
/// so procedural SDF systems can keep a small set of base materials while
/// baking animated or generated color, opacity, transmission, and surface
/// response into the volume.
public struct DistanceVolumeMaterialFields: Sendable, Equatable {
    public var baseColor: SIMD3<Float>?
    public var opacity: Float?
    public var emission: SIMD3<Float>?
    public var roughness: Float?
    public var metallic: Float?
    public var specular: Float?
    public var transmission: Float?
    public var emissionStrength: Float?

    public init(
        baseColor: SIMD3<Float>? = nil,
        opacity: Float? = nil,
        emission: SIMD3<Float>? = nil,
        roughness: Float? = nil,
        metallic: Float? = nil,
        specular: Float? = nil,
        transmission: Float? = nil,
        emissionStrength: Float? = nil
    ) {
        self.baseColor = baseColor
        self.opacity = opacity
        self.emission = emission
        self.roughness = roughness
        self.metallic = metallic
        self.specular = specular
        self.transmission = transmission
        self.emissionStrength = emissionStrength
    }

    var flags: UInt32 {
        var value: UInt32 = 0
        if baseColor != nil { value |= Self.baseColorFlag }
        if opacity != nil { value |= Self.opacityFlag }
        if emission != nil { value |= Self.emissionFlag }
        if roughness != nil { value |= Self.roughnessFlag }
        if metallic != nil { value |= Self.metallicFlag }
        if transmission != nil { value |= Self.transmissionFlag }
        if specular != nil { value |= Self.specularFlag }
        if emissionStrength != nil { value |= Self.emissionStrengthFlag }
        return value
    }

    static let baseColorFlag: UInt32 = 1 << 0
    static let opacityFlag: UInt32 = 1 << 1
    static let emissionFlag: UInt32 = 1 << 2
    static let roughnessFlag: UInt32 = 1 << 3
    static let metallicFlag: UInt32 = 1 << 4
    static let transmissionFlag: UInt32 = 1 << 5
    static let specularFlag: UInt32 = 1 << 6
    static let emissionStrengthFlag: UInt32 = 1 << 7
}

/// Per-voxel material payload for a dense signed-distance volume.
public struct DistanceVolumeMaterialSample: Sendable, Equatable {
    /// Primary material at this sample.
    public var materialA: MaterialID

    /// Secondary material used by smooth blends.
    public var materialB: MaterialID

    /// Blend amount from `materialA` to `materialB` in the range 0...1.
    public var blend: Float

    /// Optional baked material channels evaluated at this sample.
    public var fields: DistanceVolumeMaterialFields

    /// Creates a volume material sample.
    public init(
        materialA: MaterialID,
        materialB: MaterialID? = nil,
        blend: Float = 0,
        fields: DistanceVolumeMaterialFields = DistanceVolumeMaterialFields()
    ) {
        self.materialA = materialA
        self.materialB = materialB ?? materialA
        self.blend = blend
        self.fields = fields
    }
}

/// Dense signed-distance volume data sampled in local object space.
///
/// Distances are stored in row-major X-fastest order. Negative values are inside
/// the surface, positive values are outside, and the zero crossing is rendered
/// as a surface.
public struct DistanceVolume: Sendable, Equatable {
    /// Number of samples along each local axis.
    public var dimensions: SIMD3<Int>

    /// Dense signed-distance samples in row-major X-fastest order.
    public var distances: [Float]

    /// Optional material samples in row-major X-fastest order.
    ///
    /// When empty, the scene instance material is used for the entire volume.
    public var materialSamples: [DistanceVolumeMaterialSample]

    /// Compact scalar attribute layout for per-sample procedural data.
    public var attributeLayout: DistanceVolumeAttributeLayout

    /// Packed attribute samples in row-major X-fastest order.
    public var attributeSamples: [SIMD4<Float>]

    /// Minimum local-space corner covered by the distance samples.
    public var boundsMin: SIMD3<Float>

    /// Maximum local-space corner covered by the distance samples.
    public var boundsMax: SIMD3<Float>

    /// Creates a dense signed-distance volume.
    public init(
        width: Int,
        height: Int,
        depth: Int,
        distances: [Float],
        materialSamples: [DistanceVolumeMaterialSample] = [],
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout(),
        attributeSamples: [SIMD4<Float>] = [],
        boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1),
        boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) {
        self.dimensions = SIMD3<Int>(width, height, depth)
        self.distances = distances
        self.materialSamples = materialSamples
        self.attributeLayout = attributeLayout
        self.attributeSamples = attributeSamples
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
    }

    /// Creates a dense sphere signed-distance field for tests and previews.
    public static func sphere(
        resolution: Int,
        radius: Float,
        boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1),
        boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) -> DistanceVolume {
        let clampedResolution = max(resolution, 2)
        var distances: [Float] = []
        distances.reserveCapacity(clampedResolution * clampedResolution * clampedResolution)

        for z in 0..<clampedResolution {
            for y in 0..<clampedResolution {
                for x in 0..<clampedResolution {
                    let u = SIMD3<Float>(
                        Float(x) / Float(clampedResolution - 1),
                        Float(y) / Float(clampedResolution - 1),
                        Float(z) / Float(clampedResolution - 1)
                    )
                    let position = boundsMin + (boundsMax - boundsMin) * u
                    distances.append(simd_length(position) - radius)
                }
            }
        }

        return DistanceVolume(
            width: clampedResolution,
            height: clampedResolution,
            depth: clampedResolution,
            distances: distances,
            boundsMin: boundsMin,
            boundsMax: boundsMax
        )
    }
}

/// Compact renderer-facing sample stored by sparse bricks.
///
/// This mirrors the sparse brick shader payload: distance plus material identity
/// and blend. Larger procedural material fields live in a separate optional
/// stream so ordinary sparse SDFs stay cheap to upload.
public struct PackedDistanceVolumeSample: Sendable, Equatable {
    /// Signed distance at this sample.
    public var distance: Float

    /// Primary material index at this sample.
    public var materialA: UInt32

    /// Secondary material index used by smooth blends.
    public var materialB: UInt32

    /// Blend amount from `materialA` to `materialB` in the range 0...1.
    public var materialBlend: Float

    /// Creates a compact sparse volume sample.
    public init(
        distance: Float,
        materialA: UInt32,
        materialB: UInt32,
        materialBlend: Float
    ) {
        self.distance = distance
        self.materialA = materialA
        self.materialB = materialB
        self.materialBlend = materialBlend
    }

    /// Creates a compact sparse volume sample from a material payload.
    public init(distance: Float, material: DistanceVolumeMaterialSample) {
        self.init(
            distance: distance,
            materialA: material.materialA.rawValue,
            materialB: material.materialB.rawValue,
            materialBlend: simd_clamp(material.blend, 0, 1)
        )
    }
}

/// One occupied brick in a sparse signed-distance volume.
///
/// Brick samples use the same row-major X-fastest order as `DistanceVolume`,
/// but `origin` and `dimensions` address the brick inside the full volume grid.
public struct SparseDistanceVolumeBrick: Sendable, Equatable {
    /// Sample-space origin inside the full volume grid.
    public var origin: SIMD3<Int>

    /// Number of samples stored along each axis.
    public var dimensions: SIMD3<Int>

    /// Non-overlapping sample-space origin used for traversal.
    public var coreOrigin: SIMD3<Int>

    /// Non-overlapping sample-space dimensions used for traversal.
    public var coreDimensions: SIMD3<Int>

    /// Brick-local signed-distance samples in row-major X-fastest order.
    public var distances: [Float]

    /// Brick-local material payload samples in row-major X-fastest order.
    public var materialSamples: [DistanceVolumeMaterialSample]

    /// Packed brick-local attribute samples in row-major X-fastest order.
    public var attributeSamples: [SIMD4<Float>]

    /// Compact renderer-facing samples in row-major X-fastest order.
    public var packedSamples: [PackedDistanceVolumeSample]

    /// Creates a sparse signed-distance brick.
    public init(
        origin: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        coreOrigin: SIMD3<Int>? = nil,
        coreDimensions: SIMD3<Int>? = nil,
        distances: [Float],
        materialSamples: [DistanceVolumeMaterialSample],
        attributeSamples: [SIMD4<Float>] = [],
        packedSamples: [PackedDistanceVolumeSample] = []
    ) {
        self.origin = origin
        self.dimensions = dimensions
        self.coreOrigin = coreOrigin ?? origin
        self.coreDimensions = coreDimensions ?? dimensions
        self.distances = distances
        self.materialSamples = materialSamples
        self.attributeSamples = attributeSamples
        if packedSamples.count == distances.count {
            self.packedSamples = packedSamples
        } else {
            self.packedSamples = zip(distances, materialSamples).map {
                PackedDistanceVolumeSample(distance: $0.0, material: $0.1)
            }
        }
    }
}

/// Sparse signed-distance volume data stored as occupied bricks.
///
/// This is the CPU-side build/cache representation for large SDF compositions.
/// The current renderer can validate it by converting back to a dense
/// `DistanceVolume`; a future Metal path can upload these bricks into an atlas.
public struct SparseDistanceVolume: Sendable, Equatable {
    /// Number of samples along each full-volume local axis.
    public var dimensions: SIMD3<Int>

    /// Target brick size used by the builder.
    public var brickSize: SIMD3<Int>

    /// Minimum local-space corner covered by the full distance grid.
    public var boundsMin: SIMD3<Float>

    /// Maximum local-space corner covered by the full distance grid.
    public var boundsMax: SIMD3<Float>

    /// Distance assigned to samples outside stored bricks when densified.
    public var defaultDistance: Float

    /// Material payload assigned to samples outside stored bricks when densified.
    public var defaultMaterial: DistanceVolumeMaterialSample

    /// Compact scalar attribute layout for per-sample procedural data.
    public var attributeLayout: DistanceVolumeAttributeLayout

    /// Packed attribute values assigned outside stored bricks when densified.
    public var defaultAttributeSample: [SIMD4<Float>]

    /// Stored occupied bricks.
    public var bricks: [SparseDistanceVolumeBrick]

    /// Creates a sparse signed-distance volume.
    public init(
        dimensions: SIMD3<Int>,
        brickSize: SIMD3<Int>,
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>,
        defaultDistance: Float,
        defaultMaterial: DistanceVolumeMaterialSample,
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout(),
        defaultAttributeSample: [SIMD4<Float>] = [],
        bricks: [SparseDistanceVolumeBrick]
    ) {
        self.dimensions = dimensions
        self.brickSize = brickSize
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.defaultDistance = defaultDistance
        self.defaultMaterial = defaultMaterial
        self.attributeLayout = attributeLayout
        self.defaultAttributeSample = defaultAttributeSample
        self.bricks = bricks
    }

    /// Expands the sparse representation into a dense volume.
    public func denseVolume() -> DistanceVolume {
        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        var distances = [Float](repeating: defaultDistance, count: sampleCount)
        var materialSamples = [DistanceVolumeMaterialSample](repeating: defaultMaterial, count: sampleCount)
        let packedVectorCount = attributeLayout.packedVectorCount
        let defaultAttributes = defaultAttributeSample.isEmpty
            ? attributeLayout.defaultPackedSample()
            : defaultAttributeSample
        var attributeSamples = [SIMD4<Float>]()
        if packedVectorCount > 0 {
            attributeSamples.reserveCapacity(sampleCount * packedVectorCount)
            for _ in 0..<sampleCount {
                for vectorIndex in 0..<packedVectorCount {
                    let value = vectorIndex < defaultAttributes.count
                        ? defaultAttributes[vectorIndex]
                        : SIMD4<Float>(repeating: 0)
                    attributeSamples.append(value)
                }
            }
        }

        for brick in bricks {
            for z in 0..<brick.dimensions.z {
                for y in 0..<brick.dimensions.y {
                    for x in 0..<brick.dimensions.x {
                        let sourceIndex = x + y * brick.dimensions.x + z * brick.dimensions.x * brick.dimensions.y
                        let targetX = brick.origin.x + x
                        let targetY = brick.origin.y + y
                        let targetZ = brick.origin.z + z
                        guard targetX >= 0, targetX < dimensions.x,
                              targetY >= 0, targetY < dimensions.y,
                              targetZ >= 0, targetZ < dimensions.z,
                              sourceIndex < brick.distances.count,
                              sourceIndex < brick.materialSamples.count else {
                            continue
                        }
                        let targetIndex = targetX + targetY * dimensions.x + targetZ * dimensions.x * dimensions.y
                        distances[targetIndex] = brick.distances[sourceIndex]
                        materialSamples[targetIndex] = brick.materialSamples[sourceIndex]
                        if packedVectorCount > 0 {
                            let sourceAttributeIndex = sourceIndex * packedVectorCount
                            let targetAttributeIndex = targetIndex * packedVectorCount
                            guard sourceAttributeIndex + packedVectorCount <= brick.attributeSamples.count,
                                  targetAttributeIndex + packedVectorCount <= attributeSamples.count else {
                                continue
                            }
                            for vectorIndex in 0..<packedVectorCount {
                                attributeSamples[targetAttributeIndex + vectorIndex] = brick.attributeSamples[sourceAttributeIndex + vectorIndex]
                            }
                        }
                    }
                }
            }
        }

        return DistanceVolume(
            width: dimensions.x,
            height: dimensions.y,
            depth: dimensions.z,
            distances: distances,
            materialSamples: materialSamples,
            attributeLayout: attributeLayout,
            attributeSamples: attributeSamples,
            boundsMin: boundsMin,
            boundsMax: boundsMax
        )
    }
}

/// Storage variant for a renderable SDF field bundle.
///
/// This is the renderer-facing boundary for products such as Denrim Form:
/// host apps can compile procedural geometry into either dense samples or
/// sparse bricks without depending on GPU packing details.
public struct RenderGPUSparseFieldBrick: Sendable {
    /// Sample-space origin of the stored brick payload inside the full field grid.
    public var origin: SIMD3<Int>

    /// Stored brick dimensions in samples.
    public var dimensions: SIMD3<Int>

    /// Core, non-overlap sample-space origin for grid traversal.
    public var coreOrigin: SIMD3<Int>

    /// Core, non-overlap dimensions for grid traversal.
    public var coreDimensions: SIMD3<Int>

    /// Offset, in `PackedDistanceVolumeSample` elements, into the GPU sample buffer.
    public var sampleOffset: Int

    /// Number of `PackedDistanceVolumeSample` elements stored for this brick.
    public var sampleCount: Int

    /// Minimum signed distance stored in this brick. Used for conservative render-time culling.
    public var minimumDistance: Float

    /// Maximum signed distance stored in this brick. Used for conservative render-time culling.
    public var maximumDistance: Float

    public init(
        origin: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        coreOrigin: SIMD3<Int>,
        coreDimensions: SIMD3<Int>,
        sampleOffset: Int,
        sampleCount: Int,
        minimumDistance: Float = -Float.greatestFiniteMagnitude,
        maximumDistance: Float = Float.greatestFiniteMagnitude
    ) {
        self.origin = origin
        self.dimensions = dimensions
        self.coreOrigin = coreOrigin
        self.coreDimensions = coreDimensions
        self.sampleOffset = sampleOffset
        self.sampleCount = sampleCount
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }
}

/// A GPU-to-GPU sample replacement for one existing sparse field brick.
///
/// This update keeps brick topology fixed: the target brick index, dimensions,
/// and sample count must already exist in the destination resource. Use whole
/// field replacement when an edit adds/removes occupied bricks or changes
/// brick layout.
public struct RenderGPUSparseFieldBrickUpdate {
    /// Target brick index inside `RenderGPUSparseFieldResource.bricks`.
    public var brickIndex: Int

    /// Source buffer containing packed `PackedDistanceVolumeSample` values.
    public var sourceBuffer: MTLBuffer

    /// Source byte offset inside `sourceBuffer`.
    public var sourceOffset: Int

    /// Number of packed samples to copy. Defaults to the destination brick's full sample count.
    public var sampleCount: Int?

    public init(
        brickIndex: Int,
        sourceBuffer: MTLBuffer,
        sourceOffset: Int = 0,
        sampleCount: Int? = nil
    ) {
        self.brickIndex = brickIndex
        self.sourceBuffer = sourceBuffer
        self.sourceOffset = sourceOffset
        self.sampleCount = sampleCount
    }
}

/// GPU-authored sparse brick metadata compatible with the renderer's SDF bindings.
public final class RenderGPUSparseFieldMetadataBuffers: @unchecked Sendable {
    public let brickBuffer: MTLBuffer
    public let attributeDescriptorBuffer: MTLBuffer
    public let gridBuffer: MTLBuffer
    public let gridIndexBuffer: MTLBuffer
    public let brickCount: Int
    public let attributeDescriptorCount: Int
    public let gridCount: Int
    public let gridIndexCount: Int

    public init(
        brickBuffer: MTLBuffer,
        attributeDescriptorBuffer: MTLBuffer,
        gridBuffer: MTLBuffer,
        gridIndexBuffer: MTLBuffer,
        brickCount: Int,
        attributeDescriptorCount: Int,
        gridCount: Int,
        gridIndexCount: Int
    ) {
        self.brickBuffer = brickBuffer
        self.attributeDescriptorBuffer = attributeDescriptorBuffer
        self.gridBuffer = gridBuffer
        self.gridIndexBuffer = gridIndexBuffer
        self.brickCount = brickCount
        self.attributeDescriptorCount = attributeDescriptorCount
        self.gridCount = gridCount
        self.gridIndexCount = gridIndexCount
    }
}

/// Sparse distance-field samples that already live in GPU memory.
///
/// The sample buffer must contain tightly packed `PackedDistanceVolumeSample`
/// values. RendererKit owns the shader layout; hosts should prefer resources
/// returned by `DistanceFieldBaker` unless they intentionally produce the same
/// sample layout.
public final class RenderGPUSparseFieldResource: @unchecked Sendable {
    public static let packedSampleStride = MemoryLayout<PackedDistanceVolumeSample>.stride

    public let device: MTLDevice
    public let dimensions: SIMD3<Int>
    public let brickSize: SIMD3<Int>
    public let boundsMin: SIMD3<Float>
    public let boundsMax: SIMD3<Float>
    public let defaultDistance: Float
    public let defaultMaterial: DistanceVolumeMaterialSample
    public let bricks: [RenderGPUSparseFieldBrick]
    public let sampleBuffer: MTLBuffer
    public let sampleCount: Int
    public let materialFieldSampleBuffer: MTLBuffer?
    public let materialFieldSampleCount: Int
    public let attributeSampleBuffer: MTLBuffer?
    public let attributeSampleCount: Int
    public let metadataBuffers: RenderGPUSparseFieldMetadataBuffers?

    /// Number of packed samples that fit in `sampleBuffer`.
    public var sampleCapacity: Int {
        sampleBuffer.length / Self.packedSampleStride
    }

    /// Dimensions of the sparse brick grid in field-local brick cells.
    public var brickGridDimensions: SIMD3<Int> {
        SIMD3<Int>(
            (dimensions.x + brickSize.x - 1) / brickSize.x,
            (dimensions.y + brickSize.y - 1) / brickSize.y,
            (dimensions.z + brickSize.z - 1) / brickSize.z
        )
    }

    public init(
        device: MTLDevice,
        dimensions: SIMD3<Int>,
        brickSize: SIMD3<Int>,
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>,
        defaultDistance: Float,
        defaultMaterial: DistanceVolumeMaterialSample,
        bricks: [RenderGPUSparseFieldBrick],
        sampleBuffer: MTLBuffer,
        sampleCount: Int,
        materialFieldSampleBuffer: MTLBuffer? = nil,
        materialFieldSampleCount: Int = 0,
        attributeSampleBuffer: MTLBuffer? = nil,
        attributeSampleCount: Int = 0,
        metadataBuffers: RenderGPUSparseFieldMetadataBuffers? = nil
    ) {
        self.device = device
        self.dimensions = dimensions
        self.brickSize = brickSize
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.defaultDistance = defaultDistance
        self.defaultMaterial = defaultMaterial
        self.bricks = bricks
        self.sampleBuffer = sampleBuffer
        self.sampleCount = sampleCount
        self.materialFieldSampleBuffer = materialFieldSampleBuffer
        self.materialFieldSampleCount = materialFieldSampleCount
        self.attributeSampleBuffer = attributeSampleBuffer
        self.attributeSampleCount = attributeSampleCount
        self.metadataBuffers = metadataBuffers
    }

    /// Returns direct-grid brick slots whose field-local core bounds overlap an edited region.
    ///
    /// Use this with resources produced by `bakeGPUResident(..., metadataMode: .directGridGPU)`.
    /// Geometry edits should keep `activeOnly` false so inactive slots that might become active are
    /// updated too. Material/attribute-only edits can pass `activeOnly: true` to skip currently empty
    /// slots when the active brick set is known to be unchanged.
    public func directGridBrickIndices(
        overlappingLocalBoundsMin editedBoundsMin: SIMD3<Float>,
        localBoundsMax editedBoundsMax: SIMD3<Float>,
        padding: Float = 0,
        activeOnly: Bool = false
    ) throws -> [Int] {
        let gridDimensions = brickGridDimensions
        let candidateCount = gridDimensions.x * gridDimensions.y * gridDimensions.z
        guard candidateCount > 0,
              let metadataBuffers,
              metadataBuffers.brickCount == candidateCount,
              metadataBuffers.gridIndexCount >= candidateCount else {
            throw DenrimRendererError.invalidScene("Direct-grid brick lookup requires direct-grid GPU sparse metadata.")
        }

        let padding = max(padding, 0)
        let localMin = simd_min(editedBoundsMin, editedBoundsMax) - SIMD3<Float>(repeating: padding)
        let localMax = simd_max(editedBoundsMin, editedBoundsMax) + SIMD3<Float>(repeating: padding)
        let fieldMin = simd_min(boundsMin, boundsMax)
        let fieldMax = simd_max(boundsMin, boundsMax)
        guard localMax.x >= fieldMin.x, localMax.y >= fieldMin.y, localMax.z >= fieldMin.z,
              localMin.x <= fieldMax.x, localMin.y <= fieldMax.y, localMin.z <= fieldMax.z else {
            return []
        }

        func sampleCoordinate(_ position: Float, _ minValue: Float, _ maxValue: Float, _ dimension: Int) -> Float {
            let extent = max(maxValue - minValue, Float.ulpOfOne)
            let denominator = Float(max(dimension - 1, 1))
            return ((position - minValue) / extent) * denominator
        }

        func clampedCellRange(minCoordinate: Float, maxCoordinate: Float, brickSize: Int, gridDimension: Int) -> ClosedRange<Int> {
            let brickSize = max(brickSize, 1)
            let gridDimension = max(gridDimension, 1)
            let first = Int(floor((minCoordinate - 0.5) / Float(brickSize)))
            let last = Int(floor((maxCoordinate + 0.5) / Float(brickSize)))
            let clampedFirst = max(0, min(first, gridDimension - 1))
            let clampedLast = max(0, min(last, gridDimension - 1))
            return clampedFirst...max(clampedFirst, clampedLast)
        }

        let minCoordinate = SIMD3<Float>(
            sampleCoordinate(localMin.x, fieldMin.x, fieldMax.x, dimensions.x),
            sampleCoordinate(localMin.y, fieldMin.y, fieldMax.y, dimensions.y),
            sampleCoordinate(localMin.z, fieldMin.z, fieldMax.z, dimensions.z)
        )
        let maxCoordinate = SIMD3<Float>(
            sampleCoordinate(localMax.x, fieldMin.x, fieldMax.x, dimensions.x),
            sampleCoordinate(localMax.y, fieldMin.y, fieldMax.y, dimensions.y),
            sampleCoordinate(localMax.z, fieldMin.z, fieldMax.z, dimensions.z)
        )

        let xRange = clampedCellRange(
            minCoordinate: min(minCoordinate.x, maxCoordinate.x),
            maxCoordinate: max(minCoordinate.x, maxCoordinate.x),
            brickSize: brickSize.x,
            gridDimension: gridDimensions.x
        )
        let yRange = clampedCellRange(
            minCoordinate: min(minCoordinate.y, maxCoordinate.y),
            maxCoordinate: max(minCoordinate.y, maxCoordinate.y),
            brickSize: brickSize.y,
            gridDimension: gridDimensions.y
        )
        let zRange = clampedCellRange(
            minCoordinate: min(minCoordinate.z, maxCoordinate.z),
            maxCoordinate: max(minCoordinate.z, maxCoordinate.z),
            brickSize: brickSize.z,
            gridDimension: gridDimensions.z
        )

        let activeGrid = activeOnly
            ? metadataBuffers.gridIndexBuffer.contents().bindMemory(to: UInt32.self, capacity: metadataBuffers.gridIndexCount)
            : nil
        var result: [Int] = []
        result.reserveCapacity(xRange.count * yRange.count * zRange.count)
        for z in zRange {
            for y in yRange {
                for x in xRange {
                    let brickIndex = x + y * gridDimensions.x + z * gridDimensions.x * gridDimensions.y
                    if let activeGrid, activeGrid[brickIndex] == UInt32.max {
                        continue
                    }
                    result.append(brickIndex)
                }
            }
        }
        return result
    }

    /// Encodes GPU-to-GPU replacement of existing brick sample ranges.
    ///
    /// This is the dirty-brick path for same-topology edits. The caller owns
    /// command-buffer ordering, so Form can encode its bake kernels, then these
    /// copies, then the renderer sample in one frame.
    public func encodeReplaceBrickSamples(
        _ updates: [RenderGPUSparseFieldBrickUpdate],
        into commandBuffer: MTLCommandBuffer
    ) throws {
        guard !updates.isEmpty else {
            return
        }
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw DenrimRendererError.commandBufferFailed("Could not create GPU sparse field update blit encoder.")
        }
        do {
            for update in updates {
                guard bricks.indices.contains(update.brickIndex) else {
                    throw DenrimRendererError.invalidScene("GPU sparse field dirty brick index is out of range.")
                }
                guard update.sourceBuffer.device === device else {
                    throw DenrimRendererError.invalidScene("GPU sparse field dirty brick source buffer belongs to a different Metal device.")
                }
                let brick = bricks[update.brickIndex]
                let copiedSamples = update.sampleCount ?? brick.sampleCount
                guard copiedSamples >= 0, copiedSamples <= brick.sampleCount else {
                    throw DenrimRendererError.invalidScene("GPU sparse field dirty brick sample count exceeds the destination brick.")
                }
                let byteCount = copiedSamples * Self.packedSampleStride
                let destinationOffset = brick.sampleOffset * Self.packedSampleStride
                guard update.sourceOffset >= 0,
                      update.sourceOffset + byteCount <= update.sourceBuffer.length,
                      destinationOffset + byteCount <= sampleBuffer.length else {
                    throw DenrimRendererError.invalidScene("GPU sparse field dirty brick copy range is outside its buffer.")
                }
                guard byteCount > 0 else {
                    continue
                }
                blitEncoder.copy(
                    from: update.sourceBuffer,
                    sourceOffset: update.sourceOffset,
                    to: sampleBuffer,
                    destinationOffset: destinationOffset,
                    size: byteCount
                )
            }
        } catch {
            blitEncoder.endEncoding()
            throw error
        }
        blitEncoder.endEncoding()
    }
}

public enum RenderFieldStorage: Sendable {
    /// Dense row-major signed-distance samples.
    case dense(DistanceVolume)

    /// Sparse signed-distance bricks.
    case sparse(SparseDistanceVolume)

    /// Sparse signed-distance bricks whose sample payload already lives on the GPU.
    case gpuSparse(RenderGPUSparseFieldResource)

    /// Bounds covered by the field in bundle-local space.
    public var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        switch self {
        case .dense(let volume):
            return (volume.boundsMin, volume.boundsMax)
        case .sparse(let volume):
            return (volume.boundsMin, volume.boundsMax)
        case .gpuSparse(let resource):
            return (resource.boundsMin, resource.boundsMax)
        }
    }

    /// Compact scalar attribute layout stored alongside the field.
    public var attributeLayout: DistanceVolumeAttributeLayout {
        switch self {
        case .dense(let volume):
            return volume.attributeLayout
        case .sparse(let volume):
            return volume.attributeLayout
        case .gpuSparse:
            return DistanceVolumeAttributeLayout()
        }
    }
}

/// Storage family for a render field currently stored in a scene.
public enum RenderFieldStorageKind: Sendable, Hashable {
    /// Dense row-major signed-distance samples.
    case dense

    /// Sparse signed-distance bricks.
    case sparse

    /// GPU-resident sparse signed-distance bricks.
    case gpuSparse
}

/// Stable-enough scene handle returned when a render field bundle is added.
///
/// The handle records which scene collection owns the field plus that
/// collection index. It is intended for short-lived editor sessions where the
/// app owns scene rebuilding and can discard handles when it rebuilds a scene.
public struct RenderFieldID: Sendable, Hashable {
    /// Storage family for the scene field.
    public var storage: RenderFieldStorageKind

    /// Index inside the matching scene field collection.
    public var index: Int

    /// Creates a render field handle.
    public init(storage: RenderFieldStorageKind, index: Int) {
        self.storage = storage
        self.index = index
    }
}

/// A renderable SDF field bundle compiled by a host product.
///
/// `RenderFieldBundle` is the intended API boundary between procedural editors
/// like Denrim Form and RendererKit. Form owns its timeline/operator document;
/// RendererKit owns this renderable payload shape and how it is uploaded to the
/// active backend.
public struct RenderFieldBundle: Sendable {
    /// Dense or sparse field storage.
    public var storage: RenderFieldStorage

    /// Fallback material for samples or regions that do not provide a material payload.
    public var fallbackMaterial: MaterialID

    /// Optional hit-time material program evaluated after an SDF surface hit.
    public var materialProgram: DistanceFieldMaterialProgram?

    /// Creates a field bundle from dense or sparse storage.
    public init(
        storage: RenderFieldStorage,
        fallbackMaterial: MaterialID,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.storage = storage
        self.fallbackMaterial = fallbackMaterial
        self.materialProgram = materialProgram
    }

    /// Creates a field bundle from a dense signed-distance volume.
    public init(
        dense volume: DistanceVolume,
        fallbackMaterial: MaterialID,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.init(storage: .dense(volume), fallbackMaterial: fallbackMaterial, materialProgram: materialProgram)
    }

    /// Creates a field bundle from a sparse signed-distance volume.
    public init(
        sparse volume: SparseDistanceVolume,
        fallbackMaterial: MaterialID,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.init(storage: .sparse(volume), fallbackMaterial: fallbackMaterial, materialProgram: materialProgram)
    }

    /// Creates a field bundle from GPU-resident sparse signed-distance bricks.
    public init(
        gpuSparse resource: RenderGPUSparseFieldResource,
        fallbackMaterial: MaterialID,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.init(storage: .gpuSparse(resource), fallbackMaterial: fallbackMaterial, materialProgram: materialProgram)
    }

    /// Bounds covered by the field in bundle-local space.
    public var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        storage.bounds
    }

    /// Compact scalar attribute layout stored alongside the field.
    public var attributeLayout: DistanceVolumeAttributeLayout {
        storage.attributeLayout
    }
}

/// A signed-distance volume placed in a render scene.
public struct DistanceVolumeInstance: Sendable, Equatable {
    /// Volume data sampled by the renderer.
    public var volume: DistanceVolume

    /// Material used for the zero-distance surface.
    public var material: MaterialID

    /// Local-to-world transform for the volume.
    public var transform: Transform

    /// Optional hit-time material program evaluated for hits on this instance.
    public var materialProgram: DistanceFieldMaterialProgram?

    /// Creates a distance-volume instance.
    public init(
        volume: DistanceVolume,
        material: MaterialID,
        transform: Transform = .identity,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.volume = volume
        self.material = material
        self.transform = transform
        self.materialProgram = materialProgram
    }
}

/// A sparse signed-distance volume placed in a render scene.
public struct SparseDistanceVolumeInstance: Sendable, Equatable {
    /// Sparse volume data sampled by the renderer backend.
    public var volume: SparseDistanceVolume

    /// Material used as the fallback for the zero-distance surface.
    public var material: MaterialID

    /// Local-to-world transform for the volume.
    public var transform: Transform

    /// Optional hit-time material program evaluated for hits on this instance.
    public var materialProgram: DistanceFieldMaterialProgram?

    /// Creates a sparse distance-volume instance.
    public init(
        volume: SparseDistanceVolume,
        material: MaterialID,
        transform: Transform = .identity,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.volume = volume
        self.material = material
        self.transform = transform
        self.materialProgram = materialProgram
    }
}

/// A GPU-resident sparse signed-distance volume placed in a render scene.
public struct GPUSparseDistanceVolumeInstance: Sendable {
    /// GPU-resident sparse volume data sampled by the renderer backend.
    public var resource: RenderGPUSparseFieldResource

    /// Material used as the fallback for the zero-distance surface.
    public var material: MaterialID

    /// Local-to-world transform for the volume.
    public var transform: Transform

    /// Optional hit-time material program evaluated for hits on this instance.
    public var materialProgram: DistanceFieldMaterialProgram?

    public init(
        resource: RenderGPUSparseFieldResource,
        material: MaterialID,
        transform: Transform = .identity,
        materialProgram: DistanceFieldMaterialProgram? = nil
    ) {
        self.resource = resource
        self.material = material
        self.transform = transform
        self.materialProgram = materialProgram
    }
}
