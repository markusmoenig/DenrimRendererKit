import Foundation
import Metal
import XCTest
import DenrimRendererKit

final class MaterialReferenceRenderTests: XCTestCase {
    func testMaterialReferenceRendersColorfulPNG() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .materialReference(),
            settings: RenderSettings(width: 56, height: 56, maxBounces: 2)
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-MaterialReference.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.render(samples: 4, to: outputURL)

        let baseline = try ImageMetricReader.baseline(named: "MaterialReference")
        let metrics = try ImageMetricReader.metrics(url: outputURL)
        XCTAssertGreaterThan(metrics.averageBrightness, 4)
        XCTAssertGreaterThan(metrics.uniqueColorEstimate, 6)
        XCTAssertGreaterThan(metrics.maxBrightness, 120)
        assertMetrics(metrics, match: baseline)
    }
}
