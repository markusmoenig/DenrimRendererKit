import Foundation
import simd

/// Projection model used by a render camera.
public enum CameraProjection: Sendable, Equatable {
    /// Perspective projection using `Camera.verticalFieldOfViewDegrees`.
    case perspective

    /// Orthographic projection with a vertical world-space scale.
    case orthographic(verticalScale: Float)
}

/// A simple render camera.
public struct Camera: Sendable {
    /// Camera position in world space.
    public var origin: SIMD3<Float>

    /// Point the camera looks at.
    public var target: SIMD3<Float>

    /// Approximate up direction.
    public var up: SIMD3<Float>

    /// Vertical field of view in degrees.
    public var verticalFieldOfViewDegrees: Float

    /// Projection mode.
    public var projection: CameraProjection

    /// Creates a camera.
    public init(
        origin: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        verticalFieldOfViewDegrees: Float = 45,
        projection: CameraProjection = .perspective
    ) {
        self.origin = origin
        self.target = target
        self.up = up
        self.verticalFieldOfViewDegrees = verticalFieldOfViewDegrees
        self.projection = projection
    }

    func gpuCamera(width: Int, height: Int) -> GPUCamera {
        let aspect = Float(width) / Float(height)

        let forward = simd_normalize(target - origin)
        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)

        let viewportHeight: Float
        let projectionFlag: Float
        switch projection {
        case .perspective:
            let theta = verticalFieldOfViewDegrees * .pi / 180
            viewportHeight = 2 * tan(theta / 2)
            projectionFlag = 0
        case .orthographic(let verticalScale):
            viewportHeight = max(verticalScale, 0.0001)
            projectionFlag = 1
        }

        let viewportWidth = aspect * viewportHeight
        let horizontal = viewportWidth * right
        let vertical = viewportHeight * trueUp
        let planeCenter = projection == .perspective ? origin + forward : origin
        let lowerLeft = planeCenter - horizontal * 0.5 - vertical * 0.5

        return GPUCamera(
            origin: SIMD4<Float>(origin, projectionFlag),
            lowerLeft: SIMD4<Float>(lowerLeft, 0),
            horizontal: SIMD4<Float>(horizontal, 0),
            vertical: SIMD4<Float>(vertical, 0)
        )
    }
}
