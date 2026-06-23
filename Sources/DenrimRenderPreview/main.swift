import DenrimRendererKit
import Foundation
import simd

let arguments = CommandLine.arguments
let positionalArguments = positionalValues(in: arguments)
let outputURL: URL

if positionalArguments.count > 0 {
    outputURL = URL(fileURLWithPath: positionalArguments[0])
} else {
    outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("CornellBox.png")
}

let samples = positionalArguments.count > 1 ? Int(positionalArguments[1]) ?? 32 : 32
let size = positionalArguments.count > 2 ? Int(positionalArguments[2]) ?? 512 : 512
let width = optionInt(named: "--width", in: arguments) ?? size
let height = optionInt(named: "--height", in: arguments) ?? size
let denoiseName = optionValue(named: "--denoise", in: arguments)?.lowercased() ?? "none"
let denoiseRadius = optionInt(named: "--denoise-radius", in: arguments)
let denoiseIterations = optionInt(named: "--denoise-iterations", in: arguments)
let denoiseNormalSigma = optionFloat(named: "--denoise-normal-sigma", in: arguments)
let denoiseDepthSigma = optionFloat(named: "--denoise-depth-sigma", in: arguments)
let denoiseAlbedoSigma = optionFloat(named: "--denoise-albedo-sigma", in: arguments)
let denoiseColorSigma = optionFloat(named: "--denoise-color-sigma", in: arguments)
let sceneName = positionalArguments.count > 3 ? positionalArguments[3].lowercased() : "cornell"
let outputName = positionalArguments.count > 4 ? positionalArguments[4].lowercased() : "beauty"
let assetPath = positionalArguments.count > 5 ? positionalArguments[5] : nil
var scene: RenderScene
let output: RenderOutput
var denoiseSettings: DenoiseSettings

func optionValue(named name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name),
          arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

func optionInt(named name: String, in arguments: [String]) -> Int? {
    optionValue(named: name, in: arguments).flatMap(Int.init)
}

func optionFloat(named name: String, in arguments: [String]) -> Float? {
    optionValue(named: name, in: arguments).flatMap(Float.init)
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
        case "--width", "--height", "--denoise", "--denoise-radius", "--denoise-iterations",
             "--denoise-normal-sigma", "--denoise-depth-sigma",
             "--denoise-albedo-sigma", "--denoise-color-sigma":
            skipNext = true
            continue
        default:
            values.append(argument)
        }
    }
    return values
}

switch denoiseName {
case "none", "off", "false":
    denoiseSettings = .none
case "simple", "simple-spatial", "spatial", "experimental-simple":
    denoiseSettings = .simpleSpatial
case "apple", "mps", "svgf", "apple-svgf":
    denoiseSettings = .appleSVGF
default:
    throw DenrimRendererError.invalidScene(
        "Unknown denoiser: \(denoiseName). Available denoisers: none, experimental-simple, apple-svgf."
    )
}

if denoiseSettings.denoiser != .none {
    if let denoiseRadius {
        denoiseSettings.radius = denoiseRadius
    }
    if let denoiseIterations {
        denoiseSettings.iterations = denoiseIterations
    }
    if let denoiseNormalSigma {
        denoiseSettings.normalSigma = denoiseNormalSigma
    }
    if let denoiseDepthSigma {
        denoiseSettings.depthSigma = denoiseDepthSigma
    }
    if let denoiseAlbedoSigma {
        denoiseSettings.albedoSigma = denoiseAlbedoSigma
    }
    if let denoiseColorSigma {
        denoiseSettings.colorSigma = denoiseColorSigma
    }
}

switch sceneName {
case "materials", "material-reference", "material":
    scene = .materialReference()
case "material-variants", "material-variant-reference", "variants":
    if let assetPath {
        scene = try .materialVariantReference(mesh: Mesh(contentsOf: URL(fileURLWithPath: assetPath)))
    } else {
        scene = .materialVariantReference()
    }
case "script", "scene-script", "scenescript":
    guard let assetPath else {
        throw DenrimRendererError.invalidScene("Script preview requires a scene script path argument.")
    }
    scene = try SceneScript.parse(contentsOf: URL(fileURLWithPath: assetPath))
case "transparent-materials", "transparent-material-reference", "transparency":
    scene = .transparentMaterialReference()
case "cornell", "cornell-box":
    scene = .cornellBox()
default:
    throw DenrimRendererError.invalidScene("Unknown preview scene: \(sceneName).")
}

switch outputName {
case "beauty":
    output = .beauty
case "depth":
    output = .depth
case "normal", "normals":
    output = .normal
case "albedo":
    output = .albedo
case "material-id", "materialid":
    output = .materialID
case "object-id", "objectid":
    output = .objectID
case "motion", "motion-vector", "motionvector":
    output = .motionVector
default:
    throw DenrimRendererError.invalidScene("Unknown render output: \(outputName).")
}

let previousCamera: Camera? = output == .motionVector
    ? Camera(
        origin: scene.camera.origin + SIMD3<Float>(0.12, 0, 0),
        target: scene.camera.target + SIMD3<Float>(0.12, 0, 0),
        up: scene.camera.up,
        verticalFieldOfViewDegrees: scene.camera.verticalFieldOfViewDegrees
    )
    : nil

let renderer = try DenrimRenderer()
let session = try renderer.makeSession(
    scene: scene,
    settings: RenderSettings(
        width: width,
        height: height,
        maxBounces: 4,
        previousCamera: previousCamera,
        denoise: denoiseSettings
    )
)

try session.render(samples: samples)
try session.writePNG(output: output, to: outputURL)
print(
    "Rendered \(session.sampleCount) samples of \(sceneName) \(outputName)"
        + " (denoise: \(denoiseName), radius: \(denoiseSettings.radius),"
        + " iterations: \(denoiseSettings.iterations),"
        + " colorSigma: \(denoiseSettings.colorSigma)) to \(outputURL.path)"
)
