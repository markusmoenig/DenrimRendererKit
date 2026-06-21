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
* Experimental Metal ray tracing BLAS/TLAS resource builds behind the acceleration backend.
* Minimal Metal ray tracing traversal probe tested against CPU intersection.
* Production Metal ray tracing traversal kernel on supported devices, with flat BVH fallback.
* Hardware-vs-flat-BVH primary AOV parity tests for simple, Cornell Box, and material reference scenes.
* Hardware-vs-flat-BVH beauty/direct-lighting parity metrics for reference scenes.
* Built-in Cornell Box, material reference, material-variant, and transparent material reference scenes.
* Material-variant reference scene that can render one caller-supplied OBJ or PLY mesh through multiple material looks.
* GGX-style rough metallic material behavior with Schlick Fresnel, material-controlled dielectric specular weight/color, IOR, and clearcoat in the Metal path tracer.
* Wavefront OBJ and PLY mesh import through `Mesh(contentsOf:)`.
* Compiled emissive triangle light list used by flat BVH and hardware TLAS direct-light sampling.
* Mesh UVs, in-memory and ImageIO-loaded base color textures, explicit sRGB/linear import, nearest/linear sampling, and tangent-space normal maps.
* Tolerant metric baselines for render reference tests.
* Stored scripted texture AOV metric baselines for albedo and normal-map regression checks.
* Transparent beauty export with alpha-preserving PNG output and stored alpha metrics.
* Internal depth, normal, albedo, material ID, object ID, and motion-vector AOV textures.
* Material opacity preserved in albedo AOV alpha and albedo PNG export.
* Fully transparent alpha-cutout camera-ray pass-through for rear-surface visibility.
* Public output readback and PNG export for beauty, depth, normal, albedo, material ID, object ID, and motion vectors.
* Output-specific PNG visualization for depth, ID, and motion-vector buffers.
* Small scene scripting language with reusable includes plus generated and image texture support for tests and automation.
* SceneScript named/grouped geometry arguments such as `position(x, y, z)` and `quad ... a(x, y, z)` with comma support.
* SceneScript OBJ/PLY mesh asset definitions and imported mesh instances.
* SceneScript file loading with script-relative includes and asset paths.
* Preview CLI rendering for SceneScript files with relative asset resolution.
* Render-driven texture material tests for checker albedo and normal-map AOV output.
* Render-driven SceneScript image texture test proving decoded assets can feed material albedo.
* MoonRay-inspired material roadmap in `Documentation/Materials.md`.

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

Arguments are output path, sample count, square image size, optional scene name, optional output name, and an optional asset path used by some scenes.

```sh
swift run denrim-render-preview ./MaterialReference.png 32 512 materials
```

Render a local OBJ or PLY mesh through the material-variant reference scene:

```sh
swift run denrim-render-preview ./DragonMaterials.png 32 512 material-variants beauty ./Assets/dragon.ply
```

Render a SceneScript file, resolving relative mesh and texture paths beside the script:

```sh
swift run denrim-render-preview ./ScriptedScene.png 32 512 script beauty ./Scenes/dragon-materials.denrim
```

A self-contained material-variant script template lives at `Examples/SceneScripts/MaterialVariants/material-variants.denrim`. It uses a tiny bundled PLY fixture so tests and examples remain portable. A rendered reference image is checked in at `Examples/Renders/material-variants.png`.

The Stanford Dragon example is `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim`. Render all persistent example references at 128 samples with:

```sh
./Examples/Tools/render-quality-examples.sh
```

Performance benchmarks are intentionally separate from normal tests:

```sh
swift run denrim-render-benchmark cornell 16 256
swift run denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim
DENRIM_RUN_PERFORMANCE_TESTS=1 swift test --filter PerformanceBenchmarkTests
```

Benchmark JSON can be written into `Examples/Benchmarks` for later comparison:

```sh
swift run denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim --output Examples/Benchmarks/dragon-local-64px-1spp.json
```

```sh
swift run denrim-render-preview ./TransparentMaterials.png 32 512 transparency
```

```sh
swift run denrim-render-preview ./MaterialAlbedo.png 32 512 materials albedo
```

```sh
swift run denrim-render-preview ./MaterialMotion.png 8 512 materials motion-vector
```
