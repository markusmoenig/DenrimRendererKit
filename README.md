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
* Unified `denrim` CLI rendering for SceneScript files with relative asset resolution, full render options, and benchmark timing output.
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

## Command Line Rendering

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim \
    --output ./GlossyMetal.png \
    --samples 64 \
    --quality interactive
```

`denrim` renders `.denrim` SceneScript files, resolves relative assets beside the script, writes a PNG, and prints benchmark timings to the terminal. If `--output` is omitted, the image is written to `./out.png` in the current directory.

```sh
swift run denrim --help
swift run denrim help render
swift run denrim help material
```

Useful render options include:

```sh
swift run denrim -- Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --output /tmp/denrim-dining-room.png \
    --width 320 \
    --height 180 \
    --samples 1 \
    --quality interactive \
    --backend automatic \
    --sample-radiance-clamp 16
```

Use `--output-type depth|normal|albedo|material-id|object-id|motion-vector` to export AOVs, `--denoise apple-svgf` or `--denoise simple` for denoiser comparisons, `--backend flat-bvh|metal-ray-tracing` for backend measurements, and `--report-output report.json` or `--json` for benchmark JSON.

Material previews can be rendered directly through the built-in testball scene. Preset ids and inline material definitions accept the same render options:

```sh
swift run denrim -- material matte.clay --samples 64 --quality interactive
swift run denrim -- material "0.8 0.05 0.02 roughness 0.18 clearcoat 0.65" \
    --output /tmp/custom-material.png
```

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim \
    --output /tmp/glossy.png \
    --report-output /tmp/glossy-report.json
```

A self-contained material-variant script template lives at `Examples/SceneScripts/MaterialVariants/material-variants.denrim`. It uses a tiny bundled PLY fixture so tests and examples remain portable. A rendered reference image is checked in at `Examples/Renders/material-variants.png`.

The Stanford Dragon example is `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim`. Render all persistent example references at 128 samples with:

```sh
./Examples/Tools/render-quality-examples.sh
```

The older compatibility executables still exist:

```sh
swift run denrim-render-preview ./CornellBox.png 32 512
swift run denrim-render-benchmark cornell 16 256
```

Performance benchmarks are intentionally separate from normal tests:

```sh
DENRIM_RUN_PERFORMANCE_TESTS=1 swift test --filter PerformanceBenchmarkTests
```
