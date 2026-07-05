import XCTest
import Foundation
@testable import DenrimRendererKit

final class PerformanceBenchmarkTests: XCTestCase {
    func testCornellBoxRenderThroughputWhenEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DENRIM_RUN_PERFORMANCE_TESTS"] == "1",
            "Set DENRIM_RUN_PERFORMANCE_TESTS=1 to run performance benchmarks."
        )

        let renderer = try DenrimRenderer()
        let scene = RenderScene.cornellBox()
        let start = Date()
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 128, height: 128, maxBounces: 4)
        )
        let sessionSeconds = Date().timeIntervalSince(start)

        let renderStart = Date()
        try session.render(samples: 8)
        let renderSeconds = Date().timeIntervalSince(renderStart)

        let pixelSamples = 128 * 128 * 8
        let pixelSamplesPerSecond = Double(pixelSamples) / max(renderSeconds, 1e-9)
        print(
            "PERF cornell device=\(renderer.device.name) sessionSeconds=\(sessionSeconds) renderSeconds=\(renderSeconds) pixelSamplesPerSecond=\(pixelSamplesPerSecond)"
        )

        XCTAssertGreaterThan(sessionSeconds, 0)
        XCTAssertGreaterThan(renderSeconds, 0)
        XCTAssertGreaterThan(pixelSamplesPerSecond, 0)
    }

    func testMaterialReferenceRenderThroughputWhenEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DENRIM_RUN_PERFORMANCE_TESTS"] == "1",
            "Set DENRIM_RUN_PERFORMANCE_TESTS=1 to run performance benchmarks."
        )

        let renderer = try DenrimRenderer()
        let scene = RenderScene.materialReference()
        let start = Date()
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 128, height: 128, maxBounces: 4)
        )
        let sessionSeconds = Date().timeIntervalSince(start)

        let renderStart = Date()
        try session.render(samples: 8)
        let renderSeconds = Date().timeIntervalSince(renderStart)

        let pixelSamples = 128 * 128 * 8
        let pixelSamplesPerSecond = Double(pixelSamples) / max(renderSeconds, 1e-9)
        print(
            "PERF materials device=\(renderer.device.name) sessionSeconds=\(sessionSeconds) renderSeconds=\(renderSeconds) pixelSamplesPerSecond=\(pixelSamplesPerSecond)"
        )

        XCTAssertGreaterThan(sessionSeconds, 0)
        XCTAssertGreaterThan(renderSeconds, 0)
        XCTAssertGreaterThan(pixelSamplesPerSecond, 0)
    }

    func testDistanceVolumeReferenceRenderThroughputWhenEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DENRIM_RUN_PERFORMANCE_TESTS"] == "1",
            "Set DENRIM_RUN_PERFORMANCE_TESTS=1 to run performance benchmarks."
        )

        let renderer = try DenrimRenderer()
        let scene = RenderScene.distanceVolumeReference()
        let start = Date()
        let session = try renderer.makeSession(
            scene: scene,
            settings: RenderSettings(width: 128, height: 128, maxBounces: 3)
        )
        let sessionSeconds = Date().timeIntervalSince(start)

        let renderStart = Date()
        try session.render(samples: 4)
        let renderSeconds = Date().timeIntervalSince(renderStart)

        let pixelSamples = 128 * 128 * 4
        let pixelSamplesPerSecond = Double(pixelSamples) / max(renderSeconds, 1e-9)
        print(
            "PERF distance-volumes device=\(renderer.device.name) sessionSeconds=\(sessionSeconds) renderSeconds=\(renderSeconds) pixelSamplesPerSecond=\(pixelSamplesPerSecond)"
        )

        XCTAssertEqual(session.accelerationInfo.activeMode, .flatBVH)
        XCTAssertGreaterThan(sessionSeconds, 0)
        XCTAssertGreaterThan(renderSeconds, 0)
        XCTAssertGreaterThan(pixelSamplesPerSecond, 0)
    }
}
