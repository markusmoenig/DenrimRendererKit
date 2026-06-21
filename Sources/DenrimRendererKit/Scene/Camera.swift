import Foundation
import simd

/// A simple perspective camera.
public struct Camera: Sendable {
    /// Camera position in world space.
    public var origin: SIMD3<Float>

    /// Point the camera looks at.
    public var target: SIMD3<Float>

    /// Approximate up direction.
    public var up: SIMD3<Float>

    /// Vertical field of view in degrees.
    public var verticalFieldOfViewDegrees: Float

    /// Creates a perspective camera.
    public init(
        origin: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        verticalFieldOfViewDegrees: Float = 45
    ) {
        self.origin = origin
        self.target = target
        self.up = up
        self.verticalFieldOfViewDegrees = verticalFieldOfViewDegrees
    }

    func gpuCamera(width: Int, height: Int) -> GPUCamera {
        let aspect = Float(width) / Float(height)
        let theta = verticalFieldOfViewDegrees * .pi / 180
        let viewportHeight = 2 * tan(theta / 2)
        let viewportWidth = aspect * viewportHeight

        let forward = simd_normalize(target - origin)
        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)

        let horizontal = viewportWidth * right
        let vertical = viewportHeight * trueUp
        let lowerLeft = origin + forward - horizontal * 0.5 - vertical * 0.5

        return GPUCamera(
            origin: SIMD4<Float>(origin, 0),
            lowerLeft: SIMD4<Float>(lowerLeft, 0),
            horizontal: SIMD4<Float>(horizontal, 0),
            vertical: SIMD4<Float>(vertical, 0)
        )
    }
}
