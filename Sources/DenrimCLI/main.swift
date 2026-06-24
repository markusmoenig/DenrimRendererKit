import DenrimRendererKit
import Foundation
import simd

struct CLIError: Error, LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

struct RenderTimings: Codable {
    var sceneLoadSeconds: Double
    var rendererCreateSeconds: Double
    var sessionCreateSeconds: Double
    var renderSeconds: Double
    var writeSeconds: Double

    var totalSeconds: Double {
        sceneLoadSeconds
            + rendererCreateSeconds
            + sessionCreateSeconds
            + renderSeconds
            + writeSeconds
    }
}

struct RenderReport: Codable {
    var createdAt: String
    var inputPath: String
    var outputPath: String
    var output: String
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
    var denoise: String
    var deviceName: String
    var timings: RenderTimings
    var samplesPerSecond: Double
    var pixelSamplesPerSecond: Double
}

let optionsWithValues: Set<String> = [
    "--output", "-o", "--output-type", "--report-output",
    "--samples", "-s", "--size", "--width", "--height",
    "--quality", "--max-bounces", "--sample-radiance-clamp", "--backend", "--denoise",
    "--denoise-radius", "--denoise-iterations", "--denoise-normal-sigma",
    "--denoise-depth-sigma", "--denoise-albedo-sigma", "--denoise-color-sigma"
]

let rawArguments = Array(CommandLine.arguments.dropFirst())
let arguments = rawArguments.first == "--" ? Array(rawArguments.dropFirst()) : rawArguments

do {
    try run(arguments: arguments)
} catch {
    fputs("denrim: \(error.localizedDescription)\n", stderr)
    fputs("Run `denrim --help` for usage.\n", stderr)
    exit(1)
}

func run(arguments: [String]) throws {
    guard !arguments.isEmpty else {
        printGeneralHelp()
        return
    }

    if isHelp(arguments[0]) {
        printGeneralHelp()
        return
    }

    switch arguments[0] {
    case "render":
        if arguments.dropFirst().first.map(isHelp) == true {
            printRenderHelp()
            return
        }
        try render(arguments: Array(arguments.dropFirst()))
    case "material":
        if arguments.dropFirst().first.map(isHelp) == true {
            printMaterialHelp()
            return
        }
        try renderMaterial(arguments: Array(arguments.dropFirst()))
    case "help":
        if arguments.dropFirst().first == "render" {
            printRenderHelp()
        } else if arguments.dropFirst().first == "material" {
            printMaterialHelp()
        } else {
            printGeneralHelp()
        }
    default:
        if arguments[0].hasSuffix(".denrim") {
            try render(arguments: arguments)
        } else {
            throw CLIError(message: "Unknown command or input: \(arguments[0])")
        }
    }
}

func render(arguments: [String]) throws {
    guard let inputPath = firstPositional(in: arguments) else {
        throw CLIError(message: "Render requires a .denrim scene file.")
    }
    guard inputPath.hasSuffix(".denrim") else {
        throw CLIError(message: "Render input must be a .denrim scene file: \(inputPath)")
    }

    let inputURL = URL(fileURLWithPath: inputPath)
    try performRender(
        arguments: arguments,
        inputPath: inputURL.path,
        defaultOutputPath: defaultOutputPath(),
        loadScene: {
            try SceneScript.parse(contentsOf: inputURL)
        }
    )
}

func renderMaterial(arguments: [String]) throws {
    guard let materialExpression = firstPositional(in: arguments) else {
        throw CLIError(message: "Material preview requires a preset id or material definition.")
    }

    let sceneURL = try materialPreviewSceneURL()
    let baseURL = sceneURL.deletingLastPathComponent()
    let previewMaterialSource = previewMaterialDefinition(from: materialExpression)
    try performRender(
        arguments: arguments,
        inputPath: "material \(materialExpression)",
        defaultOutputPath: defaultOutputPath(),
        loadScene: {
            let source = try String(contentsOf: sceneURL, encoding: .utf8)
            return try SceneScript.parse(
                source,
                baseURL: baseURL,
                includeResolver: { includeName in
                    if includeName == "preview-material.denrim" {
                        return previewMaterialSource
                    }
                    return try String(
                        contentsOf: baseURL.appendingPathComponent(includeName),
                        encoding: .utf8
                    )
                }
            )
        }
    )
}

func performRender(
    arguments: [String],
    inputPath: String,
    defaultOutputPath: String,
    loadScene: () throws -> RenderScene
) throws {
    let outputPath = optionValue(named: "--output", short: "-o", in: arguments)
        ?? defaultOutputPath
    let outputURL = URL(fileURLWithPath: outputPath)
    let output = try renderOutput(named: optionValue(named: "--output-type", in: arguments) ?? "beauty")
    let samples = max(0, optionInt(named: "--samples", short: "-s", in: arguments) ?? 32)
    let size = max(1, optionInt(named: "--size", in: arguments) ?? 512)
    let width = max(1, optionInt(named: "--width", in: arguments) ?? size)
    let height = max(1, optionInt(named: "--height", in: arguments) ?? size)
    let qualityName = (optionValue(named: "--quality", in: arguments) ?? "preview").lowercased()
    let quality = try renderQuality(named: qualityName)
    let maxBounces = max(1, optionInt(named: "--max-bounces", in: arguments) ?? defaultMaxBounces(for: quality))
    let backendName = (optionValue(named: "--backend", in: arguments) ?? "automatic").lowercased()
    let accelerationMode = try renderAccelerationMode(named: backendName)
    let sampleRadianceClamp = optionFloat(named: "--sample-radiance-clamp", in: arguments)
    let resolvedSampleRadianceClamp = sampleRadianceClamp ?? quality.defaultSampleRadianceClamp
    let transparentBackground = optionBool(named: "--transparent-background", in: arguments)
    let denoiseName = (optionValue(named: "--denoise", in: arguments) ?? "none").lowercased()
    var denoiseSettings = try denoiseSettings(named: denoiseName)
    applyDenoiseOverrides(arguments: arguments, settings: &denoiseSettings)
    let reportOutputPath = optionValue(named: "--report-output", in: arguments)
    let writesJSON = arguments.contains("--json")

    let (scene, sceneLoadSeconds) = try elapsed(loadScene)
    let previousCamera: Camera? = output == .motionVector
        ? Camera(
            origin: scene.camera.origin + SIMD3<Float>(0.12, 0, 0),
            target: scene.camera.target + SIMD3<Float>(0.12, 0, 0),
            up: scene.camera.up,
            verticalFieldOfViewDegrees: scene.camera.verticalFieldOfViewDegrees
        )
        : nil
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
                previousCamera: previousCamera,
                transparentBackground: transparentBackground,
                denoise: denoiseSettings,
                sampleRadianceClamp: sampleRadianceClamp
            ),
            accelerationMode: accelerationMode
        )
    }
    let (_, renderSeconds) = try elapsed {
        try session.render(samples: samples)
    }
    let (_, writeSeconds) = try elapsed {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try session.writePNG(output: output, to: outputURL)
    }

    let pixelSamples = Double(width * height * samples)
    let samplesPerSecond = renderSeconds > 0 ? Double(samples) / renderSeconds : 0
    let pixelSamplesPerSecond = renderSeconds > 0 ? pixelSamples / renderSeconds : 0
    let accelerationInfo = session.accelerationInfo
    let report = RenderReport(
        createdAt: ISO8601DateFormatter().string(from: Date()),
        inputPath: inputPath,
        outputPath: outputURL.path,
        output: outputName(output),
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
        denoise: denoiseName,
        deviceName: renderer.device.name,
        timings: RenderTimings(
            sceneLoadSeconds: sceneLoadSeconds,
            rendererCreateSeconds: rendererCreateSeconds,
            sessionCreateSeconds: sessionCreateSeconds,
            renderSeconds: renderSeconds,
            writeSeconds: writeSeconds
        ),
        samplesPerSecond: samplesPerSecond,
        pixelSamplesPerSecond: pixelSamplesPerSecond
    )

    let reportData = try encodedReport(report)
    if let reportOutputPath {
        let reportURL = URL(fileURLWithPath: reportOutputPath)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try reportData.write(to: reportURL)
    }

    if writesJSON {
        print(String(decoding: reportData, as: UTF8.self))
    } else {
        printRenderReport(report)
        if let reportOutputPath {
            print("Report JSON: \(URL(fileURLWithPath: reportOutputPath).path)")
        }
    }
}

func encodedReport(_ report: RenderReport) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(report)
}

func printRenderReport(_ report: RenderReport) {
    print("Denrim render")
    print("Input: \(report.inputPath)")
    print("Output: \(report.outputPath)")
    print("AOV: \(report.output)")
    print("Device: \(report.deviceName)")
    print("Resolution: \(report.width)x\(report.height)")
    print("Samples: \(report.samples)")
    print("Quality: \(report.quality)")
    print("Max bounces: \(report.maxBounces)")
    print("Sample radiance clamp: \(report.sampleRadianceClamp)")
    print("Backend: requested \(report.requestedBackend), active \(report.activeBackend)")
    print("Metal RT: supported \(report.supportsMetalRayTracing), TLAS \(report.hasMetalTLAS)")
    print("Flat BVH: \(report.hasFlatBVH), nodes \(report.flatBVHNodeCount)")
    print("Denoise: \(report.denoise)")
    print(String(format: "Scene load: %.4fs", report.timings.sceneLoadSeconds))
    print(String(format: "Renderer create: %.4fs", report.timings.rendererCreateSeconds))
    print(String(format: "Session create: %.4fs", report.timings.sessionCreateSeconds))
    print(String(format: "Render: %.4fs", report.timings.renderSeconds))
    print(String(format: "Write PNG: %.4fs", report.timings.writeSeconds))
    print(String(format: "Total: %.4fs", report.timings.totalSeconds))
    print(String(format: "Samples/s: %.2f", report.samplesPerSecond))
    print("Pixel-samples/s: \(Int(report.pixelSamplesPerSecond.rounded()))")
}

func printGeneralHelp() {
    print(
        """
        denrim

        Usage:
          denrim render <scene.denrim> [options]
          denrim material <preset-or-definition> [options]
          denrim <scene.denrim> [options]
          denrim help render
          denrim help material

        Existing compatibility tools:
          denrim-render-preview      Older preview/image renderer.
          denrim-render-benchmark    Older timing-only benchmark runner.

        Commands:
          render    Render a SceneScript .denrim file to PNG and print benchmark timings.
          material  Render the material preview ball with a built-in preset or material definition.
          help      Show help.

        Run `denrim help render` or `denrim help material` for all options.
        """
    )
}

func printRenderHelp() {
    print(
        """
        denrim render

        Usage:
          denrim render <scene.denrim> [options]
          denrim <scene.denrim> [options]

        Output:
          -o, --output <png>                 Output PNG path. Defaults to ./out.png.
              --output-type <name>           beauty, depth, normal, albedo, material-id,
                                             object-id, motion-vector. Default: beauty.
              --transparent-background       Primary sky misses write alpha 0.

        Sampling and quality:
          -s, --samples <n>                  Progressive samples. Default: 32.
              --size <px>                    Square render size. Default: 512.
              --width <px>                   Output width. Overrides --size.
              --height <px>                  Output height. Overrides --size.
              --quality <name>               preview, interactive, final. Default: preview.
              --max-bounces <n>              Path depth. Defaults by quality:
                                             preview 4, interactive 5, final 8.
              --sample-radiance-clamp <v>    Firefly clamp. Defaults by quality:
                                             preview 10, interactive 24, final 64.
                                             Use 0 to disable.

        Backend:
              --backend <name>               automatic, flat-bvh, metal-ray-tracing.
                                             Default: automatic.

        Denoising:
              --denoise <name>               none, simple, apple-svgf. Default: none.
              --denoise-radius <n>           Spatial denoise radius.
              --denoise-iterations <n>       Denoise iterations.
              --denoise-normal-sigma <v>     Normal edge sigma.
              --denoise-depth-sigma <v>      Depth edge sigma.
              --denoise-albedo-sigma <v>     Albedo edge sigma.
              --denoise-color-sigma <v>      Color sigma.

        Reporting:
              --json                         Print the render benchmark report as JSON.
              --report-output <json>         Also write the benchmark report to JSON.
          -h, --help                         Show this help.

        Examples:
          denrim Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim \\
              --output /tmp/glossy.png --samples 64 --quality interactive

          denrim render Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \\
              --output /tmp/dining.png --width 320 --height 180 --backend metal-ray-tracing
        """
    )
}

func printMaterialHelp() {
    print(
        """
        denrim material

        Usage:
          denrim material <preset-id> [options]
          denrim material "<r g b material-options...>" [options]

        Examples:
          denrim material matte.clay
          denrim material metal.gold --samples 64 --quality interactive
          denrim material "0.8 0.05 0.02 roughness 0.18 clearcoat 0.65" \\
              --output /tmp/custom-material.png

        The command renders Examples/SceneScripts/MaterialTestBall/material-testball.denrim
        while injecting `PreviewMaterial` without modifying preview-material.denrim.

        It accepts the same render options as `denrim render`, including:
          --output, --samples, --size, --width, --height, --quality,
          --max-bounces, --backend, --sample-radiance-clamp, --denoise,
          --json, and --report-output.

        If --output is omitted, the image is written to ./out.png.
        """
    )
}

func elapsed<T>(_ work: () throws -> T) rethrows -> (T, Double) {
    let start = Date()
    let value = try work()
    return (value, Date().timeIntervalSince(start))
}

func isHelp(_ value: String) -> Bool {
    value == "--help" || value == "-h"
}

func firstPositional(in arguments: [String]) -> String? {
    var skipNext = false
    for argument in arguments {
        if skipNext {
            skipNext = false
            continue
        }
        if optionsWithValues.contains(argument) {
            skipNext = true
            continue
        }
        if argument.hasPrefix("-") {
            continue
        }
        return argument
    }
    return nil
}

func optionValue(named name: String, short: String? = nil, in arguments: [String]) -> String? {
    for (index, argument) in arguments.enumerated() {
        guard argument == name || argument == short else {
            continue
        }
        guard arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
    return nil
}

func optionInt(named name: String, short: String? = nil, in arguments: [String]) -> Int? {
    optionValue(named: name, short: short, in: arguments).flatMap(Int.init)
}

func optionFloat(named name: String, in arguments: [String]) -> Float? {
    optionValue(named: name, in: arguments).flatMap(Float.init)
}

func optionBool(named name: String, in arguments: [String]) -> Bool {
    arguments.contains(name)
}

func materialPreviewSceneURL() throws -> URL {
    let relativePath = "Examples/SceneScripts/MaterialTestBall/material-testball.denrim"
    var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    for _ in 0..<8 {
        let candidate = directory.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let parent = directory.deletingLastPathComponent()
        if parent.path == directory.path {
            break
        }
        directory = parent
    }

    throw CLIError(
        message: "Could not find \(relativePath). Run material previews from the DenrimRendererKit checkout."
    )
}

func previewMaterialDefinition(from expression: String) -> String {
    if BuiltInMaterialLibrary.material(named: expression) != nil {
        return "material PreviewMaterial preset \(expression)\n"
    }

    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased().hasPrefix("material ") {
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 3 {
            return "material PreviewMaterial \(parts.dropFirst(2).joined(separator: " "))\n"
        }
    }

    return "material PreviewMaterial \(trimmed)\n"
}

func defaultOutputPath() -> String {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("out.png")
        .path
}

func renderOutput(named name: String) throws -> RenderOutput {
    switch name.lowercased() {
    case "beauty":
        return .beauty
    case "depth":
        return .depth
    case "normal", "normals":
        return .normal
    case "albedo":
        return .albedo
    case "material-id", "materialid":
        return .materialID
    case "object-id", "objectid":
        return .objectID
    case "motion", "motion-vector", "motionvector":
        return .motionVector
    default:
        throw CLIError(message: "Unknown output type: \(name)")
    }
}

func outputName(_ output: RenderOutput) -> String {
    switch output {
    case .beauty:
        return "beauty"
    case .depth:
        return "depth"
    case .normal:
        return "normal"
    case .albedo:
        return "albedo"
    case .materialID:
        return "material-id"
    case .objectID:
        return "object-id"
    case .motionVector:
        return "motion-vector"
    }
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
        throw CLIError(message: "Unknown quality: \(name)")
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
        throw CLIError(message: "Unknown backend: \(name)")
    }
}

func denoiseSettings(named name: String) throws -> DenoiseSettings {
    switch name {
    case "none", "off", "false":
        return .none
    case "simple", "simple-spatial", "spatial", "experimental-simple":
        return .simpleSpatial
    case "apple", "mps", "svgf", "apple-svgf":
        return .appleSVGF
    default:
        throw CLIError(message: "Unknown denoiser: \(name)")
    }
}

func applyDenoiseOverrides(arguments: [String], settings: inout DenoiseSettings) {
    if let value = optionInt(named: "--denoise-radius", in: arguments) {
        settings.radius = value
    }
    if let value = optionInt(named: "--denoise-iterations", in: arguments) {
        settings.iterations = value
    }
    if let value = optionFloat(named: "--denoise-normal-sigma", in: arguments) {
        settings.normalSigma = value
    }
    if let value = optionFloat(named: "--denoise-depth-sigma", in: arguments) {
        settings.depthSigma = value
    }
    if let value = optionFloat(named: "--denoise-albedo-sigma", in: arguments) {
        settings.albedoSigma = value
    }
    if let value = optionFloat(named: "--denoise-color-sigma", in: arguments) {
        settings.colorSigma = value
    }
}
