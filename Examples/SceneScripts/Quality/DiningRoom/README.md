# DiningRoom Quality Fixture

This scene is a manual quality and performance fixture translated from `Examples/Assets/DiningRoom/diningroom.scene`.
The reference render from `glsl_pathtracer` is `Examples/Assets/DiningRoom/DiningRoom.jpg`.

It is intentionally not part of the default test suite. The asset set is large enough to stress:

* OBJ import time
* texture loading
* per-mesh acceleration setup
* top-level scene acceleration
* indoor lighting and glossy material behavior

Current material caveats:

* `spectrans` glass is mapped to rough dielectric transmission with IOR/Fresnel reflection and refraction, roughness, tint, and shadow transparency.
* The light strengths are mapped directly from the source scene and may need renderer-specific tuning.
* The current renderer has no exposure control. Denoising is off by default; `--denoise apple-svgf` and `--denoise simple` are opt-in comparison modes only.
* The bucket OBJ meshes use `flipV` so the photo-based wood texture follows the same image-origin convention as the source renderer.
* The wooden boxes use a subtle `normalFrom` map derived from the albedo texture so the fixture can test material relief even though the source assets do not include authored normal maps.

Current visual-matching notes against the GLSL reference:

* Imported vertex normals are preserved for smoother porcelain, metal, and curved-object shading.
* Picture frames use a dedicated low-roughness silver material so they do not inherit the darker table/chair metal response.
* Chair-leg metal shares the polished silver trim material with the picture frames so the thin supports stay bright and shiny in this fixture.
* Chair shells use lifted dark glossy plastic rather than near-zero black so indirect light and soft highlights remain visible.
* The wooden floor uses a subtle normal map derived from the albedo texture plus clearcoat to better approximate a varnished reflective surface.
* The green wall is mildly glossy to lift the right side with reflected window and room light.
* The right bookcase boxes use a separate glossy gray material instead of the near-black decorative glossy material.
* Table glass uses a light rough dielectric transmission material so the tabletop reads as transparent while retaining Fresnel edge reflections.
* The wooden floor boxes still expose a broader renderer gap: without exposure control, richer environment/atmosphere, denoiser comparison scenes, and more mature glossy transport, their lighting can read more synthetic than the GLSL reference.

Quick smoke render:

```sh
./Examples/Tools/render-dining-room-quality.sh
```

Higher quality render:

```sh
./Examples/Tools/render-dining-room-quality.sh 256 1280 720 Examples/Renders/dining-room-256spp.png
```

Performance benchmark:

```sh
./Examples/Tools/benchmark-dining-room.sh
```

The saved Denrim baseline is intentionally a cleaner manual render, while quick previews are written to `/tmp` by default:

```text
Examples/Renders/dining-room-256spp.png
Examples/Benchmarks/dining-room-local-320x180-1spp.json
```
