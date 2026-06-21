import CoreGraphics
import Foundation
import ImageIO
import XCTest

struct ImageMetrics: Decodable, Equatable {
    var width: Int
    var height: Int
    var averageBrightness: Double
    var maxBrightness: Double
    var uniqueColorEstimate: Int
    var topCenterMaxBrightness: Double
    var bottomCenterMaxBrightness: Double
}

struct ImageMetricTolerance: Decodable {
    var averageBrightness: Double
    var maxBrightness: Double
    var uniqueColorEstimate: Int
    var regionalBrightness: Double
}

struct ImageMetricBaseline: Decodable {
    var scene: String
    var samples: Int
    var maxBounces: Int
    var metrics: ImageMetrics
    var tolerance: ImageMetricTolerance
}

enum ImageMetricReader {
    static func metrics(url: URL) throws -> ImageMetrics {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Could not decode rendered PNG.")
            return emptyMetrics
        }

        return metrics(image: image)
    }

    static func baseline(named name: String) throws -> ImageMetricBaseline {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "ReferenceMetrics"
        ) ?? Bundle.module.url(forResource: name, withExtension: "json")

        let baselineURL = try XCTUnwrap(url)
        let data = try Data(contentsOf: baselineURL)
        return try JSONDecoder().decode(ImageMetricBaseline.self, from: data)
    }

    private static func metrics(image: CGImage) -> ImageMetrics {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create image inspection context.")
            return emptyMetrics
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var brightness = 0.0
        var maxBrightness = 0.0
        var colors = Set<Int>()
        var topCenterMaxBrightness = 0.0
        var bottomCenterMaxBrightness = 0.0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let pixelBrightness = Double(red + green + blue) / 3.0
            brightness += pixelBrightness
            maxBrightness = max(maxBrightness, pixelBrightness)
            colors.insert((red / 32) << 16 | (green / 32) << 8 | (blue / 32))

            let pixel = index / 4
            let x = pixel % width
            let y = pixel / width
            let centerMinX = width * 3 / 8
            let centerMaxX = width * 5 / 8

            if x >= centerMinX && x <= centerMaxX && y < height / 4 {
                topCenterMaxBrightness = max(topCenterMaxBrightness, pixelBrightness)
            }

            if x >= centerMinX && x <= centerMaxX && y > height * 3 / 4 {
                bottomCenterMaxBrightness = max(bottomCenterMaxBrightness, pixelBrightness)
            }
        }

        return ImageMetrics(
            width: width,
            height: height,
            averageBrightness: brightness / Double(width * height),
            maxBrightness: maxBrightness,
            uniqueColorEstimate: colors.count,
            topCenterMaxBrightness: topCenterMaxBrightness,
            bottomCenterMaxBrightness: bottomCenterMaxBrightness
        )
    }

    private static var emptyMetrics: ImageMetrics {
        ImageMetrics(
            width: 0,
            height: 0,
            averageBrightness: 0,
            maxBrightness: 0,
            uniqueColorEstimate: 0,
            topCenterMaxBrightness: 0,
            bottomCenterMaxBrightness: 0
        )
    }
}

func assertMetrics(
    _ metrics: ImageMetrics,
    match baseline: ImageMetricBaseline,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(metrics.width, baseline.metrics.width, file: file, line: line)
    XCTAssertEqual(metrics.height, baseline.metrics.height, file: file, line: line)
    XCTAssertEqual(
        metrics.averageBrightness,
        baseline.metrics.averageBrightness,
        accuracy: baseline.tolerance.averageBrightness,
        file: file,
        line: line
    )
    XCTAssertEqual(
        metrics.maxBrightness,
        baseline.metrics.maxBrightness,
        accuracy: baseline.tolerance.maxBrightness,
        file: file,
        line: line
    )
    XCTAssertEqual(
        metrics.uniqueColorEstimate,
        baseline.metrics.uniqueColorEstimate,
        accuracy: baseline.tolerance.uniqueColorEstimate,
        file: file,
        line: line
    )
    XCTAssertEqual(
        metrics.topCenterMaxBrightness,
        baseline.metrics.topCenterMaxBrightness,
        accuracy: baseline.tolerance.regionalBrightness,
        file: file,
        line: line
    )
    XCTAssertEqual(
        metrics.bottomCenterMaxBrightness,
        baseline.metrics.bottomCenterMaxBrightness,
        accuracy: baseline.tolerance.regionalBrightness,
        file: file,
        line: line
    )
}
