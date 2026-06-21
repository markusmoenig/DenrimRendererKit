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

* API tests validate the built-in Cornell Box scene and render setting defaults.
* Scene script tests validate parsing, comments, includes, materials, quads, boxes, transformed instances, include cycle handling, and useful parser errors.
* CPU intersector tests provide deterministic triangle-hit reference behavior.
* Transform tests validate point transforms, normal transforms, materialized instance transforms, and top-level instance bounds during scene compilation.
* BVH builder tests validate empty builds, leaf construction, primitive remapping, bounds, and leaf size limits.
* BVH flattener tests validate GPU node metadata, primitive index buffers, instance acceleration records, top-level instance bounds, and acceleration backend output.
* Render session tests validate that Metal sessions prepare acceleration buffers.
* AOV tests validate that depth, normal, albedo, material ID, object ID, and motion vector textures exist, receive primary-surface data, can be read through the public output API, can be exported as PNGs, and use output-specific PNG visualization encoding.
* The first render reference test renders a small Cornell Box PNG, verifies that the image is non-empty, checks basic color variation, and confirms that the ceiling light appears above the floor.
* The material reference render test renders the built-in diffuse, GGX-style rough metallic, and emissive material scene and checks that the output is bright and colorful enough to catch blank or severely broken material rendering.
* Cornell Box and material reference tests compare rendered image metrics against stored tolerant baselines.

Current visual reference scenes:

* `RenderScene.cornellBox()`
* `RenderScene.materialReference()`

Future reference testing should add stored PNG baselines or perceptual image comparisons once sampling, tone mapping, and denoising are stable enough.
