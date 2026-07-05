import Foundation
import simd

/// App-authored rectangular area light represented by one emissive quad.
public struct QuadLight: Sendable, Equatable {
    /// First corner of the quad.
    public var a: SIMD3<Float>

    /// Second corner of the quad.
    public var b: SIMD3<Float>

    /// Third corner of the quad.
    public var c: SIMD3<Float>

    /// Fourth corner of the quad.
    public var d: SIMD3<Float>

    /// Emission color in linear RGB.
    public var color: SIMD3<Float>

    /// Multiplier applied to `color`.
    public var intensity: Float

    /// Creates a rectangular area light from four corners.
    public init(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>,
        color: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        intensity: Float = 1
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.color = color
        self.intensity = intensity
    }

    var material: Material {
        Material(
            baseColor: color,
            emission: color,
            emissionStrength: intensity,
            roughness: 0.4,
            metallic: 0,
            specular: 0
        )
    }
}
