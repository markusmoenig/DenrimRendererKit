# DenrimRendererKit Examples

This folder contains checked-in example scenes and polished rendered outputs.

The examples are meant to serve three purposes:

* Show how to author scenes with SceneScript.
* Provide stable visual references while the renderer evolves.
* Offer templates that can be copied and adapted for local benchmark assets.

## Material Variants

`SceneScripts/MaterialVariants/material-variants.denrim` renders the same mesh with several material looks. It uses a small bundled PLY fixture so the example is self-contained.

`SceneScripts/MaterialVariants/glossy-metal-reference.denrim` is a focused validation scene for polished, rough, and clearcoated silver metals. It adds bright, dark, and warm reflection cards around simple geometry so glossy materials have readable reflected structure without depending on the DiningRoom asset.

`SceneScripts/MaterialTestBall/material-testball.denrim` wraps Benedikt Bitterli's public-domain Material Test Ball geometry as a single-material preview scene. Edit `SceneScripts/MaterialTestBall/preview-material.denrim`, or inject that include through the `SceneScript` API, to swap the `PreviewMaterial` definition. The Denrim scene uses the copied CC0 mesh assets in `Assets/MaterialTestBall` and a 1K Poly Haven `studio_small_01` HDRI in `Assets/HDRIs/StudioSmall01`.

To render local comparison images for the smaller example scenes:

```sh
./Examples/Tools/render-quality-examples.sh
```

The script writes to `/tmp/denrim-quality-examples` by default so `Examples/Renders` stays reserved for polished references. Override the output directory with `DENRIM_QUALITY_OUTPUT_DIR=/path/to/output`.

For a quick preview of the self-contained fixture scene:

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/material-variants.denrim --output /tmp/material-variants.png --samples 32 --size 512
```

For a quick glossy-metal preview:

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim --output /tmp/glossy-metal-reference.png --samples 64 --size 512 --quality interactive --backend automatic --sample-radiance-clamp 24
```

For a public-domain material-test-ball preview:

```sh
swift run denrim -- Examples/SceneScripts/MaterialTestBall/material-testball.denrim --output /tmp/material-testball.png --samples 64 --size 720 --width 1280
```

To render one 512x512 final-quality preview for every built-in material preset at 1024 spp:

```sh
./Examples/Tools/render-built-in-materials.sh
```

Pass sample count, size, output directory, and an optional preset id when you only want to refresh one thumbnail:

```sh
./Examples/Tools/render-built-in-materials.sh 1024 512 Examples/Renders/Materials glass.clear
```

The material previews are written to `Renders/Materials`. The script reads preset identifiers from `Sources/DenrimRendererKit/Scene/BuiltInMaterialLibrary.swift`, temporarily rewrites `SceneScripts/MaterialTestBall/preview-material.denrim` for each preset, and restores that include before exiting. Swift callers can query matching UI metadata and thumbnail paths with `BuiltInMaterialLibrary.previews`.

`SceneScripts/MaterialVariants/dragon-material-variants.denrim` is the matching Stanford Dragon example. The quality render script fetches the mesh automatically. To fetch it manually, run `./Examples/Tools/fetch-stanford-dragon.sh`; it writes `Examples/Assets/StanfordDragon/Meshes/dragon_vrip_res4.ply`.

If the dragon scene feels slow, benchmark it before changing renderer internals:

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim --output /tmp/dragon-material-variants.png --samples 1 --size 64 --quality interactive --backend automatic --sample-radiance-clamp 24
```

## Manual Quality Scenes

`SceneScripts/Quality/DiningRoom/dining-room.denrim` recreates the DiningRoom scene from `Examples/Assets/DiningRoom/diningroom.scene`. It is intentionally not part of the default example render script because the scene is large enough to expose OBJ import and acceleration setup costs.

Run a tiny smoke render:

```sh
./Examples/Tools/render-dining-room-quality.sh 1 320 180 /tmp/denrim-dining-room.png 16 interactive automatic
```

Run the authored DiningRoom default render. The script stores `HD`, `512 spp`, `final` quality, and `Renders/DiningRoom.png` as render defaults:

```sh
./Examples/Tools/render-dining-room-quality.sh
```

Run the manual benchmark:

```sh
./Examples/Tools/benchmark-dining-room.sh
```

The GLSL path tracer reference image is `Examples/Assets/DiningRoom/DiningRoom.jpg`; the current Denrim baseline is `Examples/Renders/DiningRoom.png`. `Examples/Renders` should contain only that image and the `Materials` thumbnail directory.
