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

* API tests validate the built-in Cornell Box scene, material GPU parameter packing including thin-film controls, built-in material preview metadata / thumbnail coverage, and render setting defaults.
* Scene script tests validate parsing, file-based parsing, comments, includes, generated textures, image texture assets with base-URL resolution, mesh assets with base-URL resolution, include files with script-relative resolution, named/grouped geometry arguments with comma separators, built-in material presets, specular color / IOR / anisotropy / clearcoat tint, attenuation color, thickness, and thin-film controls / transmission absorption / thin-walled material parameters, textured materials, quads, boxes, imported mesh instances, transformed instances, include cycle handling, useful parser errors, scripted UV/normal-map rendering, scripted image-texture rendering, and scripted imported-mesh rendering.
* CPU intersector tests provide deterministic triangle-hit reference behavior.
* Transform tests validate point transforms, normal transforms, materialized instance transforms, and top-level instance bounds during scene compilation.
* BVH builder tests validate empty builds, leaf construction, primitive remapping, bounds, and leaf size limits.
* BVH flattener tests validate GPU node metadata, primitive index buffers, emissive light-record compilation, HDRI environment importance distributions, instance acceleration records, top-level instance bounds, acceleration backend output, and guarded Metal ray tracing BLAS/TLAS resource builds.
* Metal ray tracing traversal probe tests compare hardware TLAS traversal against the CPU triangle intersector on supported devices.
* Render session tests validate that Metal sessions prepare acceleration buffers, expose public acceleration backend diagnostics, and select the production hardware traversal path on supported devices.
* Render session tests validate that automatic sessions can dispatch with empty optional shader-resource arrays, so no-texture scenes still bind the Metal buffer slots required by the hardware and flat BVH kernels.
* Render session tests validate that the public Metal texture output APIs expose accumulated output textures with the expected dimensions and format for GPU-side app presentation.
* Render session tests validate that app-owned command buffers can encode progressive samples through `encodeNextSample(into:)`, fetch the raw `liveMetalTexture(for:)` before commit for same-frame presentation, and then read back finite beauty output after the caller commits and waits.
* API tests validate that perspective and orthographic `CameraProjection` values generate the expected GPU camera plane dimensions and projection flag.
* Hardware traversal parity tests force both hardware TLAS and flat BVH backends, then compare primary depth, normal, albedo, material ID, and object ID AOVs for simple, Cornell Box, and material reference scenes.
* Beauty parity metrics compare average and maximum RGB differences between hardware TLAS and flat BVH reference-scene renders.
* Reference render metrics cover the MIS-adjusted energy distribution for Cornell Box and material scenes.
* AOV tests validate that depth, normal, albedo, material ID, object ID, and motion vector textures exist, receive primary-surface data, preserve material opacity in albedo alpha, can be read through the public output API, can be exported as PNGs, and use output-specific PNG visualization encoding.
* Denoising tests validate that the opt-in Apple MPS SVGF denoiser and experimental simple spatial denoiser allocate output textures, build their Metal support pipelines, produce finite beauty pixels, and change low-sample beauty output without altering the raw AOV contract.
* Opacity transport tests validate that fully transparent primary surfaces reveal rear albedo and emission instead of behaving like opaque blockers.
* Texture loading tests validate PNG dimensions, alpha, missing-file errors, explicit sRGB versus linear import behavior, and Radiance HDR/RGBE decoding.
* Mesh import tests validate OBJ loading, ASCII PLY loading, binary little-endian PLY loading, quad triangulation, UV/normal packing, relative face indices, and unsupported-format errors.
* Texture material tests render UV quads and verify that checker base color textures feed the albedo AOV, tangent-space normal maps feed the normal AOV, and linear texture filtering produces blended albedo.
* Transparent export tests validate raw beauty alpha, default opaque sky behavior, PNG alpha preservation, and stored transparent-export alpha metrics.
* The first render reference test renders a small Cornell Box PNG, verifies that the image is non-empty, checks basic color variation, and confirms that the ceiling light appears above the floor.
* The material reference render test renders the built-in diffuse, GGX-style rough metallic, and emissive material scene and checks that the output is bright and colorful enough to catch blank or severely broken material rendering.
* The transparent material reference render test verifies semi-transparent albedo alpha, cutout pass-through visibility, measured absorption setup, and rear-surface beauty contribution.
* The distance-volume reference render test verifies one dense SDF volume compiled from multiple primitives, transformed primitive bounds, transparent / transmissive volume AOVs, curved SDF normals, and rear-surface beauty contribution through a volume hit path.
* Cornell Box, material reference, distance-volume reference, scripted UV/normal-map, and transparent export tests compare rendered image or alpha metrics against stored tolerant baselines.

Current visual reference scenes:

* `RenderScene.cornellBox()`
* `RenderScene.materialReference()`
* `RenderScene.materialVariantReference(mesh:)`
* `RenderScene.transparentMaterialReference()`
* `RenderScene.distanceVolumeReference()`
* Scripted UV/normal-map scene authored with `SceneScript`
* Scripted image-texture quad scene authored with `SceneScript`
* Scripted imported-mesh scene authored with `SceneScript`
* Bundled material-variant script template in `Examples/SceneScripts/MaterialVariants`
* Stanford Dragon material-variant script in `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim`, backed by `Examples/Tools/fetch-stanford-dragon.sh`
* Transparent floating-quad export scene

Future reference testing should add stored PNG baselines or perceptual image comparisons once sampling, tone mapping, and denoising are stable enough.

## Performance Benchmarks

Performance tests must stay separate from ordinary correctness tests. Normal `swift test` should remain quick and deterministic; benchmark runs should be opt-in because render timing depends on device model, thermals, power mode, OS version, Metal backend, and scene size.

Current benchmark entry points:

```sh
swift run denrim-render-benchmark cornell 16 256
swift run denrim-render-benchmark materials 16 256
swift run denrim -- Examples/SceneScripts/MaterialVariants/material-variants.denrim --samples 16 --size 256 --output /tmp/material-variants.png
DENRIM_RUN_PERFORMANCE_TESTS=1 swift test --filter PerformanceBenchmarkTests
```

Benchmark results can be written as JSON:

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim --samples 1 --size 64 --output /tmp/dragon-material-variants.png --report-output Examples/Benchmarks/dragon-local-64px-1spp.json
```

Benchmarks should record:

* Apple device and GPU name.
* Scene name and asset source.
* Resolution, samples, quality, max bounces, requested backend, and active backend.
* Scene/script load time.
* Acceleration/session build time.
* Render time.
* Pixel-samples per second.
* GPU utilization notes when captured externally in Xcode Instruments.

Dragon and other heavy scenes should become performance baselines, not default CI tests. They are exactly where regressions will show up, but they need per-device thresholds rather than one global number.
