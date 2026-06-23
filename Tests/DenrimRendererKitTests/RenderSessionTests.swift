import Metal
import XCTest
@testable import DenrimRendererKit

final class RenderSessionTests: XCTestCase {
    func testSessionPreparesAccelerationBuffers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1)
        )

        XCTAssertEqual(session.metalRayTracingDebugInfo.supportsRayTracing, device.supportsRaytracing)

        if device.supportsRaytracing {
            XCTAssertEqual(session.accelerationDebugInfo.nodeCount, 0)
            XCTAssertFalse(session.accelerationDebugInfo.hasNodeBuffer)
            XCTAssertFalse(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
            XCTAssertTrue(session.metalRayTracingDebugInfo.hasTLAS)
            XCTAssertTrue(session.metalRayTracingDebugInfo.hasSceneBuffers)
            XCTAssertTrue(session.metalRayTracingDebugInfo.usesProductionHardwareTraversal)
        } else {
            XCTAssertGreaterThan(session.accelerationDebugInfo.nodeCount, 0)
            XCTAssertTrue(session.accelerationDebugInfo.hasNodeBuffer)
            XCTAssertTrue(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
        }
    }

    func testForcedFlatBVHSessionPreparesFallbackAccelerationBuffers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 16, height: 16, maxBounces: 1),
            accelerationMode: .flatBVH
        )

        XCTAssertGreaterThan(session.accelerationDebugInfo.nodeCount, 0)
        XCTAssertTrue(session.accelerationDebugInfo.hasNodeBuffer)
        XCTAssertTrue(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
        XCTAssertFalse(session.metalRayTracingDebugInfo.usesProductionHardwareTraversal)
    }
}
