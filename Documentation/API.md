# DenrimRendererKit API Documentation

DenrimRendererKit keeps API documentation inside the Swift Package from the beginning.

This folder is the source of truth for renderer documentation. The Denrim website in `../Denrim-Web` can consume, copy, or publish this material later, but API intent and integration guidance should be authored here first.

Documentation goals:

* Explain the stable public API.
* Keep examples close to the code.
* Document renderer settings before apps depend on them.
* Describe integration patterns for Denrim Forge, Voxel, Terrain, and Render.
* Collect architecture notes that should eventually appear on the website.

Public Swift APIs should also use DocC-compatible comments so generated API references can be published later.

## Current Public API

The first vertical slice exposes a small API around rendering a scene progressively:

```swift
import DenrimRendererKit

let renderer = try DenrimRenderer()
let scene = RenderScene.cornellBox()
let session = try renderer.makeSession(
    scene: scene,
    settings: RenderSettings(width: 512, height: 512, maxBounces: 4)
)

try session.render(samples: 64, to: outputURL)
```

Initial public types:

* `DenrimRenderer`
* `RenderSession`
* `RenderSettings`
* `RenderAccelerationMode`
* `RenderAccelerationInfo`
* `DenoiseSettings`
* `RenderDenoiser`
* `RenderQuality`
* `RenderTarget`
* `RenderOutput`
* `RenderOutputPixel`
* `RenderScene`
* `Environment`
* `QuadLight`
* `Camera`
* `Transform`
* `SceneScript`
* `SceneAssetCache`
* `Ray`
* `SurfaceHit`
* `CameraProjection`
* `Mesh`
* `MeshInstance`
* `MeshLoadingError`
* `Material`
* `MaterialID`
* `BuiltInMaterialLibrary`
* `BuiltInMaterialPreset`
* `BuiltInMaterialCategory`
* `Texture2D`
* `TextureColorEncoding`
* `TextureSamplingMode`
* `TextureLoadingError`

This API is intentionally small. The next steps are to add DocC comments to each public type, stabilize the scene-building API, and introduce internal renderer abstractions without exposing GPU implementation details.

`Texture2D.derivedNormalMap(strength:)` can create a lightweight tangent-space normal map from an existing texture's luminance. It is intended for examples and albedo-only validation assets, not as a replacement for authored material maps.

## Scene Construction

Meshes can be added with a material and an optional transform:

```swift
var scene = RenderScene()
let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.8, 0.8)))

scene.add(
    mesh: mesh,
    material: material,
    transform: .translation(SIMD3<Float>(0, 1, 0))
)
```

Wavefront OBJ and PLY meshes can be loaded from disk:

```swift
let mesh = try Mesh(contentsOf: URL(fileURLWithPath: "Assets/dragon.ply"))
let scene = RenderScene.materialVariantReference(mesh: mesh)
```

OBJ and PLY import are intentionally the first small import paths. The OBJ loader uses byte-scanned parsing for large text assets. Imported vertex normals and UVs are preserved when meshes are converted to GPU triangles. The PLY loader supports ASCII and binary little-endian meshes with vertex positions, optional normals / UVs, and polygon face lists. glTF/GLB import is future work. Common benchmark assets such as the Stanford Dragon should be supplied by the caller or test environment rather than vendored in the package unless their license allows redistribution in Denrim products.

Scene compilation now builds an internal instance acceleration model with local mesh records, transformed instance records, and a top-level instance BVH. The current compute backend still materializes transformed triangles for its flat GPU BVH, while future acceleration backends can preserve transforms for TLAS / BLAS style instancing without changing this public API.

## Cameras

`Camera` supports perspective and orthographic projection. Perspective is the default and uses `verticalFieldOfViewDegrees`. Orthographic projection uses a vertical world-space scale and keeps ray direction constant across the image, which is useful for Denrim Forge's isometric Render mode:

```swift
scene.camera = Camera(
    origin: SIMD3<Float>(0, 4, 6),
    target: SIMD3<Float>(0, 0, 0),
    up: SIMD3<Float>(0, 1, 0),
    verticalFieldOfViewDegrees: 55,
    projection: .orthographic(verticalScale: 5.0)
)
```

For viewport integrations, build `origin`, `target`, and `up` from the application's actual camera basis rather than reconstructing yaw and pitch through a different convention. `CameraProjection.orthographic(verticalScale:)` maps to the same vertical scale convention used by Forge's old render viewport: horizontal scale is derived from render width divided by render height.

## Materials and Textures

`Material` currently exposes scalar base color, emission, roughness, metallic, dielectric specular weight/color/anisotropy, index of refraction, clearcoat weight/tint/attenuation/thickness/roughness/IOR, thin-film interference strength/thickness/IOR, sheen/fuzz weight/color/roughness, random-walk subsurface weight/color/radius/scale/anisotropy, opacity, dielectric transmission weight/color/roughness/IOR/absorption/thin-wall mode, transmissive volume scattering controls, plus optional in-memory texture inputs:

```swift
let checker = Texture2D.checker(
    SIMD4<Float>(1, 0, 0, 1),
    SIMD4<Float>(0, 0, 1, 1)
)
let baseColor = try Texture2D(contentsOf: baseColorURL, colorEncoding: .sRGB)
let normalMap = try Texture2D(contentsOf: normalMapURL, colorEncoding: .linear)
let filtered = Texture2D(width: 2, height: 2, pixels: pixels, samplingMode: .linear)
let material = Material(
    baseColor: SIMD3<Float>(1, 1, 1),
    specular: 1,
    specularColor: SIMD3<Float>(1, 1, 1),
    indexOfRefraction: 1.5,
    specularAnisotropy: 0.65,
    transmission: 1,
    transmissionColor: SIMD3<Float>(0.72, 0.86, 1.0),
    transmissionRoughness: 0.04,
    transmissionIndexOfRefraction: 1.45,
    transmissionAbsorptionColor: SIMD3<Float>(0.64, 0.82, 1.0),
    transmissionAbsorptionDistance: 0.8,
    volumeScattering: 0.55,
    volumeScatteringColor: SIMD3<Float>(0.9, 0.95, 1.0),
    volumeScatteringDistance: 0.65,
    volumeAnisotropy: 0.25,
    thinWalled: false,
    clearcoat: 0.25,
    clearcoatColor: SIMD3<Float>(0.82, 1.0, 0.9),
    clearcoatAttenuationColor: SIMD3<Float>(0.7, 0.9, 0.78),
    clearcoatThickness: 0.35,
    clearcoatRoughness: 0.08,
    clearcoatIndexOfRefraction: 1.5,
    thinFilm: 0.75,
    thinFilmThicknessNanometers: 430,
    thinFilmIndexOfRefraction: 1.38,
    sheen: 0.35,
    sheenColor: SIMD3<Float>(0.9, 0.8, 1.0),
    sheenRoughness: 0.75,
    subsurface: 0.7,
    subsurfaceColor: SIMD3<Float>(0.95, 0.45, 0.28),
    subsurfaceRadius: SIMD3<Float>(1.0, 0.42, 0.24),
    subsurfaceScale: 0.35,
    subsurfaceAnisotropy: 0.18,
    baseColorTexture: baseColor,
    normalMap: normalMap
)
```

`specular`, `specularColor`, `indexOfRefraction`, and `specularAnisotropy` drive dielectric Fresnel reflectance and anisotropic GGX shape for the current base specular lobe. `subsurface`, `subsurfaceColor`, `subsurfaceRadius`, `subsurfaceScale`, and `subsurfaceAnisotropy` enable closed-surface random-walk subsurface scattering with RGB mean free paths and a Henyey-Greenstein phase function. `transmission`, `transmissionColor`, `transmissionRoughness`, `transmissionIndexOfRefraction`, `transmissionAbsorptionColor`, `transmissionAbsorptionDistance`, and `thinWalled` enable rough dielectric reflection/refraction with explicit tint, independent roughness/IOR, Beer-style absorption for solid visible paths and direct-light shadows, a straight-through thin-sheet mode, and transparent shadowing; omitted transmission controls inherit from base color, roughness, and surface IOR, while absorption is disabled when its distance is zero. `volumeScattering`, `volumeScatteringColor`, `volumeScatteringDistance`, and `volumeAnisotropy` add participating-medium random-walk scattering inside closed transmissive geometry for cloudy liquids and milky refractive materials. `clearcoat`, `clearcoatColor`, `clearcoatAttenuationColor`, `clearcoatThickness`, `clearcoatRoughness`, and `clearcoatIndexOfRefraction` add a secondary tinted isotropic GGX coating lobe above the base material, with optional Beer-style base-layer attenuation through the coating depth. Omitted clearcoat attenuation color inherits the clearcoat tint. `thinFilm`, `thinFilmThicknessNanometers`, and `thinFilmIndexOfRefraction` add angle-dependent interference tint to reflective specular and clearcoat Fresnel terms; strength zero disables it. `sheen`, `sheenColor`, and `sheenRoughness` add an active grazing fuzz / fabric lobe for cloth, velvet-like stylized surfaces, and soft edge highlights. The default IOR of 1.5, white specular and clearcoat colors, zero subsurface weight, zero volume scattering, zero clearcoat thickness, zero thin-film strength, and zero anisotropy preserve the earlier 0.04 isotropic dielectric F0 baseline.

Textures are stored as linear RGBA `Float` pixels in row-major order. Image assets can be decoded through ImageIO with explicit `.sRGB` or `.linear` RGB handling; use `.sRGB` for ordinary color textures and `.linear` for data textures such as normal maps. Radiance `.hdr` files decode through the same `Texture2D` API as linear RGBE data. The first GPU implementation samples textures by mesh UVs inside both the flat BVH and hardware TLAS kernels, with nearest and bilinear sampling modes. Mipmapping and native Metal texture objects are future API work.

Scenes expose `RenderScene.environment`, an `Environment` with optional equirectangular texture, intensity, Y rotation, and preview radiance clamp. Rays that miss geometry sample this environment, and HDRI textures also build an importance distribution for direct-light sampling and MIS, so material-preview scenes can use HDRIs as lighting instead of only as a background/reflection source:

```swift
scene.environment = Environment(
    texture: try Texture2D(contentsOf: hdriURL, colorEncoding: .linear),
    intensity: 0.9,
    rotationY: 2.9,
    maxRadiance: 6
)
```

The current material API is intentionally small. `Documentation/Materials.md` tracks the MoonRay-inspired direction for a future Denrim Standard Surface that grows from the current specular anisotropy, random-walk subsurface scattering, transmissive volume scattering, transmission, clearcoat, and sheen/fuzz controls toward layering and diagnostic controls.

Built-in material presets are available for product UIs, examples, and script authoring through `BuiltInMaterialLibrary`:

```swift
let metalPresets = BuiltInMaterialLibrary.presets(in: .metal)
let glass = BuiltInMaterialLibrary.material(named: "glass.thin-pane")
let presetIDs = BuiltInMaterialLibrary.identifiers
let preview = BuiltInMaterialLibrary.preview(named: "metal.brushed-aluminum")
let thumbnailPath = preview?.thumbnailPath
```

Preset identifiers are stable strings such as `matte.clay`, `metal.brushed-aluminum`, `coating.iridescent-amber`, `glass.thin-pane`, `ceramic.white`, and `emission.warm-panel`. Lookup is case-insensitive and treats underscores like hyphens. `BuiltInMaterialLibrary.previews` exposes the same ordered identifiers with display name, category, description, and repository-relative generated thumbnail path for material-browser UIs.

Denrim product integrations should prefer these presets as material-family baselines rather than recreating simple one-off materials in each app. A product can tint the preset by replacing `baseColor` and can override simple user-facing controls such as roughness, while leaving renderer-owned lobe weights for metallic, transmission, subsurface, clearcoat, and emission behavior in the preset. Denrim Forge's Render-mode bridge follows this pattern: Matte uses `matte.clay`, Plastic uses `plastic.gloss-white`, Metal uses `metal.brushed-aluminum`, Glass uses `glass.clear`, Wax uses `subsurface.wax-cream`, and Emission uses `emission.warm-panel`, with Forge color and roughness layered on top.

Future procedural material APIs should mirror SceneScript procedural commands. Denrim apps should be able to build typed procedural values in Swift, bind them to Standard Surface parameters, and get the same renderer behavior as script-authored scenes:

```swift
let noise = ProceduralValue.noise3D(scale: 18, octaves: 5, seed: 7, space: .object)
let marble = ProceduralColor.ramp(noise, stops: [
    .init(0.0, SIMD3<Float>(0.18, 0.12, 0.08)),
    .init(1.0, SIMD3<Float>(0.9, 0.82, 0.68))
])

let material = Material.standardSurface(
    baseColor: .procedural(marble),
    roughness: .constant(0.38),
    specular: .constant(0.5)
)
```

This is planned API shape, not current public API. The important contract is that procedural materials are deterministic, serializable, GPU-compiled, and shared between Swift-authored scenes and SceneScript-authored scenes.

## Render Outputs

Render sessions expose these outputs:

* `RenderOutput.beauty`
* `RenderOutput.depth`
* `RenderOutput.normal`
* `RenderOutput.albedo`
* `RenderOutput.materialID`
* `RenderOutput.objectID`
* `RenderOutput.motionVector`

Outputs can be read back as floating-point RGBA pixels:

```swift
let pixels = try session.pixels(for: .albedo)
```

Applications that already render with Metal can display outputs directly without CPU readback:

```swift
try session.renderNextSample()
let liveTexture = try session.metalTexture(for: .beauty)
```

`metalTexture(for:)` returns the current Metal texture for the requested `RenderOutput`; for `.beauty`, it resolves denoising first when denoising is enabled, otherwise it returns the raw accumulated beauty texture. The returned texture is owned by the render session and should be treated as read-only by host applications.

For app viewports that already own a frame command buffer, encode the sample into that command buffer before drawing the texture:

```swift
let commandBuffer = commandQueue.makeCommandBuffer()!
try session.encodeNextSample(into: commandBuffer)
let liveTexture = session.liveMetalTexture(for: .beauty)

// Encode the app's full-screen draw or compositing pass that samples liveTexture.
commandBuffer.present(drawable)
commandBuffer.commit()
```

`encodeNextSample(into:)` is nonblocking. It increments the session sample count after encoding the compute pass and leaves command-buffer commit, presentation, and error handling to the host application. `liveMetalTexture(for:)` never encodes additional work, so it is safe to call before the app commits the command buffer that contains the sample pass. For `.beauty`, it returns the raw accumulated beauty texture. Use `renderNextSample()` and `metalTexture(for:)` for simple synchronous tools, tests, and CLIs; use `encodeNextSample(into:)` with `liveMetalTexture(for:)` for live viewport loops where the renderer and presentation work should remain ordered on the GPU.

Outputs can also be exported as PNG files:

```swift
try session.writePNG(output: .normal, to: normalURL)
```

Use `pixels(for:)` for tests, analysis, custom CPU encoders, and exact output inspection. Use `metalTexture(for:)` for synchronous GPU access that may resolve denoised beauty output, and `liveMetalTexture(for:)` for app render loops that need to sample progressive textures in an already-open frame.

Motion vectors use `RenderSettings.previousCamera` and store previous-screen minus current-screen movement in pixels in the red and green channels. If no previous camera is provided, the current scene camera is used and motion resolves to zero.

`RenderSettings.transparentBackground` makes primary camera rays that miss the scene write zero alpha to beauty output and PNG export. It defaults to `false`, preserving the opaque sky background.

`RenderSettings.denoise` defaults to `.none`, and raw converged rendering is the default quality path. Denoisers are explicit opt-in experiments only because they can introduce visible reconstruction artifacts. Set it to `.appleSVGF` to run Apple's Metal Performance Shaders SVGF denoiser, or `.simpleSpatial` to run DenrimRendererKit's internal GPU bilateral filter for preview/debug comparisons. The Apple path packs Denrim's depth and normal AOVs into the layout expected by `MPSSVGFDenoiser`, keeps temporal depth-normal history, filters beauty RGB, and preserves the original beauty alpha:

```swift
let session = try renderer.makeSession(
    scene: scene,
    settings: RenderSettings(
        width: 512,
        height: 512,
        maxBounces: 4
    )
)
```

`RenderSettings.quality` communicates preview, interactive, or final-render intent to renderer integrations. Today it provides the default for `sampleRadianceClamp`; command-line tools also use it to choose a default path depth when `--max-bounces` is omitted. `RenderSettings.sampleRadianceClamp` limits the peak RGB value of a single Monte Carlo sample contribution before progressive accumulation. It is a biased but useful firefly control for glossy metals, clearcoat, glass, small bright emitters, and HDR environments. Leave it as `nil` to inherit the quality default (`preview` is stricter, `final` is gentler), set a positive value for reproducible review renders, or set `0` to disable contribution clamping when validating physically unbounded energy.

```swift
let cleanPreview = RenderSettings(
    width: 512,
    height: 512,
    quality: .interactive,
    sampleRadianceClamp: 18
)

let unclampedReference = RenderSettings(
    width: 512,
    height: 512,
    quality: .final,
    sampleRadianceClamp: 0
)
```

`DenrimRenderer.makeSession(scene:settings:accelerationMode:)` can request `.automatic`, `.flatBVH`, or `.metalRayTracing` for diagnostics, benchmarks, and backend parity checks. Product integrations should usually use the default `makeSession(scene:settings:)` overload. After creation, `RenderSession.accelerationInfo` reports the requested backend, active backend, Metal ray tracing support, TLAS availability, and flat-BVH buffer state.

For an explicit denoiser comparison pass, set `denoise: .appleSVGF` or `denoise: .simpleSpatial`.

Fully transparent material surfaces act as camera-ray cutouts, allowing primary rays to continue to the next visible surface. Transmissive material surfaces sample dielectric reflection/refraction with roughness, measured exit absorption for solid visible paths and direct-light shadows, thin-walled straight-through transmission for sheet materials, and shadow transparency. Semi-transparent blending, nested dielectric priority, caustics behavior, and layered material behavior are future material transport work.

RendererKit does not create scene lights by default. Host applications are responsible for authoring lighting, either by adding emissive materials to ordinary meshes or by using the quad-light convenience API:

```swift
scene.addQuadLight(QuadLight(
    SIMD3<Float>(-1, 3, -1),
    SIMD3<Float>(1, 3, -1),
    SIMD3<Float>(1, 3, 1),
    SIMD3<Float>(-1, 3, 1),
    color: SIMD3<Float>(1, 0.92, 0.78),
    intensity: 20
))
```

`QuadLight` is still represented as an emissive quad internally, so scene compilation includes its two triangles in direct-light sampling. This API is a host-authored lighting primitive, not a default render setup.

PNG export is visualization-oriented. Beauty output uses an ACES-fitted filmic tonemap with alpha preservation, albedo output is gamma encoded with material opacity alpha preservation, normal output is gamma encoded for display, depth output is normalized across visible primary-hit depth values, material/object ID outputs use deterministic palette colors, and motion vectors are visualized around neutral gray. When denoising is enabled, `RenderOutput.beauty` readback and PNG export return the denoised beauty texture after at least one rendered sample; the guiding AOV outputs remain raw. Use `pixels(for:)` when exact floating-point AOV values are needed.

## Built-In Reference Scenes

The package currently includes three built-in scenes:

* `RenderScene.cornellBox()` for global illumination, color bleeding, area light orientation, and camera sanity checks.
* `RenderScene.materialReference()` for the current diffuse, GGX-style rough metallic, and emissive material baseline.
* `RenderScene.materialVariantReference(mesh:)` for rendering one caller-supplied mesh through multiple material variants, suitable for local benchmark meshes such as a Stanford Dragon PLY or OBJ.
* `RenderScene.transparentMaterialReference()` for opacity, cutout, and transparent / refractive material planning.

The material reference scenes are intentionally small. They should grow as the renderer gains semi-transparent blending, nested dielectric priority, layered materials, and richer texture reference coverage.

## Scene Scripting

Small test scenes can be authored with `SceneScript`:

```swift
let scene = try SceneScript.parse(source)
let session = try renderer.makeSession(scene: scene)
```

The first script version supports comments, includes, camera, environment images, solid/checker/image texture definitions, OBJ/PLY mesh definitions, material texture bindings, quad, box, and imported mesh instance commands. Geometry commands support readable named groups such as `origin(0, 1.4, 4)`, `a(-2, 0, 2)`, quad texture coordinates such as `uvA(0, 0)`, `position(0, 0, 0)`, `scale(1, 1, 1)`, and `rotationY(0.25)` while keeping older positional forms for compatibility. Environment image, image texture, and mesh paths can be resolved relative to a caller-provided `baseURL`, with explicit sRGB/linear color decoding and nearest/linear sampler selection for images. It is intended for reference tests, examples, and future Denrim Render automation.
Reusable script fragments can be composed with `include` commands by using `SceneScript.parse(contentsOf:)` for file-based scripts or by passing an include resolver closure to `SceneScript.parse`.

Interactive products can keep decoded meshes and image textures warm across repeated parses with `SceneAssetCache`:

```swift
let assetCache = SceneAssetCache()
let scene = try SceneScript.parse(contentsOf: sceneURL, assetCache: assetCache)
assetCache.removeAll()
```

The cache keeps assets stable until cleared, which is useful for render previews and benchmarks where only camera, material, or sampling settings are changing.

The unified `denrim` CLI can render script files directly and prints benchmark timings after each render:

```sh
swift run denrim -- ./Scenes/scene.denrim --output ./ScriptedScene.png --samples 32 --size 512
```

If `--output` is omitted, `denrim` writes `./out.png` in the current directory.

Raw beauty rendering is the CLI default. Denoising must be requested explicitly:

```bash
swift run denrim -- ./Scenes/scene.denrim --output ./ScriptedScene.png --samples 8 --size 512 --denoise apple-svgf
```

Material previews can be rendered without editing `preview-material.denrim`:

```sh
swift run denrim -- material matte.clay --samples 64 --quality interactive
swift run denrim -- material "0.8 0.05 0.02 roughness 0.18 clearcoat 0.65" --size 512
```

The CLI also accepts `--output-type beauty|depth|normal|albedo|material-id|object-id|motion-vector`, `--quality preview|interactive|final`, `--max-bounces 8`, `--backend automatic|flat-bvh|metal-ray-tracing`, `--sample-radiance-clamp 18` for glossy firefly control, `--sample-radiance-clamp 0` for unclamped reference renders, `--report-output report.json`, `--json`, `--denoise experimental-simple` for the internal debug filter, plus `--denoise-radius`, `--denoise-iterations`, `--denoise-normal-sigma`, `--denoise-depth-sigma`, `--denoise-albedo-sigma`, and `--denoise-color-sigma` for quick filter tuning. Run `swift run denrim help render` or `swift run denrim help material` for the full option reference.
