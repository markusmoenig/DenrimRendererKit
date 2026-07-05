import Foundation
import simd

/// Semantic meaning for compact scalar attributes baked alongside a distance field.
public enum DistanceVolumeAttributeSemantic: UInt32, Sendable, Equatable, CaseIterable {
    case custom = 0
    case growthAge = 1
    case branchID = 2
    case curvature = 3
    case cavity = 4
    case noise = 5
    case wetness = 6
    case mossAmount = 7
    case polish = 8
    case fracture = 9
    case burnAmount = 10
}

/// One scalar channel in a compact volume attribute layout.
public struct DistanceVolumeAttributeChannel: Sendable, Equatable {
    public var name: String
    public var semantic: DistanceVolumeAttributeSemantic
    public var defaultValue: Float

    public init(
        name: String,
        semantic: DistanceVolumeAttributeSemantic = .custom,
        defaultValue: Float = 0
    ) {
        self.name = name
        self.semantic = semantic
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

    public func channelIndex(semantic: DistanceVolumeAttributeSemantic) -> Int? {
        channels.firstIndex { $0.semantic == semantic }
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
    public var transmission: Float?

    public init(
        baseColor: SIMD3<Float>? = nil,
        opacity: Float? = nil,
        emission: SIMD3<Float>? = nil,
        roughness: Float? = nil,
        metallic: Float? = nil,
        transmission: Float? = nil
    ) {
        self.baseColor = baseColor
        self.opacity = opacity
        self.emission = emission
        self.roughness = roughness
        self.metallic = metallic
        self.transmission = transmission
    }

    var flags: UInt32 {
        var value: UInt32 = 0
        if baseColor != nil { value |= Self.baseColorFlag }
        if opacity != nil { value |= Self.opacityFlag }
        if emission != nil { value |= Self.emissionFlag }
        if roughness != nil { value |= Self.roughnessFlag }
        if metallic != nil { value |= Self.metallicFlag }
        if transmission != nil { value |= Self.transmissionFlag }
        return value
    }

    static let baseColorFlag: UInt32 = 1 << 0
    static let opacityFlag: UInt32 = 1 << 1
    static let emissionFlag: UInt32 = 1 << 2
    static let roughnessFlag: UInt32 = 1 << 3
    static let metallicFlag: UInt32 = 1 << 4
    static let transmissionFlag: UInt32 = 1 << 5
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

    /// Creates a sparse signed-distance brick.
    public init(
        origin: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        coreOrigin: SIMD3<Int>? = nil,
        coreDimensions: SIMD3<Int>? = nil,
        distances: [Float],
        materialSamples: [DistanceVolumeMaterialSample],
        attributeSamples: [SIMD4<Float>] = []
    ) {
        self.origin = origin
        self.dimensions = dimensions
        self.coreOrigin = coreOrigin ?? origin
        self.coreDimensions = coreDimensions ?? dimensions
        self.distances = distances
        self.materialSamples = materialSamples
        self.attributeSamples = attributeSamples
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
public enum RenderFieldStorage: Sendable, Equatable {
    /// Dense row-major signed-distance samples.
    case dense(DistanceVolume)

    /// Sparse signed-distance bricks.
    case sparse(SparseDistanceVolume)

    /// Bounds covered by the field in bundle-local space.
    public var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        switch self {
        case .dense(let volume):
            return (volume.boundsMin, volume.boundsMax)
        case .sparse(let volume):
            return (volume.boundsMin, volume.boundsMax)
        }
    }

    /// Compact scalar attribute layout stored alongside the field.
    public var attributeLayout: DistanceVolumeAttributeLayout {
        switch self {
        case .dense(let volume):
            return volume.attributeLayout
        case .sparse(let volume):
            return volume.attributeLayout
        }
    }
}

/// Storage family for a render field currently stored in a scene.
public enum RenderFieldStorageKind: Sendable, Hashable {
    /// Dense row-major signed-distance samples.
    case dense

    /// Sparse signed-distance bricks.
    case sparse
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
public struct RenderFieldBundle: Sendable, Equatable {
    /// Dense or sparse field storage.
    public var storage: RenderFieldStorage

    /// Fallback material for samples or regions that do not provide a material payload.
    public var fallbackMaterial: MaterialID

    /// Creates a field bundle from dense or sparse storage.
    public init(
        storage: RenderFieldStorage,
        fallbackMaterial: MaterialID
    ) {
        self.storage = storage
        self.fallbackMaterial = fallbackMaterial
    }

    /// Creates a field bundle from a dense signed-distance volume.
    public init(
        dense volume: DistanceVolume,
        fallbackMaterial: MaterialID
    ) {
        self.init(storage: .dense(volume), fallbackMaterial: fallbackMaterial)
    }

    /// Creates a field bundle from a sparse signed-distance volume.
    public init(
        sparse volume: SparseDistanceVolume,
        fallbackMaterial: MaterialID
    ) {
        self.init(storage: .sparse(volume), fallbackMaterial: fallbackMaterial)
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

    /// Creates a distance-volume instance.
    public init(
        volume: DistanceVolume,
        material: MaterialID,
        transform: Transform = .identity
    ) {
        self.volume = volume
        self.material = material
        self.transform = transform
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

    /// Creates a sparse distance-volume instance.
    public init(
        volume: SparseDistanceVolume,
        material: MaterialID,
        transform: Transform = .identity
    ) {
        self.volume = volume
        self.material = material
        self.transform = transform
    }
}
