# Scene Script

DenrimRendererKit includes a small line-based scene scripting language for reference scenes and lightweight renderer automation.

The first version is intentionally small. It supports:

* Comments with `#`.
* `include` with an application-provided resolver.
* `camera`.
* `material`.
* `quad`.
* `box`.

Example:

```text
# camera ox oy oz tx ty tz fov
camera 0 1.4 4.0 0 0.6 0 42

# material name r g b
material floor 0.7 0.7 0.65

# material name r g b emitR emitG emitB strength
material light 1 1 1 1 0.9 0.7 8

# material name r g b [roughness value] [metallic value] [opacity value] [emission r g b strength]
material brushedGold 0.95 0.78 0.35 roughness 0.18 metallic 1

# include reusable script fragment
include commonMaterials

# quad material ax ay az bx by bz cx cy cz dx dy dz
quad floor -2 0 2 2 0 2 2 0 -2 -2 0 -2

# box material tx ty tz sx sy sz [rotationY]
box floor 0 0.3 0 0.6 0.6 0.6 0.4
```

Swift usage:

```swift
let scene = try SceneScript.parse(source)
let session = try renderer.makeSession(scene: scene)
```

Includes are resolved by the caller, which keeps the core parser independent of filesystem or bundle policy:

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
