import Foundation
import simd

/// Hit-time material program evaluated after an SDF surface intersection.
///
/// This IR is intentionally separate from `DistanceFieldProgram`: the distance
/// program owns geometry and low-frequency baked attributes, while this program
/// owns surface styling that must be evaluated at the final hit point.
public struct DistanceFieldMaterialProgram: Sendable, Equatable {
    /// Generic scalar/vector instructions evaluated in order at the surface hit.
    public var instructions: [DistanceFieldMaterialInstruction]

    public init(instructions: [DistanceFieldMaterialInstruction] = []) {
        self.instructions = instructions
    }
}

/// Neutral hit-time mask registers for material programs.
///
/// RendererKit assigns no meaning to these lanes. Hosts such as Denrim Form can
/// use them as routing conventions for cracks, dots, rings, wetness, moss, age
/// tint, or any other surface-style component.
public enum DistanceFieldMaterialMaskChannel: UInt32, Sendable, Equatable, CaseIterable {
    case a = 0
    case b = 1
    case c = 2
    case d = 3
}

/// Inputs exposed to a hit-time material program as vector registers.
public enum DistanceFieldMaterialVectorInput: UInt32, Sendable, Equatable {
    case worldPosition = 0
    case localPosition = 1
    case normal = 2
    case viewDirection = 3
    case baseColor = 4
    case baseEmission = 5
}

/// Inputs exposed to a hit-time material program as scalar registers.
public enum DistanceFieldMaterialScalarInput: UInt32, Sendable, Equatable {
    case roughness = 0
    case metallic = 1
    case specular = 2
    case transmission = 3
    case opacity = 4
    case emissionStrength = 5
    case materialBlend = 6
}

/// One operation in a hit-time material program.
public enum DistanceFieldMaterialInstruction: Sendable, Equatable {
    case loadVectorInput(DistanceFieldVectorRegister, DistanceFieldMaterialVectorInput)
    case loadScalarInput(DistanceFieldScalarRegister, DistanceFieldMaterialScalarInput)
    case loadAttribute(channel: Int, into: DistanceFieldScalarRegister)

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
    case clampFloatConstant(DistanceFieldScalarRegister, DistanceFieldScalarRegister, min: Float, max: Float)
    case mixFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case smoothstep(DistanceFieldScalarRegister, edge0: DistanceFieldScalarRegister, edge1: DistanceFieldScalarRegister, x: DistanceFieldScalarRegister)
    case step(DistanceFieldScalarRegister, edge: DistanceFieldScalarRegister, x: DistanceFieldScalarRegister)
    case saturate(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case fractFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case floorFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case modFloat(DistanceFieldScalarRegister, DistanceFieldScalarRegister, DistanceFieldScalarRegister)
    case addVector(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case subtractVector(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case multiplyVectorFloat(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldScalarRegister)
    case absVector(DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case maxVectorFloat(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldScalarRegister)
    case minVectorFloat(DistanceFieldVectorRegister, DistanceFieldVectorRegister, DistanceFieldScalarRegister)
    case composeVector(DistanceFieldVectorRegister, x: DistanceFieldScalarRegister, y: DistanceFieldScalarRegister, z: DistanceFieldScalarRegister)
    case extractX(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case extractY(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case extractZ(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case length(DistanceFieldScalarRegister, DistanceFieldVectorRegister)
    case dot(DistanceFieldScalarRegister, DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case normalize(DistanceFieldVectorRegister, DistanceFieldVectorRegister)
    case distance(DistanceFieldScalarRegister, DistanceFieldVectorRegister, DistanceFieldVectorRegister)

    case valueNoise3D(DistanceFieldScalarRegister, position: DistanceFieldVectorRegister, scale: DistanceFieldScalarRegister, seed: DistanceFieldScalarRegister)
    case fbm3D(DistanceFieldScalarRegister, position: DistanceFieldVectorRegister, scale: DistanceFieldScalarRegister, octaves: DistanceFieldScalarRegister, lacunarity: DistanceFieldScalarRegister, gain: DistanceFieldScalarRegister, seed: DistanceFieldScalarRegister)
    case cellular3D(
        distance: DistanceFieldScalarRegister,
        secondDistance: DistanceFieldScalarRegister,
        cellID: DistanceFieldScalarRegister,
        position: DistanceFieldVectorRegister,
        scale: DistanceFieldScalarRegister,
        seed: DistanceFieldScalarRegister
    )

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

    case writeMask(DistanceFieldMaterialMaskChannel, DistanceFieldScalarRegister)
    case readMask(DistanceFieldMaterialMaskChannel, DistanceFieldScalarRegister)
    case writeMaterialField(DistanceFieldMaterialField, scalar: DistanceFieldScalarRegister)
    case writeMaterialFieldVector(DistanceFieldMaterialField, vector: DistanceFieldVectorRegister)
}
