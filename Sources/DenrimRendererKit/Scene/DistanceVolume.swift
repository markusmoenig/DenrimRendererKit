import Foundation
import simd

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
        boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1),
        boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) {
        self.dimensions = SIMD3<Int>(width, height, depth)
        self.distances = distances
        self.materialSamples = materialSamples
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

    /// Creates a sparse signed-distance brick.
    public init(
        origin: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        coreOrigin: SIMD3<Int>? = nil,
        coreDimensions: SIMD3<Int>? = nil,
        distances: [Float],
        materialSamples: [DistanceVolumeMaterialSample]
    ) {
        self.origin = origin
        self.dimensions = dimensions
        self.coreOrigin = coreOrigin ?? origin
        self.coreDimensions = coreDimensions ?? dimensions
        self.distances = distances
        self.materialSamples = materialSamples
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
        bricks: [SparseDistanceVolumeBrick]
    ) {
        self.dimensions = dimensions
        self.brickSize = brickSize
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.defaultDistance = defaultDistance
        self.defaultMaterial = defaultMaterial
        self.bricks = bricks
    }

    /// Expands the sparse representation into a dense volume.
    public func denseVolume() -> DistanceVolume {
        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        var distances = [Float](repeating: defaultDistance, count: sampleCount)
        var materialSamples = [DistanceVolumeMaterialSample](repeating: defaultMaterial, count: sampleCount)

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
            boundsMin: boundsMin,
            boundsMax: boundsMax
        )
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
