# DenrimRendererKit API Documentation

DenrimRendererKit keeps API documentation inside the Swift Package from the beginning.

This folder is the source of truth for renderer documentation. The Denrim website in `../Denrim-Web` can consume, copy, or publish this material later, but API intent and integration guidance should be authored here first.

Documentation goals:

* Explain the stable public API.
* Keep examples close to the code.
* Document renderer settings before apps depend on them.
* Describe integration patterns for Denrim Forge, Voxel, Terrain, and Render.
* Collect architecture notes that should eventually appear on the website.

Public Swift APIs should also use DocC-compatible comments so generated API references can be published later.

## Current Public API

The first vertical slice exposes a small API around rendering a scene progressively:

```swift
import DenrimRendererKit

let renderer = try DenrimRenderer()
let scene = RenderScene.cornellBox()
let session = try renderer.makeSession(
    scene: scene,
    settings: RenderSettings(width: 512, height: 512, maxBounces: 4)
)

try session.render(samples: 64, to: outputURL)
```

Initial public types:

* `DenrimRenderer`
* `RenderSession`
* `RenderSettings`
* `RenderQuality`
* `RenderTarget`
* `RenderOutput`
* `RenderOutputPixel`
* `RenderScene`
* `Camera`
* `Transform`
* `SceneScript`
* `Ray`
* `SurfaceHit`
* `Mesh`
* `MeshInstance`
* `MeshLoadingError`
* `Material`
* `MaterialID`
* `Texture2D`
* `TextureColorEncoding`
* `TextureSamplingMode`
* `TextureLoadingError`

This API is intentionally small. The next steps are to add DocC comments to each public type, stabilize the scene-building API, and introduce internal renderer abstractions without exposing GPU implementation details.

## Scene Construction

Meshes can be added with a material and an optional transform:

```swift
var scene = RenderScene()
let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.8, 0.8)))

scene.add(
    mesh: mesh,
    material: material,
    transform: .translation(SIMD3<Float>(0, 1, 0))
)
```

Wavefront OBJ and PLY meshes can be loaded from disk:

```swift
let mesh = try Mesh(contentsOf: URL(fileURLWithPath: "Assets/dragon.ply"))
let scene = RenderScene.materialVariantReference(mesh: mesh)
```

OBJ and PLY import are intentionally the first small import paths. The PLY loader supports ASCII and binary little-endian meshes with vertex positions, optional normals / UVs, and polygon face lists. glTF/GLB import is future work. Common benchmark assets such as the Stanford Dragon should be supplied by the caller or test environment rather than vendored in the package unless their license allows redistribution in Denrim products.

Scene compilation now builds an internal instance acceleration model with local mesh records, transformed instance records, and a top-level instance BVH. The current compute backend still materializes transformed triangles for its flat GPU BVH, while future acceleration backends can preserve transforms for TLAS / BLAS style instancing without changing this public API.

## Materials and Textures

`Material` currently exposes scalar base color, emission, roughness, metallic, dielectric specular weight/color, index of refraction, clearcoat weight/roughness/IOR, opacity, plus optional in-memory texture inputs:

```swift
let checker = Texture2D.checker(
    SIMD4<Float>(1, 0, 0, 1),
    SIMD4<Float>(0, 0, 1, 1)
)
let baseColor = try Texture2D(contentsOf: baseColorURL, colorEncoding: .sRGB)
let normalMap = try Texture2D(contentsOf: normalMapURL, colorEncoding: .linear)
let filtered = Texture2D(width: 2, height: 2, pixels: pixels, samplingMode: .linear)
let material = Material(
    baseColor: SIMD3<Float>(1, 1, 1),
    specular: 1,
    specularColor: SIMD3<Float>(1, 1, 1),
    indexOfRefraction: 1.5,
    clearcoat: 0.25,
    clearcoatRoughness: 0.08,
    clearcoatIndexOfRefraction: 1.5,
    baseColorTexture: baseColor,
    normalMap: normalMap
)
```

`specular`, `specularColor`, and `indexOfRefraction` drive dielectric Fresnel reflectance for the current GGX specular lobe. `clearcoat`, `clearcoatRoughness`, and `clearcoatIndexOfRefraction` add a secondary GGX coating lobe above the base material. The default IOR of 1.5 and white specular color preserve the earlier 0.04 dielectric F0 baseline.

Textures are stored as linear RGBA `Float` pixels in row-major order. Image assets can be decoded through ImageIO with explicit `.sRGB` or `.linear` RGB handling; use `.sRGB` for ordinary color textures and `.linear` for data textures such as normal maps. The first GPU implementation samples them by mesh UVs inside both the flat BVH and hardware TLAS kernels, with nearest and bilinear sampling modes. Mipmapping and native Metal texture objects are future API work.

The current material API is intentionally small. `Documentation/Materials.md` tracks the MoonRay-inspired direction for a future Denrim Standard Surface with specular, transmission, clearcoat, sheen/fuzz, subsurface, layering, and diagnostic controls.

Future procedural material APIs should mirror SceneScript procedural commands. Denrim apps should be able to build typed procedural values in Swift, bind them to Standard Surface parameters, and get the same renderer behavior as script-authored scenes:

```swift
let noise = ProceduralValue.noise3D(scale: 18, octaves: 5, seed: 7, space: .object)
let marble = ProceduralColor.ramp(noise, stops: [
    .init(0.0, SIMD3<Float>(0.18, 0.12, 0.08)),
    .init(1.0, SIMD3<Float>(0.9, 0.82, 0.68))
])

let material = Material.standardSurface(
    baseColor: .procedural(marble),
    roughness: .constant(0.38),
    specular: .constant(0.5)
)
```

This is planned API shape, not current public API. The important contract is that procedural materials are deterministic, serializable, GPU-compiled, and shared between Swift-authored scenes and SceneScript-authored scenes.

## Render Outputs

Render sessions expose these outputs:

* `RenderOutput.beauty`
* `RenderOutput.depth`
* `RenderOutput.normal`
* `RenderOutput.albedo`
* `RenderOutput.materialID`
* `RenderOutput.objectID`
* `RenderOutput.motionVector`

Outputs can be read back as floating-point RGBA pixels:

```swift
let pixels = try session.pixels(for: .albedo)
```

Outputs can also be exported as PNG files:

```swift
try session.writePNG(output: .normal, to: normalURL)
```

Motion vectors use `RenderSettings.previousCamera` and store previous-screen minus current-screen movement in pixels in the red and green channels. If no previous camera is provided, the current scene camera is used and motion resolves to zero.

`RenderSettings.transparentBackground` makes primary camera rays that miss the scene write zero alpha to beauty output and PNG export. It defaults to `false`, preserving the opaque sky background.

Fully transparent material surfaces currently act as camera-ray cutouts, allowing primary rays to continue to the next visible surface. Semi-transparent blending, shadow transparency, and refractive transmission are future material transport work.

PNG export is visualization-oriented. Beauty output is tonemapped with alpha preservation, albedo output is gamma encoded with material opacity alpha preservation, normal output is gamma encoded for display, depth output is normalized across visible primary-hit depth values, material/object ID outputs use deterministic palette colors, and motion vectors are visualized around neutral gray. Use `pixels(for:)` when exact floating-point AOV values are needed.

## Built-In Reference Scenes

The package currently includes three built-in scenes:

* `RenderScene.cornellBox()` for global illumination, color bleeding, area light orientation, and camera sanity checks.
* `RenderScene.materialReference()` for the current diffuse, GGX-style rough metallic, and emissive material baseline.
* `RenderScene.materialVariantReference(mesh:)` for rendering one caller-supplied mesh through multiple material variants, suitable for local benchmark meshes such as a Stanford Dragon PLY or OBJ.
* `RenderScene.transparentMaterialReference()` for opacity, cutout, and future transparent / refractive material planning.

The material reference scenes are intentionally small. They should grow as the renderer gains semi-transparent transport, transmission, refraction, layered materials, and richer texture reference coverage.

## Scene Scripting

Small test scenes can be authored with `SceneScript`:

```swift
let scene = try SceneScript.parse(source)
let session = try renderer.makeSession(scene: scene)
```

The first script version supports comments, includes, camera, solid/checker/image texture definitions, OBJ/PLY mesh definitions, material texture bindings, quad, box, and imported mesh instance commands. Geometry commands support readable named groups such as `origin(0, 1.4, 4)`, `a(-2, 0, 2)`, `position(0, 0, 0)`, `scale(1, 1, 1)`, and `rotationY(0.25)` while keeping older positional forms for compatibility. Image texture and mesh paths can be resolved relative to a caller-provided `baseURL`, with explicit sRGB/linear color decoding and nearest/linear sampler selection for images. It is intended for reference tests, examples, and future Denrim Render automation.
Reusable script fragments can be composed with `include` commands by using `SceneScript.parse(contentsOf:)` for file-based scripts or by passing an include resolver closure to `SceneScript.parse`.

The preview CLI can render script files directly:

```sh
swift run denrim-render-preview ./ScriptedScene.png 32 512 script beauty ./Scenes/scene.denrim
```
