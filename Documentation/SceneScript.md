# Scene Script

DenrimRendererKit includes a small line-based scene scripting language for reference scenes and lightweight renderer automation.

The first version is intentionally small. It supports:

* Comments with `#`.
* `include` with an application-provided resolver.
* `render` defaults for CLI and host applications.
* `camera`.
* `environment`.
* `texture`.
* `mesh`.
* `material`.
* `sdf` / `volume`.
* `quad`.
* `box`.
* `instance`.

Example:

```text
# render [output path] [outputType name] [size hd|fhd|uhd|px]
#        [width px] [height px] [samples n] [spp n]
#        [quality preview|interactive|final] [maxBounces n]
#        [backend automatic|flat-bvh|metal-ray-tracing]
#        [sampleRadianceClamp value] [transparentBackground 0|1]
#        [denoise none|simple|apple-svgf] [sdfResolution n]
render output Renders/Scene.png size hd spp 512 quality final sdfResolution 72

# camera origin(x, y, z) target(x, y, z) fov(degrees)
camera origin(0, 1.4, 4.0) target(0, 0.6, 0) fov(42)

# environment sky
# environment image path [intensity value] [rotationY radians] [maxRadiance value]
environment image Textures/studio_small_01_1k.hdr intensity 0.9 rotationY 2.9 maxRadiance 6

# material name r g b
material floor 0.7 0.7 0.65

# texture name solid r g b a [nearest|linear]
texture tangentRight solid 1 0.5 0.5 1 nearest

# texture name checker ar ag ab aa br bg bb ba [nearest|linear]
texture checker checker 1 0 0 1 0 0 1 1 linear

# texture name image path [color srgb|linear] [sampler nearest|linear]
texture loadedAlbedo image Textures/albedo.png color srgb sampler linear

# texture name normalFrom sourceTexture [strength value]
texture woodNormal normalFrom loadedAlbedo strength 0.65

# mesh name path [flipV]
mesh dragon Meshes/dragon.ply
mesh objWithBottomLeftUVs Meshes/model.obj flipV

# material name r g b emitR emitG emitB strength
material light 1 1 1 1 0.9 0.7 8

# material name r g b [roughness value] [metallic value]
# material name preset preset-id [overrides...]
#                    [specular value] [specularColor r g b] [ior value] [opacity value]
#                    [anisotropy value] [specularAnisotropy value]
#                    [transmission value] [spectrans value]
#                    [transmissionColor r g b] [transmissionRoughness value] [transmissionIOR value]
#                    [absorptionColor r g b] [absorptionDistance value]
#                    [thinWalled 0|1]
#                    [volumeScattering value] [volumeScatteringColor r g b]
#                    [volumeScatteringDistance value] [volumeAnisotropy value]
#                    [clearcoat value] [clearcoatColor r g b] [clearcoatTint r g b]
#                    [clearcoatAttenuationColor r g b] [clearcoatThickness value]
#                    [clearcoatRoughness value] [clearcoatIOR value]
#                    [thinFilm value] [thinFilmThickness value] [thinFilmIOR value]
#                    [sheen value] [sheenColor r g b] [sheenRoughness value]
#                    [subsurface value] [subsurfaceColor r g b]
#                    [subsurfaceRadius r g b] [subsurfaceScale value]
#                    [subsurfaceAnisotropy value]
#                    [emission r g b strength] [baseColorTexture name] [normalMap name]
material brushedGold 0.95 0.78 0.35 roughness 0.18 metallic 1 specular 1 specularColor 1 0.86 0.7 ior 1.5 anisotropy 0.65 clearcoat 0.25 clearcoatColor 1 0.92 0.72 clearcoatAttenuationColor 0.95 0.78 0.48 clearcoatThickness 0.25 clearcoatRoughness 0.08 clearcoatIOR 1.5
material amberFilm 0.95 0.28 0.035 roughness 0.22 specular 0.65 clearcoat 0.95 clearcoatColor 1 0.74 0.32 clearcoatRoughness 0.035 thinFilm 0.85 thinFilmThickness 430 thinFilmIOR 1.38
material velvet 0.42 0.16 0.72 roughness 0.7 sheen 0.65 sheenColor 0.9 0.72 1 sheenRoughness 0.78
material warmSkin 0.82 0.52 0.38 roughness 0.56 specular 0.38 subsurface 0.82 subsurfaceColor 0.95 0.48 0.32 subsurfaceRadius 1.0 0.42 0.24 subsurfaceScale 0.34 subsurfaceAnisotropy 0.18
material glass 0.713 0.8 0.8 roughness 0.01 specular 1 ior 1.45 transmission 1 transmissionColor 0.72 0.86 1 transmissionRoughness 0.04 transmissionIOR 1.45 absorptionColor 0.64 0.82 1 absorptionDistance 0.8
material milk 0.98 0.96 0.88 roughness 0.68 specular 0.18 ior 1.35 transmission 0.46 transmissionColor 0.99 0.985 0.94 transmissionRoughness 0.58 transmissionIOR 1.35 absorptionColor 0.7 0.72 0.58 absorptionDistance 0.62 volumeScattering 0.76 volumeScatteringColor 0.98 0.97 0.9 volumeScatteringDistance 0.5 volumeAnisotropy 0.25
material thinPane 0.7 0.85 1 roughness 0.02 specular 1 transmission 1 transmissionColor 0.8 0.92 1 thinWalled 1
material textured 1 1 1 baseColorTexture checker normalMap tangentRight

# Built-in presets can be queried in Swift through BuiltInMaterialLibrary.
# Preset forms accept the same override keywords as numeric material definitions.
material brushedPreset preset metal.brushed-aluminum roughness 0.14
material amberPreset preset coating.iridescent-amber
material glassPreset preset glass.thin-pane
material warmPanel preset emission.warm-panel emission 1 0.82 0.55 6

# SDF-heavy products should use plain materials plus generic material fields.
material mossy 0.12 0.38 0.12 roughness 0.86 specular 0.22 sheen 0.28 subsurface 0.18
material wet 0.55 0.72 0.82 roughness 0.025 specular 0.85 opacity 0.55 transmission 0.65 thinWalled 1
material crystal 0.72 0.9 1 roughness 0.02 specular 1 opacity 0.8 transmission 0.82 transmissionIOR 1.5

# include reusable script fragment
include commonMaterials

# quad material a(x, y, z) b(x, y, z) c(x, y, z) d(x, y, z) [uvA(u, v) uvB(u, v) uvC(u, v) uvD(u, v)]
quad floor a(-2, 0, 2) b(2, 0, 2) c(2, 0, -2) d(-2, 0, -2) uvA(0, 0) uvB(4, 0) uvC(4, 4) uvD(0, 4)

# box material position(x, y, z) size(x, y, z) [rotationY(radians)]
box floor position(0, 0.3, 0) size(0.6, 0.6, 0.6) rotationY(0.4)

# instance mesh material position(x, y, z) scale(x, y, z) [rotationY(radians)]
instance dragon brushedGold position(0, 0, 0) scale(1, 1, 1) rotationY(0.25)

# fully named mesh/material form is also accepted
instance mesh(dragon) material(brushedGold) position(0, 0, 0) scale(1, 1, 1) rotationY(0.25)

# SDF model volumes can be built inline as dense fields or sparse bricks.
# sdf [name] dense|sparse material name [resolution n] [brickSize n] [narrowBand value]
#     [attributes channel ...] [boundsMin(x, y, z)] [boundsMax(x, y, z)]
#     sphere material name radius value [position(x, y, z)] [smooth value]
#            [attr channel value] [baseColor r g b] [opacity value]
#            [roughness value] [metallic value] [transmission value]
#     box material name size(x, y, z) [cornerRadius value] [position(x, y, z)]
#         [rotationX value] [rotationY value] [rotationZ value]
#         [smooth value] [attr channel value]
#     cylinder material name radius value height value [position(x, y, z)]
#         [rotationX value] [rotationY value] [rotationZ value] [smooth value]
#     subtract box material name size(x, y, z) [cornerRadius value] [position(x, y, z)]
#     sphere material name radius value [worldToLocal(m00 ... m33)]
sdf organics sparse material mossy resolution 40 brickSize 8 narrowBand 0.22 attributes growthAge wetness mossAmount cavity polish boundsMin -1 -1 -1 boundsMax 1 1 1 sphere material mossy radius 0.56 attr growthAge 0.92 attr wetness 0.78 attr mossAmount 1 attr cavity 0.35 sphere material wet radius 0.36 position 0.42 0.04 0.02 smooth 0.22 attr wetness 1 attr mossAmount 0.25 opacity 0.58 transmission 0.42 box material crystal size 0.42 0.42 0.42 position -0.42 -0.02 0.03 rotationY 0.55 smooth 0.14 attr polish 0.95 attr wetness 0.2 transmission 0.82
```

Swift usage:

```swift
let scene = try SceneScript.parse(contentsOf: sceneURL)
let session = try renderer.makeSession(scene: scene)
```

Interactive tools can reuse decoded image textures and meshes across parses:

```swift
let assetCache = SceneAssetCache()
let scene = try SceneScript.parse(contentsOf: sceneURL, assetCache: assetCache)

// Clear when the user asks to reload changed assets from disk.
assetCache.removeAll()
```

CLI usage:

```sh
swift run denrim -- ./Scenes/scene.denrim --output ./ScriptedScene.png --samples 32 --size 512
```

When a script contains `render` defaults, `denrim` uses them for omitted CLI options. Explicit CLI flags still win. `SceneScript.parse(contentsOf:)` resolves a render default output path relative to the script file; `SceneScript.parse(_:)` without a base URL preserves the authored relative path.

`render sdfResolution n` sets the default build resolution for every `sdf` / `volume` command that omits its own `resolution n`. Per-SDF `resolution n` remains useful for intentionally lower- or higher-detail fields. The CLI flag `--sdf-resolution n` overrides both script defaults and per-SDF values at parse time, so it changes the actual baked dense fields or sparse bricks.

The `denrim` CLI passes a renderer-backed `DistanceFieldBaker` into SceneScript parsing. Bakeable primitive SDF scenes use the Metal compute baker during scene load when the requested graph fits the current GPU primitive path; scripts with compact attributes or baked material fields can fall back to the CPU reference baker when needed so those lanes are preserved. `DistanceFieldProgram` direct-grid resources are the no-readback path for live Form-style masks and material fields.

Denoising is off by default. `--denoise apple-svgf` and `--denoise experimental-simple` are explicit opt-in comparison modes, not baseline output modes.

The repository includes a self-contained material-variant script template at `Examples/SceneScripts/MaterialVariants/material-variants.denrim`. It uses a bundled toy PLY mesh so tests can run without external assets. `Examples/SceneScripts/SDF/custom-attribute-sdf.denrim` is the current scripted validation scene for sparse SDF bricks, compact custom volume attributes, smooth primitive blending, and baked material field overrides. `Examples/SceneScripts/SDF/shadertoy-material-testball.denrim` is an SDF material-test scene derived from Markus Moenig's 2018 Shadertoy preview scene; it uses a rounded beveled SDF box environment, pedestal cylinders, sphere/cylinder CSG subtraction, and the original preview camera.

The Stanford Dragon example lives at `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim`. Run `./Examples/Tools/render-quality-examples.sh` to fetch the mesh if needed and render local comparison outputs into `/tmp/denrim-quality-examples`.

Render any `.denrim` file with the unified CLI:

```sh
swift run denrim -- Examples/SceneScripts/MaterialVariants/material-variants.denrim \
    --output /tmp/material-variants.png \
    --samples 32 \
    --quality interactive \
    --sdf-resolution 96
```

`SceneScript.parse(contentsOf:)` resolves relative environment image paths, image texture paths, mesh paths, and include paths beside the script file. `SceneScript.parse(_:baseURL:assetCache:options:includeResolver:)` is still available for applications that want to provide script source, asset cache, parse-time overrides, and include policy themselves. If no base URL is passed, relative assets are resolved against the current process directory. Environment images are linear equirectangular maps; Radiance `.hdr` files are supported for material-preview lighting. Use `maxRadiance` to clamp very bright HDR texels for preview renders until the renderer has environment importance sampling. Image textures default to `color srgb` and `sampler linear`; generated solid/checker textures default to nearest sampling. `normalFrom` derives a tangent-space normal map from an existing texture's luminance, which is useful for reference assets that ship only albedo images. Mesh assets use `Mesh(contentsOf:)`, so the current script path supports OBJ and PLY files. Add `flipV` to a `mesh` command when an imported asset's texture coordinates were authored for bottom-left image origin but the source images are decoded top-down.

Grouped numeric arguments may use commas or whitespace inside parentheses. The older positional forms, such as `quad floor -2 0 2 ...` and `instance dragon clay 0 0 0 1 1 1`, remain supported for compatibility, but examples should prefer named groups because they are easier to read and review.

Includes are resolved by the caller, which keeps reusable script fragments independent of bundle policy:

```swift
let fragments = [
    "commonMaterials": "material floor 0.7 0.7 0.65"
]

let scene = try SceneScript.parse(source) { name in
    guard let fragment = fragments[name] else {
        throw SceneScriptError.includeResolverMissing(name, line: 0)
    }
    return fragment
}
```

The script language is meant to grow carefully with the renderer. It should remain useful for tests, examples, Denrim Render automation, and reproducible Form bug reports without becoming a full DCC format. Interactive products should pass compiled `RenderFieldBundle` values to RendererKit directly rather than generating SceneScript as their realtime interchange layer.

## Procedural Material Direction

SceneScript should grow procedural material authoring alongside the Swift API. The goal is to make reference scenes and Denrim Render scenes scriptable without inventing a full shader language.

Planned commands should define reusable procedural values, then bind those values into material parameters:

```text
proc noise marbleNoise noise3d scale 18 octaves 5 seed 7 space object
proc ramp marbleRamp marbleNoise 0.0 0.18 0.12 0.08 1.0 0.9 0.82 0.68
proc noise scratchMask noise2d scale 90 octaves 3 seed 12 space uv

material marble 1 1 1 roughness 0.38 specular 0.5 baseColorProc marbleRamp
material scratchedMetal 0.74 0.72 0.68 metallic 1 roughnessProc scratchMask
```

The first useful procedural set should include constants, noise, fractal noise, ramps, checker, mix, multiply, add, clamp, remap, UV coordinates, object/world coordinates, triplanar coordinates, and procedural bump/normal generation. These script commands should compile to the same material graph representation used by the public Swift API.
