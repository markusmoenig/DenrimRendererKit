# Testing and Visual Evaluation

DenrimRendererKit should test both behavior and image quality.

The renderer needs ordinary automated tests for API and data structures, plus render-based visual evaluation for scenes where correctness is visible rather than purely numeric.

Test categories:

* Unit tests for scene, camera, transforms, materials, and BVH code.
* CPU reference intersection tests.
* GPU render smoke tests.
* Reference scene render tests.
* Tolerant image comparisons for progressive path tracing output.
* Performance benchmarks for sample throughput and acceleration builds.

Initial visual test scenes:

* Cornell Box for global illumination and color bleeding.
* Material ball grid for roughness, metallic, specular, emission, and opacity.
* Area light scene for soft shadows.
* Transparent export scene.
* Smooth normals mesh scene.
* UV texture scene for base color and normal-map correctness.
* Instance transform scene.

Future visual test scenes:

* HDR environment lighting scene.
* Sponza-style complex indirect lighting scene.
* Terrain heightmap scene.
* Bounded SDF primitive scene.
* Mixed geometry scene.
* Atmosphere and fog scene.

Reference images should support tolerant comparison because path tracing, denoising, hardware, and sampling changes can all alter output while still improving the renderer.

Current reference tests use stored metric baselines rather than pixel-perfect PNG baselines.

Each reference render stores:

* Scene name
* Sample count
* Bounce count
* Output dimensions
* Average brightness
* Maximum brightness
* Estimated color variation
* Regional brightness checks
* Per-metric tolerances

This catches blank renders, major lighting shifts, orientation bugs, and severe material regressions while remaining tolerant of low-sample path tracing noise.

Current test foundation:

* API tests validate the built-in Cornell Box scene, material GPU parameter packing, and render setting defaults.
* Scene script tests validate parsing, file-based parsing, comments, includes, generated textures, image texture assets with base-URL resolution, mesh assets with base-URL resolution, include files with script-relative resolution, named/grouped geometry arguments with comma separators, specular color / IOR / clearcoat material parameters, textured materials, quads, boxes, imported mesh instances, transformed instances, include cycle handling, useful parser errors, scripted UV/normal-map rendering, scripted image-texture rendering, and scripted imported-mesh rendering.
* CPU intersector tests provide deterministic triangle-hit reference behavior.
* Transform tests validate point transforms, normal transforms, materialized instance transforms, and top-level instance bounds during scene compilation.
* BVH builder tests validate empty builds, leaf construction, primitive remapping, bounds, and leaf size limits.
* BVH flattener tests validate GPU node metadata, primitive index buffers, emissive triangle light-list compilation, instance acceleration records, top-level instance bounds, acceleration backend output, and guarded Metal ray tracing BLAS/TLAS resource builds.
* Metal ray tracing traversal probe tests compare hardware TLAS traversal against the CPU triangle intersector on supported devices.
* Render session tests validate that Metal sessions prepare acceleration buffers and select the production hardware traversal path on supported devices.
* Hardware traversal parity tests force both hardware TLAS and flat BVH backends, then compare primary depth, normal, albedo, material ID, and object ID AOVs for simple, Cornell Box, and material reference scenes.
* Beauty parity metrics compare average and maximum RGB differences between hardware TLAS and flat BVH reference-scene renders.
* AOV tests validate that depth, normal, albedo, material ID, object ID, and motion vector textures exist, receive primary-surface data, preserve material opacity in albedo alpha, can be read through the public output API, can be exported as PNGs, and use output-specific PNG visualization encoding.
* Opacity transport tests validate that fully transparent primary surfaces reveal rear albedo and emission instead of behaving like opaque blockers.
* Texture loading tests validate PNG dimensions, alpha, missing-file errors, and explicit sRGB versus linear import behavior.
* Mesh import tests validate OBJ loading, ASCII PLY loading, binary little-endian PLY loading, quad triangulation, UV/normal packing, relative face indices, and unsupported-format errors.
* Texture material tests render UV quads and verify that checker base color textures feed the albedo AOV, tangent-space normal maps feed the normal AOV, and linear texture filtering produces blended albedo.
* Transparent export tests validate raw beauty alpha, default opaque sky behavior, PNG alpha preservation, and stored transparent-export alpha metrics.
* The first render reference test renders a small Cornell Box PNG, verifies that the image is non-empty, checks basic color variation, and confirms that the ceiling light appears above the floor.
* The material reference render test renders the built-in diffuse, GGX-style rough metallic, and emissive material scene and checks that the output is bright and colorful enough to catch blank or severely broken material rendering.
* The transparent material reference render test verifies semi-transparent albedo alpha, cutout pass-through visibility, and rear-surface beauty contribution.
* Cornell Box, material reference, scripted UV/normal-map, and transparent export tests compare rendered image or alpha metrics against stored tolerant baselines.

Current visual reference scenes:

* `RenderScene.cornellBox()`
* `RenderScene.materialReference()`
* `RenderScene.materialVariantReference(mesh:)`
* `RenderScene.transparentMaterialReference()`
* Scripted UV/normal-map scene authored with `SceneScript`
* Scripted image-texture quad scene authored with `SceneScript`
* Scripted imported-mesh scene authored with `SceneScript`
* Bundled material-variant script template in `Examples/SceneScripts/MaterialVariants` with rendered output in `Examples/Renders`
* Stanford Dragon material-variant script in `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim`, backed by `Examples/Tools/fetch-stanford-dragon.sh`
* Transparent floating-quad export scene

Future reference testing should add stored PNG baselines or perceptual image comparisons once sampling, tone mapping, and denoising are stable enough.

## Performance Benchmarks

Performance tests must stay separate from ordinary correctness tests. Normal `swift test` should remain quick and deterministic; benchmark runs should be opt-in because render timing depends on device model, thermals, power mode, OS version, Metal backend, and scene size.

Current benchmark entry points:

```sh
swift run denrim-render-benchmark cornell 16 256
swift run denrim-render-benchmark materials 16 256
swift run denrim-render-benchmark script 16 256 Examples/SceneScripts/MaterialVariants/material-variants.denrim
DENRIM_RUN_PERFORMANCE_TESTS=1 swift test --filter PerformanceBenchmarkTests
```

Benchmark results can be written as JSON:

```sh
swift run denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim --output Examples/Benchmarks/dragon-local-64px-1spp.json
```

Benchmarks should record:

* Apple device and GPU name.
* Scene name and asset source.
* Resolution, samples, max bounces, and backend.
* Scene/script load time.
* Acceleration/session build time.
* Render time.
* Pixel-samples per second.
* GPU utilization notes when captured externally in Xcode Instruments.

Dragon and other heavy scenes should become performance baselines, not default CI tests. They are exactly where regressions will show up, but they need per-device thresholds rather than one global number.
