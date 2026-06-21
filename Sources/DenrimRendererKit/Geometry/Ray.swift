import Foundation
import simd

/// A ray in world space.
public struct Ray: Sendable {
    /// The ray origin.
    public var origin: SIMD3<Float>

    /// The normalized or unnormalized ray direction.
    public var direction: SIMD3<Float>

    /// Creates a world-space ray.
    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = direction
    }
}

/// A surface interaction returned by a geometry query.
public struct SurfaceHit: Sendable, Equatable {
    /// Distance along the ray.
    public var distance: Float

    /// Hit position in world space.
    public var position: SIMD3<Float>

    /// Surface normal in world space.
    public var normal: SIMD3<Float>

    /// Material assigned to the intersected primitive.
    public var material: MaterialID

    /// Primitive index inside the queried geometry set.
    public var primitiveIndex: Int

    /// Creates a surface interaction.
    public init(
        distance: Float,
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        material: MaterialID,
        primitiveIndex: Int
    ) {
        self.distance = distance
        self.position = position
        self.normal = normal
        self.material = material
        self.primitiveIndex = primitiveIndex
    }
}
