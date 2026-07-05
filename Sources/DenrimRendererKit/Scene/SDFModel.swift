import Foundation
import simd

/// A primitive shape that can be baked into a dense signed-distance volume.
public enum SDFPrimitiveShape: Sendable, Equatable {
    /// Sphere centered at the primitive origin.
    case sphere(radius: Float)

    /// Rounded box centered at the primitive origin.
    case box(halfExtents: SIMD3<Float>, cornerRadius: Float = 0)

    /// Capped cylinder centered at the primitive origin and aligned to local Y.
    case cylinder(radius: Float, halfHeight: Float)
}

/// Boolean operation used when a primitive is combined with previous primitives.
public enum SDFPrimitiveOperation: Sendable, Equatable {
    /// Adds the primitive to the current field.
    case union

    /// Subtracts the primitive from the current field.
    case subtract
}

/// One SDF primitive in a model-space composition.
public struct SDFPrimitive: Sendable, Equatable {
    /// Primitive shape evaluated in primitive-local space.
    public var shape: SDFPrimitiveShape

    /// Material assigned to this primitive.
    public var material: MaterialID

    /// Optional baked material channels contributed by this primitive.
    public var materialFields: DistanceVolumeMaterialFields

    /// Optional compact attributes contributed by this primitive.
    public var attributes: DistanceVolumeAttributeValues

    /// Primitive-local to model-space transform.
    public var transform: Transform

    /// Smooth-union radius used when this primitive is combined with previous primitives.
    public var smoothUnionRadius: Float

    /// Boolean operation used to combine this primitive with previous primitives.
    public var operation: SDFPrimitiveOperation

    /// Creates an SDF primitive.
    public init(
        shape: SDFPrimitiveShape,
        material: MaterialID,
        materialFields: DistanceVolumeMaterialFields = DistanceVolumeMaterialFields(),
        attributes: DistanceVolumeAttributeValues = DistanceVolumeAttributeValues(),
        transform: Transform = .identity,
        smoothUnionRadius: Float = 0,
        operation: SDFPrimitiveOperation = .union
    ) {
        self.shape = shape
        self.material = material
        self.materialFields = materialFields
        self.attributes = attributes
        self.transform = transform
        self.smoothUnionRadius = smoothUnionRadius
        self.operation = operation
    }
}

/// A small authoring representation for compiling many SDF primitives into one dense field.
public struct SDFModel: Sendable, Equatable {
    /// Primitives composed in order.
    public var primitives: [SDFPrimitive]

    /// Compact attributes baked by this model.
    public var attributeLayout: DistanceVolumeAttributeLayout

    /// Creates an SDF model.
    public init(
        primitives: [SDFPrimitive] = [],
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout()
    ) {
        self.primitives = primitives
        self.attributeLayout = attributeLayout
    }

    /// Appends a primitive.
    public mutating func add(_ primitive: SDFPrimitive) {
        primitives.append(primitive)
    }
}

/// Dense SDF compilation settings.
public struct DistanceVolumeBuildSettings: Sendable, Equatable {
    /// Number of samples along each axis.
    public var dimensions: SIMD3<Int>

    /// Minimum model-space bound.
    public var boundsMin: SIMD3<Float>

    /// Maximum model-space bound.
    public var boundsMax: SIMD3<Float>

    /// Creates dense SDF build settings.
    public init(
        dimensions: SIMD3<Int>,
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>
    ) {
        self.dimensions = dimensions
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
    }

    /// Creates cubic dense SDF build settings.
    public init(
        resolution: Int,
        boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1),
        boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) {
        self.init(
            dimensions: SIMD3<Int>(repeating: max(resolution, 2)),
            boundsMin: boundsMin,
            boundsMax: boundsMax
        )
    }
}

/// Sparse SDF compilation settings.
public struct SparseDistanceVolumeBuildSettings: Sendable, Equatable {
    /// Dense grid settings used for sample coordinates and full-volume bounds.
    public var denseSettings: DistanceVolumeBuildSettings

    /// Target brick size in sample coordinates.
    public var brickSize: SIMD3<Int>

    /// Signed-distance band that keeps bricks near a possible surface.
    public var narrowBand: Float

    /// Creates sparse SDF build settings.
    public init(
        denseSettings: DistanceVolumeBuildSettings,
        brickSize: SIMD3<Int> = SIMD3<Int>(repeating: 8),
        narrowBand: Float = 0.1
    ) {
        self.denseSettings = denseSettings
        self.brickSize = SIMD3<Int>(
            max(brickSize.x, 1),
            max(brickSize.y, 1),
            max(brickSize.z, 1)
        )
        self.narrowBand = max(narrowBand, 0)
    }

    /// Creates cubic sparse SDF build settings.
    public init(
        resolution: Int,
        brickSize: Int = 8,
        boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1),
        boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 1),
        narrowBand: Float = 0.1
    ) {
        self.init(
            denseSettings: DistanceVolumeBuildSettings(
                resolution: resolution,
                boundsMin: boundsMin,
                boundsMax: boundsMax
            ),
            brickSize: SIMD3<Int>(repeating: max(brickSize, 1)),
            narrowBand: narrowBand
        )
    }
}

/// Dense SDF compiler for the first material-aware volume path.
public enum DistanceVolumeBuilder {
    /// Compiles an SDF model into one dense distance volume.
    public static func build(model: SDFModel, settings: DistanceVolumeBuildSettings) throws -> DistanceVolume {
        let dimensions = try validatedDimensions(model: model, settings: settings)

        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        var distances = [Float](repeating: Float.greatestFiniteMagnitude, count: sampleCount)
        var materialSamples = [DistanceVolumeMaterialSample](
            repeating: DistanceVolumeMaterialSample(materialA: model.primitives[0].material),
            count: sampleCount
        )
        let packedVectorCount = model.attributeLayout.packedVectorCount
        var attributeSamples = [SIMD4<Float>]()
        if packedVectorCount > 0 {
            let defaultPacked = model.attributeLayout.defaultPackedSample()
            attributeSamples.reserveCapacity(sampleCount * packedVectorCount)
            for _ in 0..<sampleCount {
                attributeSamples.append(contentsOf: defaultPacked)
            }
        }

        let extent = settings.boundsMax - settings.boundsMin
        let compiledPrimitives = compiledPrimitives(for: model)

        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    let position = samplePosition(
                        x: x,
                        y: y,
                        z: z,
                        dimensions: dimensions,
                        boundsMin: settings.boundsMin,
                        extent: extent
                    )
                    let index = x + y * dimensions.x + z * dimensions.x * dimensions.y
                    let field = sampleField(
                        compiledPrimitives,
                        at: position,
                        fallbackMaterial: model.primitives[0].material
                    )

                    distances[index] = field.distance
                    materialSamples[index] = materialSample(from: field)
                    if packedVectorCount > 0 {
                        let packedAttributes = packedAttributeSample(values: field.attributes, layout: model.attributeLayout)
                        let attributeIndex = index * packedVectorCount
                        for vectorIndex in 0..<packedVectorCount {
                            attributeSamples[attributeIndex + vectorIndex] = packedAttributes[vectorIndex]
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
            attributeLayout: model.attributeLayout,
            attributeSamples: attributeSamples,
            boundsMin: settings.boundsMin,
            boundsMax: settings.boundsMax
        )
    }

    /// Compiles an SDF model into occupied sparse bricks.
    public static func buildSparse(
        model: SDFModel,
        settings: SparseDistanceVolumeBuildSettings
    ) throws -> SparseDistanceVolume {
        let denseSettings = settings.denseSettings
        let dimensions = try validatedDimensions(model: model, settings: denseSettings)
        let brickSize = SIMD3<Int>(
            max(settings.brickSize.x, 1),
            max(settings.brickSize.y, 1),
            max(settings.brickSize.z, 1)
        )
        let extent = denseSettings.boundsMax - denseSettings.boundsMin
        let compiledPrimitives = compiledPrimitives(for: model)
        let fallbackMaterial = model.primitives[0].material
        let defaultMaterial = DistanceVolumeMaterialSample(materialA: fallbackMaterial)
        let defaultDistance = max(settings.narrowBand, 1)
        let band = settings.narrowBand

        var bricks: [SparseDistanceVolumeBrick] = []
        bricks.reserveCapacity(
            ((dimensions.x + brickSize.x - 1) / brickSize.x)
                * ((dimensions.y + brickSize.y - 1) / brickSize.y)
                * ((dimensions.z + brickSize.z - 1) / brickSize.z)
        )

        var originZ = 0
        while originZ < dimensions.z {
            var originY = 0
            while originY < dimensions.y {
                var originX = 0
                while originX < dimensions.x {
                    let brickDimensions = SIMD3<Int>(
                        min(brickSize.x, dimensions.x - originX),
                        min(brickSize.y, dimensions.y - originY),
                        min(brickSize.z, dimensions.z - originZ)
                    )
                    let overlap = 2
                    let storedOrigin = SIMD3<Int>(
                        max(originX - overlap, 0),
                        max(originY - overlap, 0),
                        max(originZ - overlap, 0)
                    )
                    let storedEnd = SIMD3<Int>(
                        min(originX + brickDimensions.x + overlap, dimensions.x),
                        min(originY + brickDimensions.y + overlap, dimensions.y),
                        min(originZ + brickDimensions.z + overlap, dimensions.z)
                    )
                    let storedDimensions = SIMD3<Int>(
                        storedEnd.x - storedOrigin.x,
                        storedEnd.y - storedOrigin.y,
                        storedEnd.z - storedOrigin.z
                    )
                    let storedSamples = sampleBrick(
                        origin: storedOrigin,
                        dimensions: storedDimensions,
                        volumeDimensions: dimensions,
                        boundsMin: denseSettings.boundsMin,
                        extent: extent,
                        primitives: compiledPrimitives,
                        fallbackMaterial: fallbackMaterial,
                        defaultDistance: defaultDistance,
                        defaultMaterial: defaultMaterial,
                        attributeLayout: model.attributeLayout
                    )
                    let minDistance = storedSamples.distances.min() ?? Float.greatestFiniteMagnitude
                    let maxDistance = storedSamples.distances.max() ?? -Float.greatestFiniteMagnitude

                    if brickIntersectsNarrowBand(minDistance: minDistance, maxDistance: maxDistance, band: band) {
                        bricks.append(SparseDistanceVolumeBrick(
                            origin: storedOrigin,
                            dimensions: storedDimensions,
                            coreOrigin: SIMD3<Int>(originX, originY, originZ),
                            coreDimensions: brickDimensions,
                            distances: storedSamples.distances,
                            materialSamples: storedSamples.materialSamples,
                            attributeSamples: storedSamples.attributeSamples
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
            boundsMin: denseSettings.boundsMin,
            boundsMax: denseSettings.boundsMax,
            defaultDistance: defaultDistance,
            defaultMaterial: defaultMaterial,
            attributeLayout: model.attributeLayout,
            defaultAttributeSample: model.attributeLayout.defaultPackedSample(),
            bricks: bricks
        )
    }

    private static func sampleBrick(
        origin: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        volumeDimensions: SIMD3<Int>,
        boundsMin: SIMD3<Float>,
        extent: SIMD3<Float>,
        primitives: [CompiledPrimitive],
        fallbackMaterial: MaterialID,
        defaultDistance: Float,
        defaultMaterial: DistanceVolumeMaterialSample,
        attributeLayout: DistanceVolumeAttributeLayout
    ) -> (distances: [Float], materialSamples: [DistanceVolumeMaterialSample], attributeSamples: [SIMD4<Float>]) {
        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        var distances = [Float](repeating: defaultDistance, count: sampleCount)
        var materialSamples = [DistanceVolumeMaterialSample](repeating: defaultMaterial, count: sampleCount)
        let packedVectorCount = attributeLayout.packedVectorCount
        var attributeSamples = [SIMD4<Float>]()
        if packedVectorCount > 0 {
            let defaultPacked = attributeLayout.defaultPackedSample()
            attributeSamples.reserveCapacity(sampleCount * packedVectorCount)
            for _ in 0..<sampleCount {
                attributeSamples.append(contentsOf: defaultPacked)
            }
        }

        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    let sampleX = origin.x + x
                    let sampleY = origin.y + y
                    let sampleZ = origin.z + z
                    let position = samplePosition(
                        x: sampleX,
                        y: sampleY,
                        z: sampleZ,
                        dimensions: volumeDimensions,
                        boundsMin: boundsMin,
                        extent: extent
                    )
                    let field = sampleField(
                        primitives,
                        at: position,
                        fallbackMaterial: fallbackMaterial
                    )
                    let index = x + y * dimensions.x + z * dimensions.x * dimensions.y
                    distances[index] = field.distance
                    materialSamples[index] = materialSample(from: field)
                    if packedVectorCount > 0 {
                        let packedAttributes = packedAttributeSample(values: field.attributes, layout: attributeLayout)
                        let attributeIndex = index * packedVectorCount
                        for vectorIndex in 0..<packedVectorCount {
                            attributeSamples[attributeIndex + vectorIndex] = packedAttributes[vectorIndex]
                        }
                    }
                }
            }
        }

        return (distances, materialSamples, attributeSamples)
    }

    private static func validatedDimensions(model: SDFModel, settings: DistanceVolumeBuildSettings) throws -> SIMD3<Int> {
        guard !model.primitives.isEmpty else {
            throw DenrimRendererError.invalidScene("SDF model must contain at least one primitive.")
        }

        let dimensions = SIMD3<Int>(
            max(settings.dimensions.x, 2),
            max(settings.dimensions.y, 2),
            max(settings.dimensions.z, 2)
        )
        guard settings.boundsMax.x > settings.boundsMin.x,
              settings.boundsMax.y > settings.boundsMin.y,
              settings.boundsMax.z > settings.boundsMin.z else {
            throw DenrimRendererError.invalidScene("SDF build bounds must have positive extent.")
        }
        return dimensions
    }

    private static func compiledPrimitives(for model: SDFModel) -> [CompiledPrimitive] {
        model.primitives.map(CompiledPrimitive.init)
    }

    private static func samplePosition(
        x: Int,
        y: Int,
        z: Int,
        dimensions: SIMD3<Int>,
        boundsMin: SIMD3<Float>,
        extent: SIMD3<Float>
    ) -> SIMD3<Float> {
        let wx = dimensions.x == 1 ? Float(0) : Float(x) / Float(dimensions.x - 1)
        let wy = dimensions.y == 1 ? Float(0) : Float(y) / Float(dimensions.y - 1)
        let wz = dimensions.z == 1 ? Float(0) : Float(z) / Float(dimensions.z - 1)
        return boundsMin + extent * SIMD3<Float>(wx, wy, wz)
    }

    private static func sampleField(
        _ primitives: [CompiledPrimitive],
        at position: SIMD3<Float>,
        fallbackMaterial: MaterialID
    ) -> SampledField {
        var field = SampledField(
            distance: Float.greatestFiniteMagnitude,
            material: fallbackMaterial,
            secondaryMaterial: fallbackMaterial,
            blend: 0,
            fields: DistanceVolumeMaterialFields(),
            attributes: DistanceVolumeAttributeValues()
        )

        for primitive in primitives {
            let primitiveDistance = primitive.distance(to: position)
            switch primitive.operation {
            case .union:
                field = combine(
                    field,
                    withDistance: primitiveDistance,
                    material: primitive.material,
                    fields: primitive.materialFields,
                    attributes: primitive.attributes,
                    smoothRadius: primitive.smoothUnionRadius
                )
            case .subtract:
                if field.distance.isFinite {
                    field.distance = max(field.distance, -primitiveDistance)
                }
            }
        }

        return field
    }

    private static func materialSample(from field: SampledField) -> DistanceVolumeMaterialSample {
        DistanceVolumeMaterialSample(
            materialA: field.material,
            materialB: field.secondaryMaterial,
            blend: field.blend,
            fields: field.fields
        )
    }

    private static func brickIntersectsNarrowBand(minDistance: Float, maxDistance: Float, band: Float) -> Bool {
        minDistance <= band && maxDistance >= -band
    }

    private static func combine(
        _ current: SampledField,
        withDistance candidateDistance: Float,
        material candidateMaterial: MaterialID,
        fields candidateFields: DistanceVolumeMaterialFields,
        attributes candidateAttributes: DistanceVolumeAttributeValues,
        smoothRadius: Float
    ) -> SampledField {
        guard current.distance.isFinite else {
            return SampledField(
                distance: candidateDistance,
                material: candidateMaterial,
                secondaryMaterial: candidateMaterial,
                blend: 0,
                fields: candidateFields,
                attributes: candidateAttributes
            )
        }

        let radius = max(smoothRadius, 0)
        guard radius > 1e-6 else {
            if candidateDistance < current.distance {
                return SampledField(
                    distance: candidateDistance,
                    material: candidateMaterial,
                    secondaryMaterial: candidateMaterial,
                    blend: 0,
                    fields: candidateFields,
                    attributes: candidateAttributes
                )
            }
            return current
        }

        let h = simd_clamp(0.5 + 0.5 * (candidateDistance - current.distance) / radius, 0, 1)
        let distance = mix(candidateDistance, current.distance, t: h) - radius * h * (1 - h)
        let candidateWeight = 1 - h
        if candidateWeight <= 0.001 {
            return SampledField(
                distance: distance,
                material: current.material,
                secondaryMaterial: current.secondaryMaterial,
                blend: current.blend,
                fields: current.fields,
                attributes: current.attributes
            )
        }
        if candidateWeight >= 0.999 {
            return SampledField(
                distance: distance,
                material: candidateMaterial,
                secondaryMaterial: candidateMaterial,
                blend: 0,
                fields: candidateFields,
                attributes: candidateAttributes
            )
        }
        return SampledField(
            distance: distance,
            material: current.material,
            secondaryMaterial: candidateMaterial,
            blend: candidateWeight,
            fields: blendMaterialFields(current.fields, candidateFields, t: candidateWeight),
            attributes: blendAttributeValues(current.attributes, candidateAttributes, t: candidateWeight)
        )
    }

    private static func mix(_ lhs: Float, _ rhs: Float, t: Float) -> Float {
        lhs + (rhs - lhs) * t
    }

    private static func blendMaterialFields(
        _ lhs: DistanceVolumeMaterialFields,
        _ rhs: DistanceVolumeMaterialFields,
        t: Float
    ) -> DistanceVolumeMaterialFields {
        DistanceVolumeMaterialFields(
            baseColor: mix(lhs.baseColor, rhs.baseColor, t: t),
            opacity: mix(lhs.opacity, rhs.opacity, t: t),
            emission: mix(lhs.emission, rhs.emission, t: t),
            roughness: mix(lhs.roughness, rhs.roughness, t: t),
            metallic: mix(lhs.metallic, rhs.metallic, t: t),
            transmission: mix(lhs.transmission, rhs.transmission, t: t)
        )
    }

    private static func mix(_ lhs: Float?, _ rhs: Float?, t: Float) -> Float? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return mix(lhs, rhs, t: t)
        case let (.some(lhs), .none):
            return t < 0.5 ? lhs : nil
        case let (.none, .some(rhs)):
            return t >= 0.5 ? rhs : nil
        case (.none, .none):
            return nil
        }
    }

    private static func mix(_ lhs: SIMD3<Float>?, _ rhs: SIMD3<Float>?, t: Float) -> SIMD3<Float>? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return lhs + (rhs - lhs) * t
        case let (.some(lhs), .none):
            return t < 0.5 ? lhs : nil
        case let (.none, .some(rhs)):
            return t >= 0.5 ? rhs : nil
        case (.none, .none):
            return nil
        }
    }

    private static func blendAttributeValues(
        _ lhs: DistanceVolumeAttributeValues,
        _ rhs: DistanceVolumeAttributeValues,
        t: Float
    ) -> DistanceVolumeAttributeValues {
        var keys = Set(lhs.values.keys)
        keys.formUnion(rhs.values.keys)
        var values: [String: Float] = [:]
        for key in keys {
            switch (lhs.values[key], rhs.values[key]) {
            case let (.some(lhs), .some(rhs)):
                values[key] = mix(lhs, rhs, t: t)
            case let (.some(lhs), .none):
                if t < 0.5 {
                    values[key] = lhs
                }
            case let (.none, .some(rhs)):
                if t >= 0.5 {
                    values[key] = rhs
                }
            case (.none, .none):
                break
            }
        }
        return DistanceVolumeAttributeValues(values)
    }
}

private struct SampledField {
    var distance: Float
    var material: MaterialID
    var secondaryMaterial: MaterialID
    var blend: Float
    var fields: DistanceVolumeMaterialFields
    var attributes: DistanceVolumeAttributeValues
}

private struct CompiledPrimitive {
    var shape: SDFPrimitiveShape
    var material: MaterialID
    var materialFields: DistanceVolumeMaterialFields
    var attributes: DistanceVolumeAttributeValues
    var worldToPrimitive: simd_float4x4
    var distanceScale: Float
    var smoothUnionRadius: Float
    var operation: SDFPrimitiveOperation

    init(_ primitive: SDFPrimitive) {
        self.shape = primitive.shape
        self.material = primitive.material
        self.materialFields = primitive.materialFields
        self.attributes = primitive.attributes
        self.worldToPrimitive = primitive.transform.matrix.inverse
        self.distanceScale = Self.distanceScale(for: primitive.transform.matrix)
        self.smoothUnionRadius = primitive.smoothUnionRadius
        self.operation = primitive.operation
    }

    func distance(to position: SIMD3<Float>) -> Float {
        let local4 = worldToPrimitive * SIMD4<Float>(position, 1)
        let local = SIMD3<Float>(local4.x, local4.y, local4.z)
        let distance: Float
        switch shape {
        case .sphere(let radius):
            distance = simd_length(local) - radius
        case .box(let halfExtents, let cornerRadius):
            let q = simd_abs(local) - halfExtents
            distance = simd_length(simd_max(q, SIMD3<Float>(repeating: 0)))
                + min(max(q.x, max(q.y, q.z)), 0)
                - max(cornerRadius, 0)
        case .cylinder(let radius, let halfHeight):
            let d = SIMD2<Float>(
                simd_length(SIMD2<Float>(local.x, local.z)),
                abs(local.y)
            ) - SIMD2<Float>(radius, halfHeight)
            distance = min(max(d.x, d.y), 0)
                + simd_length(simd_max(d, SIMD2<Float>(repeating: 0)))
        }
        return distance * distanceScale
    }

    private static func distanceScale(for matrix: simd_float4x4) -> Float {
        let sx = simd_length(SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z))
        let sy = simd_length(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        let sz = simd_length(SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        return max(min(sx, min(sy, sz)), 1e-6)
    }
}
