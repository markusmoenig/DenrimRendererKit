import Foundation
import simd

/// Projection model used by a render camera.
public enum CameraProjection: Sendable, Equatable {
    /// Perspective projection using `Camera.verticalFieldOfViewDegrees`.
    case perspective

    /// Orthographic projection with a vertical world-space scale.
    case orthographic(verticalScale: Float)
}

/// Thin-lens camera settings used by path-traced render qualities.
public struct CameraLens: Sendable, Equatable {
    /// Distance from the camera origin to the focal plane along the view direction.
    public var focusDistance: Float

    /// Radius of the lens aperture in world units. Use zero for pinhole rendering.
    public var apertureRadius: Float

    /// Pinhole lens with no depth of field.
    public static let pinhole = CameraLens(focusDistance: 1, apertureRadius: 0)

    /// Creates camera lens settings.
    public init(
        focusDistance: Float = 1,
        apertureRadius: Float = 0
    ) {
        self.focusDistance = max(focusDistance, 0.0001)
        self.apertureRadius = max(apertureRadius, 0)
    }
}

/// Projection mode used by automatic camera framing.
public enum CameraFramingProjection: Sendable, Equatable {
    /// Perspective camera with the requested vertical field of view.
    case perspective(verticalFieldOfViewDegrees: Float = 45)

    /// Orthographic camera. The vertical scale is computed from the fitted bounds.
    case orthographic
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

    /// Lens/focus settings. `.preview` currently ignores aperture for speed.
    public var lens: CameraLens

    /// Creates a camera.
    public init(
        origin: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        verticalFieldOfViewDegrees: Float = 45,
        projection: CameraProjection = .perspective,
        lens: CameraLens = .pinhole
    ) {
        self.origin = origin
        self.target = target
        self.up = up
        self.verticalFieldOfViewDegrees = verticalFieldOfViewDegrees
        self.projection = projection
        self.lens = lens
    }

    /// Normalized direction from `origin` to `target`.
    public var viewDirection: SIMD3<Float> {
        let direction = target - origin
        guard simd_length_squared(direction) > 1e-8 else {
            return SIMD3<Float>(0, 0, -1)
        }
        return simd_normalize(direction)
    }

    /// Returns a copy focused on a world-space point.
    public func focused(
        on point: SIMD3<Float>,
        apertureRadius: Float
    ) -> Camera {
        var camera = self
        let focusDistance = max(simd_dot(point - origin, viewDirection), 0.0001)
        camera.lens = CameraLens(
            focusDistance: focusDistance,
            apertureRadius: apertureRadius
        )
        return camera
    }

    /// Creates a camera that frames world-space bounds from a view direction.
    ///
    /// `centerOffset` is measured in normalized fitted-frame units on the camera plane.
    /// Positive X moves the object center to the right of the image; positive Y moves it up.
    public static func framing(
        _ bounds: SceneBounds,
        viewDirection: SIMD3<Float> = SIMD3<Float>(0, -0.25, -1),
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        aspectRatio: Float,
        padding: Float = 1.15,
        centerOffset: SIMD2<Float> = SIMD2<Float>(repeating: 0),
        targetOffset: SIMD3<Float> = SIMD3<Float>(repeating: 0),
        projection: CameraFramingProjection = .perspective(),
        apertureRadius: Float = 0
    ) -> Camera {
        let basis = cameraBasis(viewDirection: viewDirection, up: up)
        let center = bounds.center + targetOffset
        let paddedCorners = bounds.corners.map { center + ($0 - bounds.center) * max(padding, 0.0001) }
        let aspect = max(aspectRatio, 0.0001)
        let projected = projectedExtents(corners: paddedCorners, center: center, basis: basis)
        let targetShift = basis.right * (projected.halfWidth * centerOffset.x)
            + basis.trueUp * (projected.halfHeight * centerOffset.y)
        let target = center - targetShift
        let targetProjected = projectedExtents(corners: paddedCorners, center: target, basis: basis)

        switch projection {
        case .perspective(let fov):
            let clampedFOV = simd_clamp(fov, 1, 175)
            let tanY = tan(clampedFOV * .pi / 360)
            let tanX = tanY * aspect
            var distance: Float = 0.0001
            for corner in paddedCorners {
                let relative = corner - target
                let x = simd_dot(relative, basis.right)
                let y = simd_dot(relative, basis.trueUp)
                let z = simd_dot(relative, basis.forward)
                distance = max(distance, abs(x) / max(tanX, 0.0001) - z)
                distance = max(distance, abs(y) / max(tanY, 0.0001) - z)
            }
            let origin = target - basis.forward * max(distance, 0.0001)
            return Camera(
                origin: origin,
                target: target,
                up: basis.trueUp,
                verticalFieldOfViewDegrees: clampedFOV,
                projection: .perspective,
                lens: CameraLens(focusDistance: max(distance, 0.0001), apertureRadius: apertureRadius)
            )
        case .orthographic:
            let verticalScale = max(targetProjected.halfHeight, targetProjected.halfWidth / aspect) * 2
            let distance = max(
                targetProjected.depth * 0.5 + max(targetProjected.halfWidth, targetProjected.halfHeight),
                0.0001
            )
            return Camera(
                origin: target - basis.forward * distance,
                target: target,
                up: basis.trueUp,
                projection: .orthographic(verticalScale: max(verticalScale, 0.0001)),
                lens: CameraLens(focusDistance: distance, apertureRadius: apertureRadius)
            )
        }
    }

    func gpuCamera(width: Int, height: Int) -> GPUCamera {
        let aspect = Float(width) / Float(height)

        let basis = Self.cameraBasis(viewDirection: target - origin, up: up)
        let forward = basis.forward
        let right = basis.right
        let trueUp = basis.trueUp

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
            vertical: SIMD4<Float>(vertical, 0),
            lens: SIMD4<Float>(lens.apertureRadius, lens.focusDistance, 0, 0)
        )
    }

    private static func cameraBasis(
        viewDirection: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> (forward: SIMD3<Float>, right: SIMD3<Float>, trueUp: SIMD3<Float>) {
        let forward = simd_length_squared(viewDirection) > 1e-8
            ? simd_normalize(viewDirection)
            : SIMD3<Float>(0, 0, -1)
        let upVector = simd_length_squared(up) > 1e-8
            ? simd_normalize(up)
            : SIMD3<Float>(0, 1, 0)
        let helper = abs(simd_dot(forward, upVector)) < 0.999
            ? upVector
            : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(forward, helper))
        let trueUp = simd_cross(right, forward)
        return (forward, right, trueUp)
    }

    private static func projectedExtents(
        corners: [SIMD3<Float>],
        center: SIMD3<Float>,
        basis: (forward: SIMD3<Float>, right: SIMD3<Float>, trueUp: SIMD3<Float>)
    ) -> (halfWidth: Float, halfHeight: Float, depth: Float) {
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var halfWidth: Float = 0
        var halfHeight: Float = 0
        for corner in corners {
            let relative = corner - center
            halfWidth = max(halfWidth, abs(simd_dot(relative, basis.right)))
            halfHeight = max(halfHeight, abs(simd_dot(relative, basis.trueUp)))
            let z = simd_dot(relative, basis.forward)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
        }
        return (
            max(halfWidth, 0.0001),
            max(halfHeight, 0.0001),
            max(maxZ - minZ, 0.0001)
        )
    }
}
