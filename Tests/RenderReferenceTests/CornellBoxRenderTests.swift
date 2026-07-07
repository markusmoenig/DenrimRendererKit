import Metal
import XCTest
import DenrimRendererKit

final class CornellBoxRenderTests: XCTestCase {
    func testCornellBoxRendersPNG() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .cornellBox(),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 2, quality: .final)
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-CornellBox.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.render(samples: 4, to: outputURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(byteCount, 0)
        XCTAssertEqual(session.sampleCount, 4)

        let baseline = try ImageMetricReader.baseline(named: "CornellBox")
        let metrics = try ImageMetricReader.metrics(url: outputURL)
        XCTAssertGreaterThan(metrics.averageBrightness, 3)
        XCTAssertGreaterThan(metrics.uniqueColorEstimate, 3)
        XCTAssertGreaterThan(metrics.topCenterMaxBrightness, metrics.bottomCenterMaxBrightness)
        assertMetrics(metrics, match: baseline)
    }
}
