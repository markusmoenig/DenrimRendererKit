import Foundation
import Metal
import XCTest
import DenrimRendererKit

final class DistanceVolumeReferenceRenderTests: XCTestCase {
    func testDistanceVolumeReferenceRendersPNG() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .distanceVolumeReference(),
            settings: RenderSettings(width: 56, height: 56, maxBounces: 3)
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-DistanceVolumeReference.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.render(samples: 4, to: outputURL)

        let baseline = try ImageMetricReader.baseline(named: "DistanceVolumeReference")
        let metrics = try ImageMetricReader.metrics(url: outputURL)
        XCTAssertGreaterThan(metrics.averageBrightness, 15)
        XCTAssertGreaterThan(metrics.uniqueColorEstimate, 8)
        XCTAssertGreaterThan(metrics.maxBrightness, 90)
        assertMetrics(metrics, match: baseline)
    }

    func testDistanceVolumeReferenceExposesTransparentVolumeAOVs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .distanceVolumeReference(),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 3)
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo).filter { $0.a > 0 }
        let normal = try session.pixels(for: RenderOutput.normal).filter { $0.a > 0 }
        let beauty = try session.pixels(for: RenderOutput.beauty)

        let hasSemiTransparentBlueVolume = albedo.contains { pixel in
            pixel.b > 0.75
                && pixel.r < 0.35
                && pixel.g > 0.35
                && pixel.a > 0.35
                && pixel.a < 0.50
        }
        let hasCurvedVolumeNormal = normal.contains { pixel in
            abs(pixel.r - 0.5) > 0.05
                && abs(pixel.g - 0.5) > 0.05
                && pixel.a > 0.9
        }
        let hasRearPanelThroughVolume = beauty.contains { pixel in
            pixel.g > 0.18 && pixel.r < 0.25
        }

        XCTAssertTrue(hasSemiTransparentBlueVolume)
        XCTAssertTrue(hasCurvedVolumeNormal)
        XCTAssertTrue(hasRearPanelThroughVolume)
    }
}
