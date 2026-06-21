# DenrimRendererKit

DenrimRendererKit is an open source Swift Package for a high quality Metal-based progressive path tracer used across Denrim products.

The package is currently at the first vertical slice:

* Swift Package scaffold.
* Public renderer/session/settings API.
* Built-in Cornell Box scene.
* Metal compute path tracing kernel.
* Direct emissive triangle sampling.
* Progressive accumulation.
* PNG export.
* Unit and render smoke tests.
* CPU BVH builder groundwork.
* Flattened GPU-friendly BVH buffers.
* GPU BVH traversal in the Metal kernel.
* Internal BLAS/TLAS-style instance acceleration model with materialized triangles for the current Metal path.
* Built-in Cornell Box and material reference scenes.
* GGX-style rough metallic material behavior with Schlick Fresnel in the Metal path tracer.
* Tolerant metric baselines for render reference tests.
* Internal depth, normal, albedo, material ID, object ID, and motion-vector AOV textures.
* Public output readback and PNG export for beauty, depth, normal, albedo, material ID, object ID, and motion vectors.
* Output-specific PNG visualization for depth, ID, and motion-vector buffers.
* Small scene scripting language with reusable includes for tests and automation.

## Quick Start

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

## Test

```sh
swift test
```

The render reference test creates a small Cornell Box PNG as a first visual smoke test.

## Render Preview

```sh
swift run denrim-render-preview ./CornellBox.png 32 512
```

Arguments are output path, sample count, square image size, optional scene name, and optional output name.

```sh
swift run denrim-render-preview ./MaterialReference.png 32 512 materials
```

```sh
swift run denrim-render-preview ./MaterialAlbedo.png 32 512 materials albedo
```

```sh
swift run denrim-render-preview ./MaterialMotion.png 8 512 materials motion-vector
```
