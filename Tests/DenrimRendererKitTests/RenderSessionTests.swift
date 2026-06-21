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

        XCTAssertGreaterThan(session.accelerationDebugInfo.nodeCount, 0)
        XCTAssertTrue(session.accelerationDebugInfo.hasNodeBuffer)
        XCTAssertTrue(session.accelerationDebugInfo.hasPrimitiveIndexBuffer)
    }
}
