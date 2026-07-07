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
            settings: RenderSettings(width: 56, height: 56, maxBounces: 2, quality: .final)
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

    func testTransparentMaterialReferenceExposesOpacityPlanningAOVs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: .transparentMaterialReference(),
            settings: RenderSettings(width: 48, height: 48, maxBounces: 2, quality: .final)
        )

        try session.renderNextSample()
        let albedo = try session.pixels(for: RenderOutput.albedo).filter { $0.a > 0 }
        let beauty = try session.pixels(for: RenderOutput.beauty)

        let hasSemiTransparentBlue = albedo.contains { pixel in
            let blueEnough = pixel.b > 0.75
            let cyanTint = pixel.r < 0.35 && pixel.g > 0.3
            let semiAlpha = pixel.a > 0.40 && pixel.a < 0.50
            return blueEnough && cyanTint && semiAlpha
        }
        let hasRearGreenThroughCutout = albedo.contains { pixel in
            let greenEnough = pixel.g > 0.75
            let notRedOrBlue = pixel.r < 0.35 && pixel.b < 0.45
            return greenEnough && notRedOrBlue && pixel.a > 0.99
        }
        let hasRearBeautyContribution = beauty.contains { pixel in
            pixel.g > 0.15 && pixel.r < 0.25
        }

        XCTAssertTrue(hasSemiTransparentBlue)
        XCTAssertTrue(hasRearGreenThroughCutout)
        XCTAssertTrue(hasRearBeautyContribution)
    }
}
