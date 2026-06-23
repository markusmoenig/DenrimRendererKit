# Denrim Material Test Ball

This directory contains a Denrim scene wrapper for Benedikt Bitterli's Material Test Ball geometry.

The original mesh scene is public domain / CC0. The bundled `textures/envmap.pfm` is not used by the Denrim scene because the light probe license is non-commercial. The Denrim version instead uses local area lights and reflection cards inside a large axis-aligned preview room. The camera looks down at the object so thumbnails see floor only, while the unseen room walls still catch indirect rays.

## Change the Preview Material

Edit `preview-material.denrim` and keep the material name `PreviewMaterial`:

```text
material PreviewMaterial preset glass.clear
material PreviewMaterial preset metal.gold roughness 0.16
material PreviewMaterial 0.8 0.05 0.02 roughness 0.18 clearcoat 0.65 clearcoatRoughness 0.035
```

Tools can also generate or replace that include file before calling `SceneScript.parse(contentsOf:)`, or use the parser's include resolver to inject a different `PreviewMaterial` definition without touching `material-testball.denrim`.

## Test Render

From the repository root:

```sh
swift run -c release denrim-render-preview Examples/Renders/material-testball.png 64 720 script beauty Examples/SceneScripts/MaterialTestBall/material-testball.denrim --width 1280
```

To render all built-in material presets as square thumbnails:

```sh
./Examples/Tools/render-built-in-materials.sh
```

Denoising is off by default. Keep preview renders raw unless you are explicitly comparing opt-in denoiser modes.
