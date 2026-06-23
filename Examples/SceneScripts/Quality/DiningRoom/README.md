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

* `spectrans` glass is approximated with glossy dielectric settings until transmission lands.
* The light strengths are mapped directly from the source scene and may need renderer-specific tuning.
* The current renderer has no exposure control or denoising, so low-sample renders are still noisy even with first-pass MIS.
* The bucket OBJ meshes use `flipV` so the photo-based wood texture follows the same image-origin convention as the source renderer.
* The wooden boxes use a subtle `normalFrom` map derived from the albedo texture so the fixture can test material relief even though the source assets do not include authored normal maps.

Quick smoke render:

```sh
./Examples/Tools/render-dining-room-quality.sh
```

Higher quality render:

```sh
./Examples/Tools/render-dining-room-quality.sh 128 1280 720 Examples/Renders/dining-room-128spp.png
```

Performance benchmark:

```sh
./Examples/Tools/benchmark-dining-room.sh
```

The saved Denrim baseline is intentionally a cleaner manual render, while quick previews are written to `/tmp` by default:

```text
Examples/Renders/dining-room-128spp.png
Examples/Benchmarks/dining-room-local-160x90-1spp.json
```
