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
swift run -c release denrim-render-preview \
    /tmp/denrim-dining-room.png \
    1 \
    320 \
    script \
    beauty \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --width 320 \
    --height 180
```

### Source Resolution Render

The original `.scene` asks for `1280x720`. This is slow right now, but useful when checking image quality:

```sh
./Examples/Tools/render-dining-room-quality.sh 128 1280 720 Examples/Renders/dining-room-128spp.png
```

Equivalent explicit command:

```sh
swift run -c release denrim-render-preview \
    Examples/Renders/dining-room-128spp.png \
    128 \
    1280 \
    script \
    beauty \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --width 1280 \
    --height 720
```

### Benchmark

This records scene loading, renderer creation, session / acceleration setup, and render timing:

```sh
./Examples/Tools/benchmark-dining-room.sh
```

Equivalent explicit command:

```sh
swift run -c release denrim-render-benchmark \
    script \
    1 \
    320 \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --width 320 \
    --height 180 \
    --output Examples/Benchmarks/dining-room-local-320x180-1spp.json
```

### Current Renderer Gaps

The Denrim translation currently approximates a few source features:

* `spectrans` glass is mapped to a glossy dielectric-like material until true transmission lands.
* Exposure and tone mapping are still basic, so the window lights may not match the reference exactly.
* Low-sample renders are noisy because denoising and stronger light sampling are not implemented yet.
* The wooden boxes intentionally use a subtle derived normal map to improve their material read beyond the flatter source reference.
