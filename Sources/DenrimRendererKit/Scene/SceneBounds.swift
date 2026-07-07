import Foundation
import simd

/// World or local axis-aligned bounds for renderer-facing scene content.
public struct SceneBounds: Sendable, Equatable {
    /// Minimum corner.
    public var minimum: SIMD3<Float>

    /// Maximum corner.
    public var maximum: SIMD3<Float>

    /// Empty bounds that can be grown with `include`.
    public static var empty: SceneBounds {
        SceneBounds(
            uncheckedMinimum: SIMD3<Float>(repeating: Float.greatestFiniteMagnitude),
            maximum: SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        )
    }

    private init(
        uncheckedMinimum minimum: SIMD3<Float>,
        maximum: SIMD3<Float>
    ) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Creates bounds from two corners.
    public init(
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>
    ) {
        self.minimum = simd_min(minimum, maximum)
        self.maximum = simd_max(minimum, maximum)
    }

    /// Creates bounds from a center point and extent.
    public init(
        center: SIMD3<Float>,
        extent: SIMD3<Float>
    ) {
        let halfExtent = simd_abs(extent) * 0.5
        self.init(
            minimum: center - halfExtent,
            maximum: center + halfExtent
        )
    }

    /// Whether the bounds contain at least one point.
    public var isEmpty: Bool {
        minimum.x > maximum.x || minimum.y > maximum.y || minimum.z > maximum.z
    }

    /// Center point.
    public var center: SIMD3<Float> {
        isEmpty ? SIMD3<Float>(repeating: 0) : (minimum + maximum) * 0.5
    }

    /// Axis lengths.
    public var extent: SIMD3<Float> {
        isEmpty ? SIMD3<Float>(repeating: 0) : maximum - minimum
    }

    /// Bounding-sphere radius around `center`.
    public var radius: Float {
        simd_length(extent) * 0.5
    }

    /// The eight bounds corners.
    public var corners: [SIMD3<Float>] {
        guard !isEmpty else {
            return []
        }
        return [
            SIMD3<Float>(minimum.x, minimum.y, minimum.z),
            SIMD3<Float>(maximum.x, minimum.y, minimum.z),
            SIMD3<Float>(minimum.x, maximum.y, minimum.z),
            SIMD3<Float>(maximum.x, maximum.y, minimum.z),
            SIMD3<Float>(minimum.x, minimum.y, maximum.z),
            SIMD3<Float>(maximum.x, minimum.y, maximum.z),
            SIMD3<Float>(minimum.x, maximum.y, maximum.z),
            SIMD3<Float>(maximum.x, maximum.y, maximum.z)
        ]
    }

    /// Expands these bounds to include a point.
    public mutating func include(_ point: SIMD3<Float>) {
        minimum = simd_min(minimum, point)
        maximum = simd_max(maximum, point)
    }

    /// Expands these bounds to include another bounds value.
    public mutating func include(_ bounds: SceneBounds) {
        guard !bounds.isEmpty else {
            return
        }
        include(bounds.minimum)
        include(bounds.maximum)
    }

    /// Returns bounds transformed by a local-to-world transform.
    public func transformed(by transform: Transform) -> SceneBounds {
        guard !isEmpty else {
            return .empty
        }
        var result = SceneBounds.empty
        for corner in corners {
            result.include(transform.transformPoint(corner))
        }
        return result
    }
}

public extension Mesh {
    /// Local bounds of the mesh vertices.
    var bounds: SceneBounds? {
        guard let first = vertices.first else {
            return nil
        }
        var bounds = SceneBounds(minimum: first, maximum: first)
        for vertex in vertices.dropFirst() {
            bounds.include(vertex)
        }
        return bounds
    }
}

public extension RenderFieldBundle {
    /// Bounds covered by the field in bundle-local space.
    var sceneBounds: SceneBounds {
        let bounds = self.bounds
        return SceneBounds(minimum: bounds.minimum, maximum: bounds.maximum)
    }
}

public extension RenderScene {
    /// Combined world-space bounds of mesh and SDF field instances.
    func worldBounds() -> SceneBounds? {
        var bounds = SceneBounds.empty

        for instance in meshInstances {
            guard let meshBounds = instance.mesh.bounds else {
                continue
            }
            bounds.include(meshBounds.transformed(by: instance.transform))
        }

        for instance in volumeInstances {
            bounds.include(SceneBounds(
                minimum: instance.volume.boundsMin,
                maximum: instance.volume.boundsMax
            ).transformed(by: instance.transform))
        }

        for instance in sparseVolumeInstances {
            bounds.include(SceneBounds(
                minimum: instance.volume.boundsMin,
                maximum: instance.volume.boundsMax
            ).transformed(by: instance.transform))
        }

        for instance in gpuSparseVolumeInstances {
            bounds.include(SceneBounds(
                minimum: instance.resource.boundsMin,
                maximum: instance.resource.boundsMax
            ).transformed(by: instance.transform))
        }

        return bounds.isEmpty ? nil : bounds
    }
}
