import Metal
import simd
import XCTest
@testable import DenrimRendererKit

final class MetalRayTracingTraversalProbeTests: XCTestCase {
    func testHardwareTraversalProbeMatchesCPUIntersector() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }
        guard device.supportsRaytracing else {
            throw XCTSkip("Metal ray tracing is not supported on this device.")
        }

        let triangle = Mesh(
            vertices: [
                SIMD3<Float>(-1, -1, 0),
                SIMD3<Float>(1, -1, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            indices: [0, 1, 2]
        )
        var scene = RenderScene()
        let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(1, 1, 1)))
        scene.add(mesh: triangle, material: material)

        let ray = Ray(
            origin: SIMD3<Float>(0, 0, 1),
            direction: SIMD3<Float>(0, 0, -1)
        )
        let cpuHit = try XCTUnwrap(CPUIntersector.closestHit(
            ray: ray,
            mesh: triangle,
            material: material
        ))
        let hardwareHit = try XCTUnwrap(MetalRayTracingTraversalProbe(device: device).trace(
            scene: scene,
            ray: ray
        ))

        XCTAssertTrue(hardwareHit.hit)
        XCTAssertEqual(hardwareHit.distance, cpuHit.distance, accuracy: 0.0005)
        XCTAssertEqual(hardwareHit.primitiveID, UInt32(cpuHit.primitiveIndex))
        XCTAssertEqual(hardwareHit.instanceID, 0)
    }
}
