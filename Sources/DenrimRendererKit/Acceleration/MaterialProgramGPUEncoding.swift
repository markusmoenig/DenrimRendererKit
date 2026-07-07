import Foundation
import simd

struct GPUMaterialProgramResources {
    var descriptors: [GPUMaterialProgramDescriptor]
    var operations: [GPUMaterialProgramOperation]
}

enum MaterialProgramGPUEncoding {
    static func encode(_ programs: [DistanceFieldMaterialProgram]) -> GPUMaterialProgramResources {
        var descriptors: [GPUMaterialProgramDescriptor] = []
        var operations: [GPUMaterialProgramOperation] = []

        for program in programs {
            let offset = operations.count
            let encoded = program.instructions.map(encodeInstruction)
            operations.append(contentsOf: encoded)
            descriptors.append(GPUMaterialProgramDescriptor(
                metadata: SIMD4<UInt32>(UInt32(offset), UInt32(encoded.count), 0, 0)
            ))
        }

        return GPUMaterialProgramResources(descriptors: descriptors, operations: operations)
    }

    private static func encodeInstruction(_ instruction: DistanceFieldMaterialInstruction) -> GPUMaterialProgramOperation {
        switch instruction {
        case .loadVectorInput(let destination, let input):
            return op(1, destination.rawValue, input.rawValue, 0)
        case .loadScalarInput(let destination, let input):
            return op(2, destination.rawValue, input.rawValue, 0)
        case .loadAttribute(let channel, let destination):
            return op(3, destination.rawValue, UInt32(max(channel, 0)), 0)
        case .setFloat(let destination, let value):
            return op(10, destination.rawValue, 0, 0, data: SIMD4<Float>(value, 0, 0, 0))
        case .setVector(let destination, let value):
            return op(11, destination.rawValue, 0, 0, data: SIMD4<Float>(value.x, value.y, value.z, 0))
        case .addFloat(let destination, let lhs, let rhs):
            return op(20, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .subtractFloat(let destination, let lhs, let rhs):
            return op(21, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .multiplyFloat(let destination, let lhs, let rhs):
            return op(22, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .divideFloat(let destination, let lhs, let rhs):
            return op(23, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .negateFloat(let destination, let source):
            return op(26, destination.rawValue, source.rawValue, 0)
        case .minFloat(let destination, let lhs, let rhs):
            return op(27, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .maxFloat(let destination, let lhs, let rhs):
            return op(28, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .absFloat(let destination, let source):
            return op(29, destination.rawValue, source.rawValue, 0)
        case .sinFloat(let destination, let source):
            return op(34, destination.rawValue, source.rawValue, 0)
        case .cosFloat(let destination, let source):
            return op(35, destination.rawValue, source.rawValue, 0)
        case .clampFloat(let destination, let source, let min, let max):
            return op(36, destination.rawValue, source.rawValue, min.rawValue, data: SIMD4<Float>(Float(max.rawValue), 0, 0, 0))
        case .clampFloatConstant(let destination, let source, min: let min, max: let max):
            return op(24, destination.rawValue, source.rawValue, 0, data: SIMD4<Float>(min, max, 0, 0))
        case .mixFloat(let destination, let a, let b, let t):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(25, destination.rawValue, a.rawValue, b.rawValue),
                data0: SIMD4<Float>(Float(t.rawValue), 0, 0, 0)
            )
        case .smoothstep(let destination, let edge0, let edge1, let x):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(74, destination.rawValue, edge0.rawValue, edge1.rawValue),
                data0: SIMD4<Float>(Float(x.rawValue), 0, 0, 0)
            )
        case .step(let destination, let edge, let x):
            return op(75, destination.rawValue, edge.rawValue, x.rawValue)
        case .saturate(let destination, let source):
            return op(76, destination.rawValue, source.rawValue, 0)
        case .fractFloat(let destination, let source):
            return op(77, destination.rawValue, source.rawValue, 0)
        case .floorFloat(let destination, let source):
            return op(78, destination.rawValue, source.rawValue, 0)
        case .modFloat(let destination, let lhs, let rhs):
            return op(79, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .addVector(let destination, let lhs, let rhs):
            return op(60, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .subtractVector(let destination, let lhs, let rhs):
            return op(61, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .multiplyVectorFloat(let destination, let source, let amount):
            return op(62, destination.rawValue, source.rawValue, amount.rawValue)
        case .absVector(let destination, let source):
            return op(63, destination.rawValue, source.rawValue, 0)
        case .maxVectorFloat(let destination, let source, let value):
            return op(64, destination.rawValue, source.rawValue, value.rawValue)
        case .minVectorFloat(let destination, let source, let value):
            return op(65, destination.rawValue, source.rawValue, value.rawValue)
        case .composeVector(let destination, let x, let y, let z):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(30, destination.rawValue, x.rawValue, y.rawValue),
                data0: SIMD4<Float>(Float(z.rawValue), 0, 0, 0)
            )
        case .extractX(let destination, let source):
            return op(31, destination.rawValue, source.rawValue, 0)
        case .extractY(let destination, let source):
            return op(32, destination.rawValue, source.rawValue, 0)
        case .extractZ(let destination, let source):
            return op(33, destination.rawValue, source.rawValue, 0)
        case .length(let destination, let source):
            return op(66, destination.rawValue, source.rawValue, 0)
        case .dot(let destination, let lhs, let rhs):
            return op(80, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .normalize(let destination, let source):
            return op(81, destination.rawValue, source.rawValue, 0)
        case .distance(let destination, let lhs, let rhs):
            return op(82, destination.rawValue, lhs.rawValue, rhs.rawValue)
        case .valueNoise3D(let destination, let position, let scale, let seed):
            return op(83, destination.rawValue, position.rawValue, scale.rawValue, data: SIMD4<Float>(Float(seed.rawValue), 0, 0, 0))
        case .fbm3D(let destination, let position, let scale, let octaves, let lacunarity, let gain, let seed):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(84, destination.rawValue, position.rawValue, scale.rawValue),
                data0: SIMD4<Float>(Float(octaves.rawValue), Float(lacunarity.rawValue), Float(gain.rawValue), Float(seed.rawValue))
            )
        case .cellular3D(let distance, let secondDistance, let cellID, let position, let scale, let seed):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(85, distance.rawValue, secondDistance.rawValue, cellID.rawValue),
                data0: SIMD4<Float>(Float(position.rawValue), Float(scale.rawValue), Float(seed.rawValue), 0)
            )
        case .boxDistance(let destination, let position, let halfExtents, let cornerRadius):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(70, destination.rawValue, position.rawValue, halfExtents.rawValue),
                data0: SIMD4<Float>(Float(cornerRadius.rawValue), 0, 0, 0)
            )
        case .cylinderDistance(let destination, let position, let radius, let halfHeight):
            return op(71, destination.rawValue, position.rawValue, radius.rawValue, data: SIMD4<Float>(Float(halfHeight.rawValue), 0, 0, 0))
        case .taperedCapsuleDistance(let destination, let position, let start, let end, let startRadius, let endRadius):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(72, destination.rawValue, position.rawValue, start.rawValue),
                data0: SIMD4<Float>(Float(end.rawValue), Float(startRadius.rawValue), Float(endRadius.rawValue), 0)
            )
        case .splineTubeDistance(let destination, let position, let control0, let control1, let control2, let control3, let startRadius, let endRadius):
            return GPUMaterialProgramOperation(
                metadata: SIMD4<UInt32>(73, destination.rawValue, position.rawValue, control0.rawValue),
                data0: SIMD4<Float>(Float(control1.rawValue), Float(control2.rawValue), Float(control3.rawValue), Float(startRadius.rawValue + (endRadius.rawValue << 8)))
            )
        case .writeMask(let channel, let source):
            return op(40, channel.rawValue, source.rawValue, 0)
        case .readMask(let channel, let destination):
            return op(41, channel.rawValue, destination.rawValue, 0)
        case .writeMaterialField(let field, let source):
            return op(50, field.rawValue, source.rawValue, 0)
        case .writeMaterialFieldVector(let field, let source):
            return op(51, field.rawValue, source.rawValue, 0)
        }
    }

    private static func op(
        _ opcode: UInt32,
        _ a: UInt32,
        _ b: UInt32,
        _ c: UInt32,
        data: SIMD4<Float> = SIMD4<Float>(repeating: 0)
    ) -> GPUMaterialProgramOperation {
        GPUMaterialProgramOperation(metadata: SIMD4<UInt32>(opcode, a, b, c), data0: data)
    }
}
