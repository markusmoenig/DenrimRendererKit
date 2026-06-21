# DenrimRendererKit Examples

This folder contains checked-in example scenes and rendered outputs.

The examples are meant to serve three purposes:

* Show how to author scenes with SceneScript.
* Provide stable visual references while the renderer evolves.
* Offer templates that can be copied and adapted for local benchmark assets.

## Material Variants

`SceneScripts/MaterialVariants/material-variants.denrim` renders the same mesh with several material looks. It uses a small bundled PLY fixture so the example is self-contained. The rendered reference output is `Renders/material-variants.png`.

To render the checked-in examples at reference quality:

```sh
./Examples/Tools/render-quality-examples.sh
```

The script renders 128 samples at 512 px by default. Override with `./Examples/Tools/render-quality-examples.sh 512 512` when you want a slower, cleaner render.

For a quick preview of the self-contained fixture scene:

```sh
swift run denrim-render-preview Examples/Renders/material-variants.png 32 512 script beauty Examples/SceneScripts/MaterialVariants/material-variants.denrim
```

`SceneScripts/MaterialVariants/dragon-material-variants.denrim` is the matching Stanford Dragon example. The quality render script fetches the mesh automatically. To fetch it manually, run `./Examples/Tools/fetch-stanford-dragon.sh`; it writes `Examples/Assets/StanfordDragon/Meshes/dragon_vrip_res4.ply`.

If the dragon scene feels slow, benchmark it before changing renderer internals:

```sh
swift run denrim-render-benchmark script 1 64 Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim
```
