import Foundation
import simd

/// A compact procedural SDF program evaluated by RendererKit's distance-field baker.
///
/// This is the first modular authoring boundary for products such as Denrim Form:
/// Form can compile timeline/operator state into this op tape instead of requiring
/// a new RendererKit public type for every operator.
public struct DistanceFieldProgram: Sendable, Equatable {
    /// Program operations evaluated in order.
    public var operations: [DistanceFieldProgramOperation]

    /// Generic scalar/vector instructions evaluated in order.
    ///
    /// This is the preferred target for procedural products. The higher-level
    /// `operations` array is kept as a convenience layer, but Form-style modules
    /// should compile into instructions so RendererKit does not need a new public
    /// operation for every authored component.
    public var instructions: [DistanceFieldProgramInstruction]

    /// Compact attributes baked by this program.
    public var attributeLayout: DistanceVolumeAttributeLayout

    /// Creates a distance-field program from convenience operations.
    public init(
        operations: [DistanceFieldProgramOperation] = [],
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout()
    ) {
        self.operations = operations
        self.instructions = []
        self.attributeLayout = attributeLayout
    }

    /// Creates a distance-field program from generic scalar/vector instructions.
    public init(
        instructions: [DistanceFieldProgramInstruction],
        attributeLayout: DistanceVolumeAttributeLayout = DistanceVolumeAttributeLayout()
    ) {
        self.operations = []
        self.instructions = instructions
        self.attributeLayout = attributeLayout
    }

    /// Returns a semantically equivalent program with conservative instruction folding applied.
    public func optimized() -> DistanceFieldProgram {
        guard !instructions.isEmpty else {
            return self
        }
        return DistanceFieldProgram(
            instructions: DistanceFieldProgramOptimizer.optimizedInstructions(instructions),
            attributeLayout: attributeLayout
        )
    }
}

/// Scalar register used by `DistanceFieldProgramInstruction`.
public struct DistanceFieldScalarRegister: RawRepresentable, Sendable, Equatable, Hashable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Vector register used by `DistanceFieldProgramInstruction`.
public struct DistanceFieldVectorRegister: RawRepresentable, Sendable, Equatable, Hashable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Scalar attribute value attached to one emitted SDF candidate.
public struct DistanceFieldProgramAttributeBinding: Sendable, Equatable {
    public var channel: Int
    public var value: DistanceFieldScalarRegister

    public init(channel: Int, value: DistanceFieldScalarRegister) {
        self.channel = channel
        self.value = value
    }
}

/// Generic instruction for `DistanceFieldProgram`.
///
/// This is a small renderer-owned VM, not raw Metal source. It is intended to be
/// broad enough for Form modules to compile deformations, masks, and procedural
/// SDF expressions without RendererKit hardcoding every product-level operator.
public enum DistanceFieldProgramInstruction: Sendable, Equatable {
    case loadPosition(DistanceFieldVectorRegister)
    case setFloat(DistanceFieldScalarRegister, Float)
    case setVector(DistanceFieldVectorRegister, SIMD3<Float>)

    case addFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case subtractFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case multiplyFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case divideFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case negateFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case minFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case maxFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case absFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case sinFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case cosFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case clampFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case mixFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)

    case addVector(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case subtractVector(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case multiplyVectorFloat(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldScalarRegister)
    case absVector(DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case maxVectorFloat(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldScalarRegister)
    case minVectorFloat(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldScalarRegister)
    case composeVector(DistanceFieldVectorRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case extractX(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case extractY(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case extractZ(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case length(DistanceFieldScalarRegister, DistanceFieldVectorRegister)

    case boxDistance(DistanceFieldScalarRegister, position: DistanceFieldVectorRegister, halfExtents: DistanceFieldVectorRegister, cornerRadius: DistanceFieldScalarRegister)
    case cylinderDistance(DistanceFieldScalarRegister, position: DistanceFieldVectorRegister, radius: DistanceFieldScalarRegister, halfHeight: DistanceFieldScalarRegister)
    case taperedCapsuleDistance(
        DistanceFieldScalarRegister,
        position: DistanceFieldVectorRegister,
        start: DistanceFieldVectorRegister,
        end: DistanceFieldVectorRegister,
        startRadius: DistanceFieldScalarRegister,
        endRadius: DistanceFieldScalarRegister
    )
    case splineTubeDistance(
        DistanceFieldScalarRegister,
        position: DistanceFieldVectorRegister,
        control0: DistanceFieldVectorRegister,
        control1: DistanceFieldVectorRegister,
        control2: DistanceFieldVectorRegister,
        control3: DistanceFieldVectorRegister,
        startRadius: DistanceFieldScalarRegister,
        endRadius: DistanceFieldScalarRegister
    )

    case emit(
        distance: DistanceFieldScalarRegister,
        material: MaterialID,
        smoothUnionRadius: Float = 0,
        operation: SDFPrimitiveOperation = .union,
        attributes: [DistanceFieldProgramAttributeBinding] = []
    )
    case writeAttribute(channel: Int, value: DistanceFieldScalarRegister)
}

private func taperedCapsuleDistance(
    position: SIMD3<Float>,
    start: SIMD3<Float>,
    end: SIMD3<Float>,
    startRadius: Float,
    endRadius: Float
) -> Float {
    let segment = end - start
    let lengthSquared = simd_length_squared(segment)
    let t = lengthSquared > 1e-8
        ? simd_clamp(simd_dot(position - start, segment) / lengthSquared, 0, 1)
        : Float(0)
    let radius = max(startRadius + (endRadius - startRadius) * t, 0)
    return simd_length(position - (start + segment * t)) - radius
}

private func cubicBezierPoint(
    _ control0: SIMD3<Float>,
    _ control1: SIMD3<Float>,
    _ control2: SIMD3<Float>,
    _ control3: SIMD3<Float>,
    _ t: Float
) -> SIMD3<Float> {
    let oneMinusT = 1 - t
    let oneMinusT2 = oneMinusT * oneMinusT
    let t2 = t * t
    return control0 * (oneMinusT2 * oneMinusT)
        + control1 * (3 * oneMinusT2 * t)
        + control2 * (3 * oneMinusT * t2)
        + control3 * (t2 * t)
}

private func splineTubeDistance(
    position: SIMD3<Float>,
    control0: SIMD3<Float>,
    control1: SIMD3<Float>,
    control2: SIMD3<Float>,
    control3: SIMD3<Float>,
    startRadius: Float,
    endRadius: Float
) -> Float {
    let segmentCount = 16
    var bestDistance = Float.greatestFiniteMagnitude
    var previousPoint = control0
    var previousRadius = max(startRadius, 0)
    for segmentIndex in 1...segmentCount {
        let t = Float(segmentIndex) / Float(segmentCount)
        let point = cubicBezierPoint(control0, control1, control2, control3, t)
        let radius = max(startRadius + (endRadius - startRadius) * t, 0)
        bestDistance = min(
            bestDistance,
            taperedCapsuleDistance(
                position: position,
                start: previousPoint,
                end: point,
                startRadius: previousRadius,
                endRadius: radius
            )
        )
        previousPoint = point
        previousRadius = radius
    }
    return bestDistance
}

enum DistanceFieldProgramOptimizer {
    static func optimizedInstructions(_ instructions: [DistanceFieldProgramInstruction]) -> [DistanceFieldProgramInstruction] {
        var scalarConstants: [UInt32: Float] = [:]
        var vectorConstants: [UInt32: SIMD3<Float>] = [:]
        var result: [DistanceFieldProgramInstruction] = []
        result.reserveCapacity(instructions.count)

        func s(_ register: DistanceFieldScalarRegister) -> UInt32 {
            register.rawValue % 32
        }

        func v(_ register: DistanceFieldVectorRegister) -> UInt32 {
            register.rawValue % 32
        }

        func scalar(_ register: DistanceFieldScalarRegister) -> Float? {
            scalarConstants[s(register)]
        }

        func vector(_ register: DistanceFieldVectorRegister) -> SIMD3<Float>? {
            vectorConstants[v(register)]
        }

        func remember(_ register: DistanceFieldScalarRegister, _ value: Float?) {
            scalarConstants[s(register)] = value
        }

        func remember(_ register: DistanceFieldVectorRegister, _ value: SIMD3<Float>?) {
            vectorConstants[v(register)] = value
        }

        func appendSet(_ register: DistanceFieldScalarRegister, _ value: Float) {
            remember(register, value)
            result.append(.setFloat(register, value))
        }

        func appendSet(_ register: DistanceFieldVectorRegister, _ value: SIMD3<Float>) {
            remember(register, value)
            result.append(.setVector(register, value))
        }

        for instruction in instructions {
            switch instruction {
            case .loadPosition(let destination):
                remember(destination, nil)
                result.append(instruction)
            case .setFloat(let destination, let value):
                appendSet(destination, value)
            case .setVector(let destination, let value):
                appendSet(destination, value)
            case .addFloat(let destination, let lhs, let rhs):
                if let lhs = scalar(lhs), let rhs = scalar(rhs) {
                    appendSet(destination, lhs + rhs)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .subtractFloat(let destination, let lhs, let rhs):
                if let lhs = scalar(lhs), let rhs = scalar(rhs) {
                    appendSet(destination, lhs - rhs)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .multiplyFloat(let destination, let lhs, let rhs):
                if let lhs = scalar(lhs), let rhs = scalar(rhs) {
                    appendSet(destination, lhs * rhs)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .divideFloat(let destination, let lhs, let rhs):
                if let lhs = scalar(lhs), let rhs = scalar(rhs) {
                    appendSet(destination, abs(rhs) > 1e-8 ? lhs / rhs : 0)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .negateFloat(let destination, let source):
                if let source = scalar(source) {
                    appendSet(destination, -source)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .minFloat(let destination, let lhs, let rhs):
                if let lhs = scalar(lhs), let rhs = scalar(rhs) {
                    appendSet(destination, min(lhs, rhs))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .maxFloat(let destination, let lhs, let rhs):
                if let lhs = scalar(lhs), let rhs = scalar(rhs) {
                    appendSet(destination, max(lhs, rhs))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .absFloat(let destination, let source):
                if let source = scalar(source) {
                    appendSet(destination, abs(source))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .sinFloat(let destination, let source):
                if let source = scalar(source) {
                    appendSet(destination, sin(source))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .cosFloat(let destination, let source):
                if let source = scalar(source) {
                    appendSet(destination, cos(source))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .clampFloat(let destination, let source, let minimum, let maximum):
                if let source = scalar(source), let minimum = scalar(minimum), let maximum = scalar(maximum) {
                    appendSet(destination, simd_clamp(source, minimum, maximum))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .mixFloat(let destination, let lhs, let rhs, let amount):
                if let lhs = scalar(lhs), let rhs = scalar(rhs), let amount = scalar(amount) {
                    appendSet(destination, lhs + (rhs - lhs) * amount)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .addVector(let destination, let lhs, let rhs):
                if let lhs = vector(lhs), let rhs = vector(rhs) {
                    appendSet(destination, lhs + rhs)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .subtractVector(let destination, let lhs, let rhs):
                if let lhs = vector(lhs), let rhs = vector(rhs) {
                    appendSet(destination, lhs - rhs)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .multiplyVectorFloat(let destination, let source, let amount):
                if let source = vector(source), let amount = scalar(amount) {
                    appendSet(destination, source * amount)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .absVector(let destination, let source):
                if let source = vector(source) {
                    appendSet(destination, simd_abs(source))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .maxVectorFloat(let destination, let source, let value):
                if let source = vector(source), let value = scalar(value) {
                    appendSet(destination, simd_max(source, SIMD3<Float>(repeating: value)))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .minVectorFloat(let destination, let source, let value):
                if let source = vector(source), let value = scalar(value) {
                    appendSet(destination, simd_min(source, SIMD3<Float>(repeating: value)))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .composeVector(let destination, let x, let y, let z):
                if let x = scalar(x), let y = scalar(y), let z = scalar(z) {
                    appendSet(destination, SIMD3<Float>(x, y, z))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .extractX(let destination, let source):
                if let source = vector(source) {
                    appendSet(destination, source.x)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .extractY(let destination, let source):
                if let source = vector(source) {
                    appendSet(destination, source.y)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .extractZ(let destination, let source):
                if let source = vector(source) {
                    appendSet(destination, source.z)
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .length(let destination, let source):
                if let source = vector(source) {
                    appendSet(destination, simd_length(source))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .boxDistance(let destination, let source, let halfExtents, let cornerRadius):
                if let source = vector(source), let halfExtents = vector(halfExtents), let cornerRadius = scalar(cornerRadius) {
                    let q = simd_abs(source) - halfExtents
                    appendSet(
                        destination,
                        simd_length(simd_max(q, SIMD3<Float>(repeating: 0)))
                            + min(max(q.x, max(q.y, q.z)), 0)
                            - max(cornerRadius, 0)
                    )
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .cylinderDistance(let destination, let source, let radius, let halfHeight):
                if let source = vector(source), let radius = scalar(radius), let halfHeight = scalar(halfHeight) {
                    let d = SIMD2<Float>(
                        simd_length(SIMD2<Float>(source.x, source.z)),
                        abs(source.y)
                    ) - SIMD2<Float>(radius, halfHeight)
                    appendSet(destination, min(max(d.x, d.y), 0) + simd_length(simd_max(d, SIMD2<Float>(repeating: 0))))
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .taperedCapsuleDistance(let destination, let source, let start, let end, let startRadius, let endRadius):
                if let source = vector(source),
                   let start = vector(start),
                   let end = vector(end),
                   let startRadius = scalar(startRadius),
                   let endRadius = scalar(endRadius) {
                    appendSet(
                        destination,
                        taperedCapsuleDistance(
                            position: source,
                            start: start,
                            end: end,
                            startRadius: startRadius,
                            endRadius: endRadius
                        )
                    )
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .splineTubeDistance(let destination, let source, let control0, let control1, let control2, let control3, let startRadius, let endRadius):
                if let source = vector(source),
                   let control0 = vector(control0),
                   let control1 = vector(control1),
                   let control2 = vector(control2),
                   let control3 = vector(control3),
                   let startRadius = scalar(startRadius),
                   let endRadius = scalar(endRadius) {
                    appendSet(
                        destination,
                        splineTubeDistance(
                            position: source,
                            control0: control0,
                            control1: control1,
                            control2: control2,
                            control3: control3,
                            startRadius: startRadius,
                            endRadius: endRadius
                        )
                    )
                } else {
                    remember(destination, nil)
                    result.append(instruction)
                }
            case .emit:
                result.append(instruction)
            case .writeAttribute:
                result.append(instruction)
            }
        }

        return result
    }
}

/// One operation in a `DistanceFieldProgram` op tape.
public enum DistanceFieldProgramOperation: Sendable, Equatable {
    /// Resets the domain transform/deformation state used by following primitive ops.
    case resetDomain

    /// Sets a local-to-program transform for following primitive ops.
    case transform(Transform)

    /// Applies a twist deformation around Y for following primitive ops.
    ///
    /// Strength is measured in radians per program-space unit along Y.
    case twistY(strength: Float)

    /// Adds or subtracts a sphere in the current domain.
    case sphere(
        radius: Float,
        material: MaterialID,
        smoothUnionRadius: Float = 0,
        operation: SDFPrimitiveOperation = .union
    )

    /// Adds or subtracts a rounded box in the current domain.
    case box(
        halfExtents: SIMD3<Float>,
        cornerRadius: Float = 0,
        material: MaterialID,
        smoothUnionRadius: Float = 0,
        operation: SDFPrimitiveOperation = .union
    )

    /// Adds or subtracts a capped cylinder aligned to local Y in the current domain.
    case cylinder(
        radius: Float,
        halfHeight: Float,
        material: MaterialID,
        smoothUnionRadius: Float = 0,
        operation: SDFPrimitiveOperation = .union
    )
}

enum DistanceFieldProgramEvaluator {
    private static let registerCount = 32

    static func defaultMaterial(for program: DistanceFieldProgram) -> MaterialID? {
        for instruction in program.instructions {
            if case .emit(_, let material, _, _, _) = instruction {
                return material
            }
        }

        for operation in program.operations {
            switch operation {
            case .sphere(_, let material, _, _),
                 .box(_, _, let material, _, _),
                 .cylinder(_, _, let material, _, _):
                return material
            case .resetDomain, .transform, .twistY:
                continue
            }
        }
        return nil
    }

    static func sample(
        program: DistanceFieldProgram,
        at position: SIMD3<Float>,
        fallbackMaterial: MaterialID
    ) -> DistanceFieldProgramSample {
        if !program.instructions.isEmpty {
            return sampleInstructions(
                program.instructions,
                at: position,
                fallbackMaterial: fallbackMaterial
            )
        }

        var state = DomainState()
        var field = DistanceFieldProgramSample(
            distance: Float.greatestFiniteMagnitude,
            material: fallbackMaterial,
            secondaryMaterial: fallbackMaterial,
            blend: 0,
            attributes: [:]
        )

        for operation in program.operations {
            switch operation {
            case .resetDomain:
                state = DomainState()
            case .transform(let transform):
                state.localToProgram = transform.matrix
                state.programToLocal = transform.matrix.inverse
                state.distanceScale = distanceScale(for: transform.matrix)
            case .twistY(let strength):
                state.twistYStrength = strength
            case .sphere(let radius, let material, let smoothUnionRadius, let combineOperation):
                let local = state.localPosition(for: position)
                let distance = (simd_length(local) - radius) * state.distanceScale
                field = combine(field, distance: distance, material: material, attributes: [:], smoothUnionRadius: smoothUnionRadius, operation: combineOperation)
            case .box(let halfExtents, let cornerRadius, let material, let smoothUnionRadius, let combineOperation):
                let local = state.localPosition(for: position)
                let q = simd_abs(local) - halfExtents
                let distance = (
                    simd_length(simd_max(q, SIMD3<Float>(repeating: 0)))
                        + min(max(q.x, max(q.y, q.z)), 0)
                        - max(cornerRadius, 0)
                ) * state.distanceScale
                field = combine(field, distance: distance, material: material, attributes: [:], smoothUnionRadius: smoothUnionRadius, operation: combineOperation)
            case .cylinder(let radius, let halfHeight, let material, let smoothUnionRadius, let combineOperation):
                let local = state.localPosition(for: position)
                let d = SIMD2<Float>(
                    simd_length(SIMD2<Float>(local.x, local.z)),
                    abs(local.y)
                ) - SIMD2<Float>(radius, halfHeight)
                let distance = (
                    min(max(d.x, d.y), 0)
                        + simd_length(simd_max(d, SIMD2<Float>(repeating: 0)))
                ) * state.distanceScale
                field = combine(field, distance: distance, material: material, attributes: [:], smoothUnionRadius: smoothUnionRadius, operation: combineOperation)
            }
        }

        return field
    }

    private static func sampleInstructions(
        _ instructions: [DistanceFieldProgramInstruction],
        at position: SIMD3<Float>,
        fallbackMaterial: MaterialID
    ) -> DistanceFieldProgramSample {
        var scalars = [Float](repeating: 0, count: registerCount)
        var vectors = [SIMD3<Float>](repeating: .zero, count: registerCount)
        var field = DistanceFieldProgramSample(
            distance: Float.greatestFiniteMagnitude,
            material: fallbackMaterial,
            secondaryMaterial: fallbackMaterial,
            blend: 0,
            attributes: [:]
        )
        var currentAttributes: [Int: Float] = [:]

        func s(_ register: DistanceFieldScalarRegister) -> Int {
            Int(register.rawValue % UInt32(registerCount))
        }

        func v(_ register: DistanceFieldVectorRegister) -> Int {
            Int(register.rawValue % UInt32(registerCount))
        }

        for instruction in instructions {
            switch instruction {
            case .loadPosition(let destination):
                vectors[v(destination)] = position
            case .setFloat(let destination, let value):
                scalars[s(destination)] = value
            case .setVector(let destination, let value):
                vectors[v(destination)] = value
            case .addFloat(let destination, let lhs, let rhs):
                scalars[s(destination)] = scalars[s(lhs)] + scalars[s(rhs)]
            case .subtractFloat(let destination, let lhs, let rhs):
                scalars[s(destination)] = scalars[s(lhs)] - scalars[s(rhs)]
            case .multiplyFloat(let destination, let lhs, let rhs):
                scalars[s(destination)] = scalars[s(lhs)] * scalars[s(rhs)]
            case .divideFloat(let destination, let lhs, let rhs):
                let divisor = scalars[s(rhs)]
                scalars[s(destination)] = abs(divisor) > 1e-8 ? scalars[s(lhs)] / divisor : 0
            case .negateFloat(let destination, let source):
                scalars[s(destination)] = -scalars[s(source)]
            case .minFloat(let destination, let lhs, let rhs):
                scalars[s(destination)] = min(scalars[s(lhs)], scalars[s(rhs)])
            case .maxFloat(let destination, let lhs, let rhs):
                scalars[s(destination)] = max(scalars[s(lhs)], scalars[s(rhs)])
            case .absFloat(let destination, let source):
                scalars[s(destination)] = abs(scalars[s(source)])
            case .sinFloat(let destination, let source):
                scalars[s(destination)] = sin(scalars[s(source)])
            case .cosFloat(let destination, let source):
                scalars[s(destination)] = cos(scalars[s(source)])
            case .clampFloat(let destination, let source, let minimum, let maximum):
                scalars[s(destination)] = simd_clamp(
                    scalars[s(source)],
                    scalars[s(minimum)],
                    scalars[s(maximum)]
                )
            case .mixFloat(let destination, let lhs, let rhs, let amount):
                let t = scalars[s(amount)]
                scalars[s(destination)] = scalars[s(lhs)] + (scalars[s(rhs)] - scalars[s(lhs)]) * t
            case .addVector(let destination, let lhs, let rhs):
                vectors[v(destination)] = vectors[v(lhs)] + vectors[v(rhs)]
            case .subtractVector(let destination, let lhs, let rhs):
                vectors[v(destination)] = vectors[v(lhs)] - vectors[v(rhs)]
            case .multiplyVectorFloat(let destination, let source, let amount):
                vectors[v(destination)] = vectors[v(source)] * scalars[s(amount)]
            case .absVector(let destination, let source):
                vectors[v(destination)] = simd_abs(vectors[v(source)])
            case .maxVectorFloat(let destination, let source, let value):
                vectors[v(destination)] = simd_max(vectors[v(source)], SIMD3<Float>(repeating: scalars[s(value)]))
            case .minVectorFloat(let destination, let source, let value):
                vectors[v(destination)] = simd_min(vectors[v(source)], SIMD3<Float>(repeating: scalars[s(value)]))
            case .composeVector(let destination, let x, let y, let z):
                vectors[v(destination)] = SIMD3<Float>(scalars[s(x)], scalars[s(y)], scalars[s(z)])
            case .extractX(let destination, let source):
                scalars[s(destination)] = vectors[v(source)].x
            case .extractY(let destination, let source):
                scalars[s(destination)] = vectors[v(source)].y
            case .extractZ(let destination, let source):
                scalars[s(destination)] = vectors[v(source)].z
            case .length(let destination, let source):
                scalars[s(destination)] = simd_length(vectors[v(source)])
            case .boxDistance(let destination, let source, let halfExtents, let cornerRadius):
                let q = simd_abs(vectors[v(source)]) - vectors[v(halfExtents)]
                scalars[s(destination)] = simd_length(simd_max(q, SIMD3<Float>(repeating: 0)))
                    + min(max(q.x, max(q.y, q.z)), 0)
                    - max(scalars[s(cornerRadius)], 0)
            case .cylinderDistance(let destination, let source, let radius, let halfHeight):
                let local = vectors[v(source)]
                let d = SIMD2<Float>(
                    simd_length(SIMD2<Float>(local.x, local.z)),
                    abs(local.y)
                ) - SIMD2<Float>(scalars[s(radius)], scalars[s(halfHeight)])
                scalars[s(destination)] = min(max(d.x, d.y), 0)
                    + simd_length(simd_max(d, SIMD2<Float>(repeating: 0)))
            case .taperedCapsuleDistance(let destination, let source, let start, let end, let startRadius, let endRadius):
                scalars[s(destination)] = taperedCapsuleDistance(
                    position: vectors[v(source)],
                    start: vectors[v(start)],
                    end: vectors[v(end)],
                    startRadius: scalars[s(startRadius)],
                    endRadius: scalars[s(endRadius)]
                )
            case .splineTubeDistance(let destination, let source, let control0, let control1, let control2, let control3, let startRadius, let endRadius):
                scalars[s(destination)] = splineTubeDistance(
                    position: vectors[v(source)],
                    control0: vectors[v(control0)],
                    control1: vectors[v(control1)],
                    control2: vectors[v(control2)],
                    control3: vectors[v(control3)],
                    startRadius: scalars[s(startRadius)],
                    endRadius: scalars[s(endRadius)]
                )
            case .emit(let distance, let material, let smoothUnionRadius, let operation, let attributes):
                var candidateAttributes = currentAttributes
                for attribute in attributes where attribute.channel >= 0 && attribute.channel < DistanceVolumeAttributeLayout.maximumChannelCount {
                    candidateAttributes[attribute.channel] = scalars[s(attribute.value)]
                }
                field = combine(
                    field,
                    distance: scalars[s(distance)],
                    material: material,
                    attributes: candidateAttributes,
                    smoothUnionRadius: smoothUnionRadius,
                    operation: operation
                )
            case .writeAttribute(let channel, let value):
                if channel >= 0 && channel < DistanceVolumeAttributeLayout.maximumChannelCount {
                    currentAttributes[channel] = scalars[s(value)]
                }
            }
        }

        return field
    }

    private static func combine(
        _ current: DistanceFieldProgramSample,
        distance candidateDistance: Float,
        material candidateMaterial: MaterialID,
        attributes candidateAttributes: [Int: Float],
        smoothUnionRadius: Float,
        operation: SDFPrimitiveOperation
    ) -> DistanceFieldProgramSample {
        switch operation {
        case .subtract:
            guard current.distance.isFinite else {
                return current
            }
            var result = current
            result.distance = max(current.distance, -candidateDistance)
            return result
        case .union:
            return union(
                current,
                distance: candidateDistance,
                material: candidateMaterial,
                attributes: candidateAttributes,
                smoothUnionRadius: smoothUnionRadius
            )
        }
    }

    private static func union(
        _ current: DistanceFieldProgramSample,
        distance candidateDistance: Float,
        material candidateMaterial: MaterialID,
        attributes candidateAttributes: [Int: Float],
        smoothUnionRadius: Float
    ) -> DistanceFieldProgramSample {
        guard current.distance.isFinite else {
            return DistanceFieldProgramSample(
                distance: candidateDistance,
                material: candidateMaterial,
                secondaryMaterial: candidateMaterial,
                blend: 0,
                attributes: candidateAttributes
            )
        }

        let radius = max(smoothUnionRadius, 0)
        guard radius > 1e-6 else {
            if candidateDistance < current.distance {
                return DistanceFieldProgramSample(
                    distance: candidateDistance,
                    material: candidateMaterial,
                    secondaryMaterial: candidateMaterial,
                    blend: 0,
                    attributes: candidateAttributes
                )
            }
            return current
        }

        let h = simd_clamp(0.5 + 0.5 * (candidateDistance - current.distance) / radius, 0, 1)
        let distance = candidateDistance + (current.distance - candidateDistance) * h - radius * h * (1 - h)
        let candidateWeight = 1 - h
        if candidateWeight <= 0.001 {
            var result = current
            result.distance = distance
            return result
        }
        if candidateWeight >= 0.999 {
            return DistanceFieldProgramSample(
                distance: distance,
                material: candidateMaterial,
                secondaryMaterial: candidateMaterial,
                blend: 0,
                attributes: candidateAttributes
            )
        }
        var blendedAttributes = current.attributes
        for (channel, candidateValue) in candidateAttributes {
            if let currentValue = current.attributes[channel] {
                blendedAttributes[channel] = currentValue + (candidateValue - currentValue) * candidateWeight
            } else {
                blendedAttributes[channel] = candidateValue
            }
        }
        return DistanceFieldProgramSample(
            distance: distance,
            material: current.material,
            secondaryMaterial: candidateMaterial,
            blend: candidateWeight,
            attributes: blendedAttributes
        )
    }

    private static func distanceScale(for matrix: simd_float4x4) -> Float {
        let sx = simd_length(SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z))
        let sy = simd_length(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        let sz = simd_length(SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        return max(min(sx, min(sy, sz)), 1e-6)
    }

    private struct DomainState {
        var localToProgram = matrix_identity_float4x4
        var programToLocal = matrix_identity_float4x4
        var distanceScale: Float = 1
        var twistYStrength: Float = 0

        func localPosition(for position: SIMD3<Float>) -> SIMD3<Float> {
            let local4 = programToLocal * SIMD4<Float>(position, 1)
            var local = SIMD3<Float>(local4.x, local4.y, local4.z)
            if abs(twistYStrength) > 1e-6 {
                let angle = -local.y * twistYStrength
                let c = cos(angle)
                let s = sin(angle)
                local = SIMD3<Float>(
                    c * local.x - s * local.z,
                    local.y,
                    s * local.x + c * local.z
                )
            }
            return local
        }
    }
}

struct DistanceFieldProgramSample {
    var distance: Float
    var material: MaterialID
    var secondaryMaterial: MaterialID
    var blend: Float
    var attributes: [Int: Float]
}

enum DistanceFieldProgramBuilder {
    static func build(program: DistanceFieldProgram, settings: DistanceVolumeBuildSettings, fallbackMaterial: MaterialID) throws -> DistanceVolume {
        let dimensions = try validatedDimensions(program: program, settings: settings)

        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        var distances = [Float](repeating: Float.greatestFiniteMagnitude, count: sampleCount)
        var materialSamples = [DistanceVolumeMaterialSample](
            repeating: DistanceVolumeMaterialSample(materialA: fallbackMaterial),
            count: sampleCount
        )
        let packedVectorCount = program.attributeLayout.packedVectorCount
        var attributeSamples = [SIMD4<Float>]()
        if packedVectorCount > 0 {
            let defaultPacked = program.attributeLayout.defaultPackedSample()
            attributeSamples.reserveCapacity(sampleCount * packedVectorCount)
            for _ in 0..<sampleCount {
                attributeSamples.append(contentsOf: defaultPacked)
            }
        }
        let extent = settings.boundsMax - settings.boundsMin

        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    let wx = Float(x) / Float(max(dimensions.x - 1, 1))
                    let wy = Float(y) / Float(max(dimensions.y - 1, 1))
                    let wz = Float(z) / Float(max(dimensions.z - 1, 1))
                    let position = settings.boundsMin + extent * SIMD3<Float>(wx, wy, wz)
                    let sample = DistanceFieldProgramEvaluator.sample(
                        program: program,
                        at: position,
                        fallbackMaterial: fallbackMaterial
                    )
                    let index = x + y * dimensions.x + z * dimensions.x * dimensions.y
                    distances[index] = sample.distance
                    materialSamples[index] = DistanceVolumeMaterialSample(
                        materialA: sample.material,
                        materialB: sample.secondaryMaterial,
                        blend: sample.blend
                    )
                    if packedVectorCount > 0 {
                        let attributeIndex = index * packedVectorCount
                        for (channelIndex, value) in sample.attributes where channelIndex < program.attributeLayout.channelCount {
                            let vectorIndex = channelIndex / 4
                            let laneIndex = channelIndex % 4
                            attributeSamples[attributeIndex + vectorIndex][laneIndex] = value
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
            attributeLayout: program.attributeLayout,
            attributeSamples: attributeSamples,
            boundsMin: settings.boundsMin,
            boundsMax: settings.boundsMax
        )
    }

    static func buildSparse(
        program: DistanceFieldProgram,
        settings: SparseDistanceVolumeBuildSettings,
        fallbackMaterial: MaterialID
    ) throws -> SparseDistanceVolume {
        let baseDimensions = try validatedDimensions(program: program, settings: settings.denseSettings)
        let sampleScale = max(settings.sampleScale, 1)
        let dimensions = scaledDimensions(baseDimensions, sampleScale: sampleScale)
        let brickSize = SIMD3<Int>(
            max(settings.brickSize.x * sampleScale, 1),
            max(settings.brickSize.y * sampleScale, 1),
            max(settings.brickSize.z * sampleScale, 1)
        )
        let extent = settings.denseSettings.boundsMax - settings.denseSettings.boundsMin
        let defaultMaterial = DistanceVolumeMaterialSample(materialA: fallbackMaterial)
        let defaultDistance = max(settings.narrowBand, 1)
        let band = settings.narrowBand
        let packedVectorCount = program.attributeLayout.packedVectorCount
        let defaultAttributeSample = program.attributeLayout.defaultPackedSample()

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
                    let coreDimensions = SIMD3<Int>(
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
                        min(originX + coreDimensions.x + overlap, dimensions.x),
                        min(originY + coreDimensions.y + overlap, dimensions.y),
                        min(originZ + coreDimensions.z + overlap, dimensions.z)
                    )
                    let storedDimensions = SIMD3<Int>(
                        storedEnd.x - storedOrigin.x,
                        storedEnd.y - storedOrigin.y,
                        storedEnd.z - storedOrigin.z
                    )
                    let storedSamples = sampleBrick(
                        program: program,
                        origin: storedOrigin,
                        dimensions: storedDimensions,
                        volumeDimensions: dimensions,
                        boundsMin: settings.denseSettings.boundsMin,
                        extent: extent,
                        fallbackMaterial: fallbackMaterial,
                        defaultAttributeSample: defaultAttributeSample,
                        packedVectorCount: packedVectorCount
                    )
                    let minDistance = storedSamples.distances.min() ?? Float.greatestFiniteMagnitude
                    let maxDistance = storedSamples.distances.max() ?? -Float.greatestFiniteMagnitude

                    if minDistance <= band && maxDistance >= -band {
                        bricks.append(SparseDistanceVolumeBrick(
                            origin: storedOrigin,
                            dimensions: storedDimensions,
                            coreOrigin: SIMD3<Int>(originX, originY, originZ),
                            coreDimensions: coreDimensions,
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
            boundsMin: settings.denseSettings.boundsMin,
            boundsMax: settings.denseSettings.boundsMax,
            defaultDistance: defaultDistance,
            defaultMaterial: defaultMaterial,
            attributeLayout: program.attributeLayout,
            defaultAttributeSample: defaultAttributeSample,
            bricks: bricks
        )
    }

    private static func validatedDimensions(
        program: DistanceFieldProgram,
        settings: DistanceVolumeBuildSettings
    ) throws -> SIMD3<Int> {
        guard !program.operations.isEmpty || !program.instructions.isEmpty else {
            throw DenrimRendererError.invalidScene("Distance field program must contain at least one operation or instruction.")
        }
        let dimensions = SIMD3<Int>(
            max(settings.dimensions.x, 2),
            max(settings.dimensions.y, 2),
            max(settings.dimensions.z, 2)
        )
        guard settings.boundsMax.x > settings.boundsMin.x,
              settings.boundsMax.y > settings.boundsMin.y,
              settings.boundsMax.z > settings.boundsMin.z else {
            throw DenrimRendererError.invalidScene("Distance field program bounds must have positive extent.")
        }
        return dimensions
    }

    private static func scaledDimensions(_ dimensions: SIMD3<Int>, sampleScale: Int) -> SIMD3<Int> {
        let scale = max(sampleScale, 1)
        guard scale > 1 else {
            return dimensions
        }
        return SIMD3<Int>(
            (dimensions.x - 1) * scale + 1,
            (dimensions.y - 1) * scale + 1,
            (dimensions.z - 1) * scale + 1
        )
    }

    private static func sampleBrick(
        program: DistanceFieldProgram,
        origin: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        volumeDimensions: SIMD3<Int>,
        boundsMin: SIMD3<Float>,
        extent: SIMD3<Float>,
        fallbackMaterial: MaterialID,
        defaultAttributeSample: [SIMD4<Float>],
        packedVectorCount: Int
    ) -> (distances: [Float], materialSamples: [DistanceVolumeMaterialSample], attributeSamples: [SIMD4<Float>]) {
        let sampleCount = dimensions.x * dimensions.y * dimensions.z
        var distances = [Float]()
        var materialSamples = [DistanceVolumeMaterialSample]()
        var attributeSamples = [SIMD4<Float>]()
        distances.reserveCapacity(sampleCount)
        materialSamples.reserveCapacity(sampleCount)
        if packedVectorCount > 0 {
            attributeSamples.reserveCapacity(sampleCount * packedVectorCount)
        }

        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    let position = samplePosition(
                        x: origin.x + x,
                        y: origin.y + y,
                        z: origin.z + z,
                        dimensions: volumeDimensions,
                        boundsMin: boundsMin,
                        extent: extent
                    )
                    let sample = DistanceFieldProgramEvaluator.sample(
                        program: program,
                        at: position,
                        fallbackMaterial: fallbackMaterial
                    )
                    distances.append(sample.distance)
                    materialSamples.append(DistanceVolumeMaterialSample(
                        materialA: sample.material,
                        materialB: sample.secondaryMaterial,
                        blend: sample.blend
                    ))
                    if packedVectorCount > 0 {
                        var packed = defaultAttributeSample
                        for (channelIndex, value) in sample.attributes where channelIndex < program.attributeLayout.channelCount {
                            let vectorIndex = channelIndex / 4
                            let laneIndex = channelIndex % 4
                            packed[vectorIndex][laneIndex] = value
                        }
                        attributeSamples.append(contentsOf: packed)
                    }
                }
            }
        }

        return (distances, materialSamples, attributeSamples)
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
}
