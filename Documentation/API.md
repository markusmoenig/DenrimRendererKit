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
* `Material`
* `MaterialID`

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

Scene compilation now builds an internal instance acceleration model with local mesh records, transformed instance records, and a top-level instance BVH. The current compute backend still materializes transformed triangles for its flat GPU BVH, while future acceleration backends can preserve transforms for TLAS / BLAS style instancing without changing this public API.

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

PNG export is visualization-oriented. Beauty output is tonemapped, albedo and normal outputs are gamma encoded for display, depth output is normalized across visible primary-hit depth values, material/object ID outputs use deterministic palette colors, and motion vectors are visualized around neutral gray. Use `pixels(for:)` when exact floating-point AOV values are needed.

## Built-In Reference Scenes

The package currently includes two built-in scenes:

* `RenderScene.cornellBox()` for global illumination, color bleeding, area light orientation, and camera sanity checks.
* `RenderScene.materialReference()` for the current diffuse, GGX-style rough metallic, and emissive material baseline.

The material reference scene is intentionally simple. It should grow as the renderer gains transmission, opacity behavior, texture, layered materials, and normal-map support.

## Scene Scripting

Small test scenes can be authored with `SceneScript`:

```swift
let scene = try SceneScript.parse(source)
let session = try renderer.makeSession(scene: scene)
```

The first script version supports comments, camera, material, quad, and box commands. It is intended for reference tests, examples, and future Denrim Render automation.
Reusable script fragments can be composed with `include` commands by passing an include resolver closure to `SceneScript.parse`.
