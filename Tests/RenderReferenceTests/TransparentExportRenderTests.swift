import CoreGraphics
import Foundation
import ImageIO
import Metal
import XCTest
import DenrimRendererKit

final class TransparentExportRenderTests: XCTestCase {
    func testTransparentExportAlphaMetricsMatchBaseline() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available.")
        }

        let renderer = try DenrimRenderer(device: device)
        let session = try renderer.makeSession(
            scene: Self.floatingQuadScene(),
            settings: RenderSettings(
                width: 32,
                height: 32,
                maxBounces: 1,
                transparentBackground: true
            )
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-TransparentExportReference.png")
        try? FileManager.default.removeItem(at: outputURL)

        try session.render(samples: 1, to: outputURL)

        let baseline = try AlphaMetricReader.baseline(named: "TransparentExport")
        let metrics = try AlphaMetricReader.metrics(url: outputURL)

        XCTAssertGreaterThan(metrics.transparentPixels, 0)
        XCTAssertGreaterThan(metrics.opaquePixels, 0)
        assertAlphaMetrics(metrics, match: baseline)
    }

    private static func floatingQuadScene() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 0, 3),
                target: SIMD3<Float>(0, 0, 0),
                verticalFieldOfViewDegrees: 34
            )
        )
        let material = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.9, 0.2, 0.1),
            emission: SIMD3<Float>(0.9, 0.2, 0.1),
            emissionStrength: 1
        ))
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.45, -0.45, 0),
            SIMD3<Float>(0.45, -0.45, 0),
            SIMD3<Float>(0.45, 0.45, 0),
            SIMD3<Float>(-0.45, 0.45, 0)
        ), material: material)
        return scene
    }
}

struct AlphaMetrics: Decodable, Equatable {
    var width: Int
    var height: Int
    var minAlpha: Int
    var maxAlpha: Int
    var transparentPixels: Int
    var opaquePixels: Int
}

struct AlphaMetricTolerance: Decodable {
    var transparentPixels: Int
    var opaquePixels: Int
}

struct AlphaMetricBaseline: Decodable {
    var scene: String
    var samples: Int
    var maxBounces: Int
    var metrics: AlphaMetrics
    var tolerance: AlphaMetricTolerance
}

enum AlphaMetricReader {
    static func metrics(url: URL) throws -> AlphaMetrics {
        let data = try Data(contentsOf: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let alphas = stride(from: 3, to: pixels.count, by: 4).map { Int(pixels[$0]) }
        return AlphaMetrics(
            width: image.width,
            height: image.height,
            minAlpha: alphas.min() ?? 0,
            maxAlpha: alphas.max() ?? 0,
            transparentPixels: alphas.filter { $0 < 8 }.count,
            opaquePixels: alphas.filter { $0 > 247 }.count
        )
    }

    static func baseline(named name: String) throws -> AlphaMetricBaseline {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "ReferenceMetrics"
        ) ?? Bundle.module.url(forResource: name, withExtension: "json")

        let baselineURL = try XCTUnwrap(url)
        let data = try Data(contentsOf: baselineURL)
        return try JSONDecoder().decode(AlphaMetricBaseline.self, from: data)
    }
}

func assertAlphaMetrics(
    _ metrics: AlphaMetrics,
    match baseline: AlphaMetricBaseline,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(metrics.width, baseline.metrics.width, file: file, line: line)
    XCTAssertEqual(metrics.height, baseline.metrics.height, file: file, line: line)
    XCTAssertEqual(metrics.minAlpha, baseline.metrics.minAlpha, file: file, line: line)
    XCTAssertEqual(metrics.maxAlpha, baseline.metrics.maxAlpha, file: file, line: line)
    XCTAssertEqual(
        metrics.transparentPixels,
        baseline.metrics.transparentPixels,
        accuracy: baseline.tolerance.transparentPixels,
        file: file,
        line: line
    )
    XCTAssertEqual(
        metrics.opaquePixels,
        baseline.metrics.opaquePixels,
        accuracy: baseline.tolerance.opaquePixels,
        file: file,
        line: line
    )
}
