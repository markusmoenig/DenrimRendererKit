import DenrimRendererKit
import Foundation
import Metal

struct BenchmarkResult: Codable {
    var createdAt: String
    var sceneName: String
    var assetPath: String?
    var width: Int
    var height: Int
    var samples: Int
    var maxBounces: Int
    var quality: String
    var sampleRadianceClamp: Float
    var requestedBackend: String
    var activeBackend: String
    var supportsMetalRayTracing: Bool
    var hasMetalTLAS: Bool
    var hasFlatBVH: Bool
    var flatBVHNodeCount: Int
    var deviceName: String
    var sceneLoadSeconds: Double
    var rendererCreateSeconds: Double
    var sessionCreateSeconds: Double
    var renderSeconds: Double
    var totalSeconds: Double
    var samplesPerSecond: Double
    var pixelSamplesPerSecond: Double
}

let arguments = CommandLine.arguments
let positionalArguments = positionalValues(in: arguments)
let sceneName = positionalArguments.count > 0 ? positionalArguments[0].lowercased() : "cornell"
let samples = positionalArguments.count > 1 ? Int(positionalArguments[1]) ?? 16 : 16
let size = positionalArguments.count > 2 ? Int(positionalArguments[2]) ?? 256 : 256
let width = optionInt(named: "--width", in: arguments) ?? size
let height = optionInt(named: "--height", in: arguments) ?? size
let qualityName = optionValue(named: "--quality", in: arguments)?.lowercased() ?? "preview"
let quality = try renderQuality(named: qualityName)
let maxBounces = max(1, optionInt(named: "--max-bounces", in: arguments) ?? defaultMaxBounces(for: quality))
let backendName = optionValue(named: "--backend", in: arguments)?.lowercased() ?? "automatic"
let accelerationMode = try renderAccelerationMode(named: backendName)
let assetPath = positionalArguments.count > 3 ? positionalArguments[3] : nil
let writeJSONToStdout = arguments.contains("--json")
let outputPath = optionValue(named: "--output", in: arguments)
let sampleRadianceClamp = optionFloat(named: "--sample-radiance-clamp", in: arguments)
let resolvedSampleRadianceClamp = sampleRadianceClamp ?? quality.defaultSampleRadianceClamp
let sampleRadianceClampDescription = sampleRadianceClamp.map { String($0) }
    ?? "\(resolvedSampleRadianceClamp) (quality-default)"

func optionValue(named name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name),
          arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

func positionalValues(in arguments: [String]) -> [String] {
    var values: [String] = []
    var skipNext = false
    for argument in arguments.dropFirst() {
        if skipNext {
            skipNext = false
            continue
        }
        switch argument {
        case "--json":
            continue
        case "--output", "--width", "--height", "--quality", "--max-bounces", "--backend",
             "--sample-radiance-clamp":
            skipNext = true
            continue
        default:
            values.append(argument)
        }
    }
    return values
}

func optionInt(named name: String, in arguments: [String]) -> Int? {
    optionValue(named: name, in: arguments).flatMap(Int.init)
}

func optionFloat(named name: String, in arguments: [String]) -> Float? {
    optionValue(named: name, in: arguments).flatMap(Float.init)
}

func renderQuality(named name: String) throws -> RenderQuality {
    switch name {
    case "preview", "fast":
        return .preview
    case "interactive", "viewport":
        return .interactive
    case "final", "export":
        return .final
    default:
        throw DenrimRendererError.invalidScene(
            "Unknown render quality: \(name). Available qualities: preview, interactive, final."
        )
    }
}

func defaultMaxBounces(for quality: RenderQuality) -> Int {
    switch quality {
    case .preview:
        return 4
    case .interactive:
        return 5
    case .final:
        return 8
    }
}

func renderAccelerationMode(named name: String) throws -> RenderAccelerationMode {
    switch name {
    case "automatic", "auto":
        return .automatic
    case "flat", "flat-bvh", "flatbvh":
        return .flatBVH
    case "metal", "metal-ray-tracing", "metalrt", "hardware", "hardware-ray-tracing":
        return .metalRayTracing
    default:
        throw DenrimRendererError.invalidScene(
            "Unknown acceleration backend: \(name). Available backends: automatic, flat-bvh, metal-ray-tracing."
        )
    }
}

func elapsed<T>(_ work: () throws -> T) rethrows -> (T, Double) {
    let start = Date()
    let value = try work()
    return (value, Date().timeIntervalSince(start))
}

func loadScene(named sceneName: String, assetPath: String?) throws -> RenderScene {
    switch sceneName {
    case "materials", "material-reference", "material":
        return .materialReference()
    case "material-variants", "material-variant-reference", "variants":
        if let assetPath {
            return try .materialVariantReference(mesh: Mesh(contentsOf: URL(fileURLWithPath: assetPath)))
        }
        return .materialVariantReference()
    case "script", "scene-script", "scenescript":
        guard let assetPath else {
            throw DenrimRendererError.invalidScene("Script benchmark requires a scene script path argument.")
        }
        return try SceneScript.parse(contentsOf: URL(fileURLWithPath: assetPath))
    case "transparent-materials", "transparent-material-reference", "transparency":
        return .transparentMaterialReference()
    case "cornell", "cornell-box":
        return .cornellBox()
    default:
        throw DenrimRendererError.invalidScene("Unknown benchmark scene: \(sceneName).")
    }
}

let (scene, sceneLoadSeconds) = try elapsed {
    try loadScene(named: sceneName, assetPath: assetPath)
}
let (renderer, rendererCreateSeconds) = try elapsed {
    try DenrimRenderer()
}
let (session, sessionCreateSeconds) = try elapsed {
    try renderer.makeSession(
        scene: scene,
        settings: RenderSettings(
            width: width,
            height: height,
            maxBounces: maxBounces,
            quality: quality,
            sampleRadianceClamp: sampleRadianceClamp
        ),
        accelerationMode: accelerationMode
    )
}
let (_, renderSeconds) = try elapsed {
    try session.render(samples: samples)
}

let pixelSamples = Double(width * height * samples)
let samplesPerSecond = renderSeconds > 0 ? Double(samples) / renderSeconds : 0
let pixelSamplesPerSecond = renderSeconds > 0 ? pixelSamples / renderSeconds : 0
let totalSeconds = sceneLoadSeconds
    + rendererCreateSeconds
    + sessionCreateSeconds
    + renderSeconds
let accelerationInfo = session.accelerationInfo

let result = BenchmarkResult(
    createdAt: ISO8601DateFormatter().string(from: Date()),
    sceneName: sceneName,
    assetPath: assetPath,
    width: width,
    height: height,
    samples: samples,
    maxBounces: maxBounces,
    quality: qualityName,
    sampleRadianceClamp: resolvedSampleRadianceClamp,
    requestedBackend: accelerationInfo.requestedMode.rawValue,
    activeBackend: accelerationInfo.activeMode.rawValue,
    supportsMetalRayTracing: accelerationInfo.supportsMetalRayTracing,
    hasMetalTLAS: accelerationInfo.hasMetalTLAS,
    hasFlatBVH: accelerationInfo.hasFlatBVH,
    flatBVHNodeCount: accelerationInfo.flatBVHNodeCount,
    deviceName: renderer.device.name,
    sceneLoadSeconds: sceneLoadSeconds,
    rendererCreateSeconds: rendererCreateSeconds,
    sessionCreateSeconds: sessionCreateSeconds,
    renderSeconds: renderSeconds,
    totalSeconds: totalSeconds,
    samplesPerSecond: samplesPerSecond,
    pixelSamplesPerSecond: pixelSamplesPerSecond
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let jsonData = try encoder.encode(result)

if let outputPath {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try jsonData.write(to: outputURL)
}

if writeJSONToStdout {
    print(String(decoding: jsonData, as: UTF8.self))
    exit(0)
}

print("DenrimRendererKit benchmark")
print("Device: \(result.deviceName)")
print("Scene: \(result.sceneName)")
if let assetPath = result.assetPath {
    print("Asset: \(assetPath)")
}
print("Resolution: \(result.width)x\(result.height)")
print("Samples: \(result.samples)")
print("Quality: \(result.quality)")
print("Max bounces: \(result.maxBounces)")
print("Sample radiance clamp: \(sampleRadianceClampDescription)")
print("Backend: requested \(result.requestedBackend), active \(result.activeBackend)")
print("Metal RT: supported \(result.supportsMetalRayTracing), TLAS \(result.hasMetalTLAS)")
print("Flat BVH: \(result.hasFlatBVH), nodes \(result.flatBVHNodeCount)")
print(String(format: "Scene load: %.4fs", result.sceneLoadSeconds))
print(String(format: "Renderer create: %.4fs", result.rendererCreateSeconds))
print(String(format: "Session create: %.4fs", result.sessionCreateSeconds))
print(String(format: "Render: %.4fs", result.renderSeconds))
print(String(format: "Total: %.4fs", result.totalSeconds))
print(String(format: "Samples/s: %.2f", result.samplesPerSecond))
print("Pixel-samples/s: \(Int(result.pixelSamplesPerSecond.rounded()))")
if let outputPath {
    print("JSON: \(outputPath)")
}
