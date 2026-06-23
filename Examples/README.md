# DenrimRendererKit Examples

This folder contains checked-in example scenes and rendered outputs.

The examples are meant to serve three purposes:

* Show how to author scenes with SceneScript.
* Provide stable visual references while the renderer evolves.
* Offer templates that can be copied and adapted for local benchmark assets.

## Material Variants

`SceneScripts/MaterialVariants/material-variants.denrim` renders the same mesh with several material looks. It uses a small bundled PLY fixture so the example is self-contained. The rendered reference output is `Renders/material-variants.png`.

`SceneScripts/MaterialVariants/glossy-metal-reference.denrim` is a focused validation scene for polished, rough, and clearcoated silver metals. It adds bright, dark, and warm reflection cards around simple geometry so glossy materials have readable reflected structure without depending on the DiningRoom asset. The rendered reference output is `Renders/glossy-metal-reference.png`.

To render the checked-in examples at reference quality:

```sh
./Examples/Tools/render-quality-examples.sh
```

The script renders 128 samples at 512 px by default. Override with `./Examples/Tools/render-quality-examples.sh 512 512` when you want a slower, cleaner render.

For a quick preview of the self-contained fixture scene:

```sh
swift run denrim-render-preview Examples/Renders/material-variants.png 32 512 script beauty Examples/SceneScripts/MaterialVariants/material-variants.denrim
```

For a quick glossy-metal preview:

```sh
swift run denrim-render-preview Examples/Renders/glossy-metal-reference.png 64 512 script beauty Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim
```

`SceneScripts/MaterialVariants/dragon-material-variants.denrim` is the matching Stanford Dragon example. The quality render script fetches the mesh automatically. To fetch it manually, run `./Examples/Tools/fetch-stanford-dragon.sh`; it writes `Examples/Assets/StanfordDragon/Meshes/dragon_vrip_res4.ply`.

If the dragon scene feels slow, benchmark it before changing renderer internals:

```sh
swift run denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim
```

## Manual Quality Scenes

`SceneScripts/Quality/DiningRoom/dining-room.denrim` recreates the DiningRoom scene from `Examples/Assets/DiningRoom/diningroom.scene`. It is intentionally not part of the default example render script because the scene is large enough to expose OBJ import and acceleration setup costs.

Run a tiny smoke render:

```sh
./Examples/Tools/render-dining-room-quality.sh
```

Run the manual benchmark:

```sh
./Examples/Tools/benchmark-dining-room.sh
```

The GLSL path tracer reference image is `Examples/Assets/DiningRoom/DiningRoom.jpg`; the current Denrim baseline is `Examples/Renders/dining-room-256spp.png`. Quick smoke renders default to `/tmp/denrim-dining-room.png` so `Examples/Renders` stays reserved for polished references.
