# Scene Script

DenrimRendererKit includes a small line-based scene scripting language for reference scenes and lightweight renderer automation.

The first version is intentionally small. It supports:

* Comments with `#`.
* `include` with an application-provided resolver.
* `camera`.
* `texture`.
* `mesh`.
* `material`.
* `quad`.
* `box`.
* `instance`.

Example:

```text
# camera origin(x, y, z) target(x, y, z) fov(degrees)
camera origin(0, 1.4, 4.0) target(0, 0.6, 0) fov(42)

# material name r g b
material floor 0.7 0.7 0.65

# texture name solid r g b a [nearest|linear]
texture tangentRight solid 1 0.5 0.5 1 nearest

# texture name checker ar ag ab aa br bg bb ba [nearest|linear]
texture checker checker 1 0 0 1 0 0 1 1 linear

# texture name image path [color srgb|linear] [sampler nearest|linear]
texture loadedAlbedo image Textures/albedo.png color srgb sampler linear

# mesh name path
mesh dragon Meshes/dragon.ply

# material name r g b emitR emitG emitB strength
material light 1 1 1 1 0.9 0.7 8

# material name r g b [roughness value] [metallic value]
#                    [specular value] [specularColor r g b] [ior value] [opacity value]
#                    [clearcoat value] [clearcoatRoughness value] [clearcoatIOR value]
#                    [emission r g b strength] [baseColorTexture name] [normalMap name]
material brushedGold 0.95 0.78 0.35 roughness 0.18 metallic 1 specular 1 specularColor 1 0.86 0.7 ior 1.5 clearcoat 0.25 clearcoatRoughness 0.08 clearcoatIOR 1.5
material textured 1 1 1 baseColorTexture checker normalMap tangentRight

# include reusable script fragment
include commonMaterials

# quad material a(x, y, z) b(x, y, z) c(x, y, z) d(x, y, z)
quad floor a(-2, 0, 2) b(2, 0, 2) c(2, 0, -2) d(-2, 0, -2)

# box material position(x, y, z) size(x, y, z) [rotationY(radians)]
box floor position(0, 0.3, 0) size(0.6, 0.6, 0.6) rotationY(0.4)

# instance mesh material position(x, y, z) scale(x, y, z) [rotationY(radians)]
instance dragon brushedGold position(0, 0, 0) scale(1, 1, 1) rotationY(0.25)

# fully named mesh/material form is also accepted
instance mesh(dragon) material(brushedGold) position(0, 0, 0) scale(1, 1, 1) rotationY(0.25)
```

Swift usage:

```swift
let scene = try SceneScript.parse(contentsOf: sceneURL)
let session = try renderer.makeSession(scene: scene)
```

Preview CLI usage:

```sh
swift run denrim-render-preview ./ScriptedScene.png 32 512 script beauty ./Scenes/scene.denrim
```

The repository includes a self-contained material-variant script template at `Examples/SceneScripts/MaterialVariants/material-variants.denrim` and a rendered output at `Examples/Renders/material-variants.png`. It uses a bundled toy PLY mesh so tests can run without external assets.

The Stanford Dragon example lives at `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim`. Run `./Examples/Tools/render-quality-examples.sh` to fetch the mesh if needed and render persistent reference outputs into `Examples/Renders`.

`SceneScript.parse(contentsOf:)` resolves relative image texture paths, mesh paths, and include paths beside the script file. `SceneScript.parse(_:baseURL:includeResolver:)` is still available for applications that want to provide script source and include policy themselves. If no base URL is passed, relative assets are resolved against the current process directory. Image textures default to `color srgb` and `sampler linear`; generated solid/checker textures default to nearest sampling. Mesh assets use `Mesh(contentsOf:)`, so the current script path supports OBJ and PLY files.

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

The script language is meant to grow carefully with the renderer. It should remain useful for tests, examples, and Denrim Render automation without becoming a full DCC format.

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
