import Foundation
import simd

/// A scene transform used by mesh instances.
public struct Transform: Sendable, Equatable {
    /// Transform matrix from local space to world space.
    public var matrix: simd_float4x4

    /// Identity transform.
    public static let identity = Transform(matrix: matrix_identity_float4x4)

    /// Creates a transform from a local-to-world matrix.
    public init(matrix: simd_float4x4) {
        self.matrix = matrix
    }

    /// Creates a translation transform.
    public static func translation(_ value: SIMD3<Float>) -> Transform {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(value, 1)
        return Transform(matrix: matrix)
    }

    /// Creates a scale transform.
    public static func scale(_ value: SIMD3<Float>) -> Transform {
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = value.x
        matrix.columns.1.y = value.y
        matrix.columns.2.z = value.z
        return Transform(matrix: matrix)
    }

    /// Creates a rotation transform around the Y axis.
    public static func rotationY(radians: Float) -> Transform {
        let c = cos(radians)
        let s = sin(radians)
        let matrix = simd_float4x4(
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return Transform(matrix: matrix)
    }

    /// Creates a rotation transform around the X axis.
    public static func rotationX(radians: Float) -> Transform {
        let c = cos(radians)
        let s = sin(radians)
        let matrix = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return Transform(matrix: matrix)
    }

    /// Creates a rotation transform around the Z axis.
    public static func rotationZ(radians: Float) -> Transform {
        let c = cos(radians)
        let s = sin(radians)
        let matrix = simd_float4x4(
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return Transform(matrix: matrix)
    }

    /// Combines two transforms.
    public static func * (lhs: Transform, rhs: Transform) -> Transform {
        Transform(matrix: lhs.matrix * rhs.matrix)
    }

    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(point, 1)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }

    func transformNormal(_ normal: SIMD3<Float>) -> SIMD3<Float> {
        let inverseTranspose = matrix.transpose.inverse
        let transformed = inverseTranspose * SIMD4<Float>(normal, 0)
        return simd_normalize(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
    }
}
