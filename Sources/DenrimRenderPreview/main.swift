import DenrimRendererKit
import Foundation
import simd

let arguments = CommandLine.arguments
let outputURL: URL

if arguments.count > 1 {
    outputURL = URL(fileURLWithPath: arguments[1])
} else {
    outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("CornellBox.png")
}

let samples = arguments.count > 2 ? Int(arguments[2]) ?? 32 : 32
let size = arguments.count > 3 ? Int(arguments[3]) ?? 512 : 512
let sceneName = arguments.count > 4 ? arguments[4].lowercased() : "cornell"
let outputName = arguments.count > 5 ? arguments[5].lowercased() : "beauty"
let assetPath = arguments.count > 6 ? arguments[6] : nil
var scene: RenderScene
let output: RenderOutput

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
    settings: RenderSettings(width: size, height: size, maxBounces: 4, previousCamera: previousCamera)
)

try session.render(samples: samples)
try session.writePNG(output: output, to: outputURL)
print("Rendered \(session.sampleCount) samples of \(sceneName) \(outputName) to \(outputURL.path)")
