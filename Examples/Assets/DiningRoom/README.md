# DiningRoom Assets

This folder contains the imported DiningRoom scene, its textures and meshes, and the reference render from `glsl_pathtracer`.

Source scene:

```text
Examples/Assets/DiningRoom/diningroom.scene
```

Reference image rendered with `glsl_pathtracer`:

```text
Examples/Assets/DiningRoom/DiningRoom.jpg
```

Denrim SceneScript translation:

```text
Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim
```

The DiningRoom scene is intentionally manual. It is too heavy for the default test suite because it stresses OBJ loading, texture loading, BLAS/TLAS construction, and indoor lighting quality.

### Quick Smoke Render

This renders a small 320x180 image at 1 sample per pixel:

```sh
./Examples/Tools/render-dining-room-quality.sh
```

Output:

```text
/tmp/denrim-dining-room.png
```

Equivalent explicit command:

```sh
swift run -c release denrim -- \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --output /tmp/denrim-dining-room.png \
    --samples 1 \
    --width 320 \
    --height 180
```

### Authored Quality Render

The `.denrim` scene carries render defaults for `1280x720`, `512 spp`, final quality, and `Examples/Renders/DiningRoom.png`. This is slow right now, but useful when checking image quality:

```sh
./Examples/Tools/render-dining-room-quality.sh
```

Equivalent explicit command:

```sh
swift run -c release denrim -- \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim
```

### Benchmark

This records scene loading, renderer creation, session / acceleration setup, and render timing:

```sh
./Examples/Tools/benchmark-dining-room.sh
```

Equivalent explicit command:

```sh
swift run -c release denrim -- \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --output /tmp/denrim-dining-room-benchmark.png \
    --samples 1 \
    --width 320 \
    --height 180 \
    --report-output Examples/Benchmarks/dining-room-local-320x180-1spp.json
```

### Current Renderer Gaps

The Denrim translation currently approximates a few source features:

* `spectrans` glass is mapped to rough dielectric transmission with IOR/Fresnel reflection and refraction, roughness, tint, and shadow transparency.
* Exposure and tone mapping are still basic, so the window lights may not match the reference exactly.
* Denoising is off by default for this fixture. `--denoise apple-svgf` and `--denoise simple` are opt-in comparison modes only; stronger light sampling remains future work.
* The wooden boxes intentionally use a subtle derived normal map to improve their material read beyond the flatter source reference.
