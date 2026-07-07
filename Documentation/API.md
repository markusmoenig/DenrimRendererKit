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
* `SDFTraversalStats`
* `RenderViewport`
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
* `DistanceVolume`
* `DistanceVolumeAttributeChannel`
* `DistanceVolumeAttributeLayout`
* `DistanceVolumeAttributeValues`
* `DistanceVolumeInstance`
* `DistanceVolumeMaterialFields`
* `DistanceVolumeMaterialSample`
* `RenderFieldBundle`
* `RenderFieldID`
* `RenderFieldStorage`
* `RenderFieldStorageKind`
* `DistanceFieldBaker`
* `DistanceFieldBakeBackend`
* `DistanceFieldBakeGraph`
* `DistanceFieldBakeRequest`
* `DistanceFieldBakeResult`
* `DistanceFieldBakeStorage`
* `RenderGPUSparseFieldResource`
* `RenderGPUSparseFieldBrick`
* `RenderGPUSparseFieldBrickUpdate`
* `SparseDistanceVolume`
* `SparseDistanceVolumeBrick`
* `SparseDistanceVolumeInstance`
* `SDFModel`
* `SDFPrimitive`
* `SDFPrimitiveOperation`
* `SDFPrimitiveShape`
* `DistanceVolumeBuildSettings`
* `SparseDistanceVolumeBuildSettings`
* `DistanceVolumeBuilder`
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
let material = scene.addMaterial(Material(
    baseColor: SIMD3<Float>(0.12, 0.38, 0.12),
    roughness: 0.86,
    specular: 0.22
))

scene.add(
    mesh: mesh,
    material: material,
    transform: .translation(SIMD3<Float>(0, 1, 0))
)
```

Dense signed-distance volumes can be added with the same material and transform pattern:

```swift
let material = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.8, 0.2, 0.1)))
let volume = DistanceVolume(
    width: 32,
    height: 32,
    depth: 32,
    distances: samples,
    boundsMin: SIMD3<Float>(repeating: -1),
    boundsMax: SIMD3<Float>(repeating: 1)
)

scene.add(
    volume: volume,
    material: material,
    transform: .translation(SIMD3<Float>(0, 1, 0))
)
```

`DistanceVolume` stores dense row-major X-fastest signed-distance samples in local object space. The current Metal path renders the zero crossing as a surface, computes normals from the distance gradient, and reuses the regular material, lighting, and AOV path.

`DistanceVolumeMaterialSample` can carry a two-material blend plus optional baked `DistanceVolumeMaterialFields`. These fields override selected material channels after material-ID blending, which lets procedural SDF systems bake color, opacity, emission, roughness, metallic, and transmission fields without generating a unique static material for every voxel.

`RenderFieldBundle` is the preferred Form-to-RendererKit boundary. Products should add plain renderer materials to the scene, compile their procedural model into dense or sparse field storage, and pass the bundle to `RenderScene`. For bakeable primitive graphs, use the renderer's `DistanceFieldBaker` instead of calling the CPU reference builder directly:

```swift
let renderer = try DenrimRenderer()
let moss = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.38, 0.12), roughness: 0.86))
let baker = renderer.makeDistanceFieldBaker()
let result = try baker.bake(DistanceFieldBakeRequest(
    graph: DistanceFieldBakeGraph(model: formCompiledModel),
    resolution: 64,
    storage: .sparseBricks(brickSize: 8, narrowBand: 0.2, sampleScale: 2),
    fallbackMaterial: moss
))
let fieldID = scene.add(fieldBundle: result.bundle, transform: objectTransform)
```

Form should own its editable timeline/operator document format. RendererKit owns the renderable field-bundle API and storage semantics. SceneScript can emit or load comparable scenes for debugging and fixtures, but it is not the realtime interchange layer between Form and RendererKit.

`DistanceFieldBaker` is the shared bake service for SceneScript, Denrim Form, and other procedural hosts. It accepts a `DistanceFieldBakeGraph`, target bounds/resolution, and dense or sparse-brick storage. `DistanceFieldBakeStorage.sparseBricks(..., sampleScale:)` requests refined sparse payloads for quality: the baker increases sample dimensions and brick payload size together while keeping the coarse brick grid stable. The current Metal compute path supports transformed spheres, rounded boxes, cylinders, union/subtract, smooth-union material IDs, sparse-brick extraction, and sample-scaled GPU-resident direct-grid bakes. Direct-grid `DistanceFieldProgram` bakes can keep compact mask/custom attribute samples and generic material-field override samples GPU-resident; generic `SDFModel` graphs with compact attributes or baked material fields may still fall back to the CPU reference baker so those lanes are preserved. Future work should move those generic graph lanes and cache lookup behind the same API.

`DistanceFieldProgram` is the first modular SDF IR for Form-style operator graphs. It is a small renderer-owned VM rather than arbitrary Metal source. Form should compile timeline modules into scalar/vector instructions and `emit` calls, so RendererKit does not need a new public SDF operation for every product-level component. The higher-level named operations are kept as conveniences and test fixtures, not as the main Form integration layer.

An instruction program can define distance expressions directly:

```swift
let p = DistanceFieldVectorRegister(0)
let distance = DistanceFieldScalarRegister(0)
let radius = DistanceFieldScalarRegister(1)
let finalDistance = DistanceFieldScalarRegister(2)

let program = DistanceFieldProgram(instructions: [
    .loadPosition(p),
    .length(distance, p),
    .setFloat(radius, 0.55),
    .subtractFloat(finalDistance, distance, radius),
    .emit(distance: finalDistance, material: materialID)
])

let result = try baker.bake(DistanceFieldBakeRequest(
    graph: DistanceFieldBakeGraph(program: program),
    resolution: 64,
    storage: .sparseBricks(brickSize: 8, narrowBand: 0.2),
    fallbackMaterial: materialID
))
```

The geometry instruction VM currently includes scalar/vector constants, arithmetic, min/max/abs, sin/cos, clamp/mix/smoothstep/step/saturate, fract/floor/mod, vector compose/extract, dot/length/normalize/distance, 3D value noise, 3D FBM, 3D cellular/Worley noise, box/cylinder/tapered-capsule/spline-tube distance intrinsics, field `emit` with union/subtract plus smooth-union material blending, candidate-scoped custom attributes, and coarse/volumetric material field writes. `DistanceFieldProgram` should be used for distance, deformation, and stable low-frequency geometric attributes such as growth age, radius, branch id, or local growth coordinates. Visible surface styling should compile into `DistanceFieldMaterialProgram`, which runs at the final hit point and owns masks, color variation, roughness/wetness changes, dots, cracks, rings, moss, age tint, and material overrides. The material VM intentionally supports the same scalar/vector math set, procedural noise intrinsics, and distance intrinsics as the geometry VM, plus hit inputs, baked attribute reads, hit-time mask registers, and generic material field writes. RendererKit should only grow new VM intrinsics when the math vocabulary itself is missing.

For organic growth, `splineTubeDistance` is the preferred branch/stem primitive for one cubic Bezier tube segment with tapered endpoints. `taperedCapsuleDistance` remains useful for simple straight sections and as the lower-level segment primitive. Form can chain spline tube segments for longer branches while keeping the editable curve data in Form:

```swift
let program = DistanceFieldProgram(instructions: [
    .loadPosition(.init(0)),
    .setVector(.init(1), SIMD3<Float>(-0.4, -0.5, 0)),
    .setVector(.init(2), SIMD3<Float>(0.35, -0.2, 0.18)),
    .setVector(.init(3), SIMD3<Float>(-0.35, 0.2, -0.18)),
    .setVector(.init(4), SIMD3<Float>(0.4, 0.5, 0)),
    .setFloat(.init(0), 0.18),
    .setFloat(.init(1), 0.34),
    .splineTubeDistance(
        .init(2),
        position: .init(0),
        control0: .init(1),
        control1: .init(2),
        control2: .init(3),
        control3: .init(4),
        startRadius: .init(0),
        endRadius: .init(1)
    ),
    .emit(distance: .init(2), material: materialID)
])
```

Surface style is a separate hit-time program:

```swift
let materialProgram = DistanceFieldMaterialProgram(instructions: [
    .loadVectorInput(.init(0), .localPosition),
    .extractY(.init(0), .init(0)),
    .clampFloatConstant(.init(1), .init(0), min: 0, max: 1),
    .writeMask(.a, .init(1)),
    .readMask(.a, .init(2)),
    .writeMaterialField(.roughness, scalar: .init(2)),
    .setVector(.init(1), SIMD3<Float>(0.18, 0.42, 0.11)),
    .writeMaterialFieldVector(.baseColor, vector: .init(1))
])

let field = RenderFieldBundle(
    sparse: sparseVolume,
    fallbackMaterial: materialID,
    materialProgram: materialProgram
)
```

Generated programs can also keep candidate attributes directly on the emit:

```swift
.emit(
    distance: .init(2),
    material: materialID,
    smoothUnionRadius: 0.12,
    attributes: [
        DistanceFieldProgramAttributeBinding(channel: 0, value: .init(3))
    ]
)
```

`program.optimized()` applies conservative constant folding. The baker runs the same optimizer before CPU/reference program baking and GPU instruction packing.

The program path has a CPU/reference baker for dense and sparse validation fields, including sparse `sampleScale` payloads and candidate-scoped compact attributes. It can also bake directly into GPU-resident sparse fields when using `GPUResidentSparseMetadataMode.directGridGPU`, including resident compact attribute sample buffers for program attributes. That is the intended live-edit path for Form-style operator graphs. Existing `SDFModel` primitive graphs remain supported; compacted GPU-resident metadata for `DistanceFieldProgram` is not implemented yet.

For live editors that can use RendererKit's Metal baker, `bakeGPUResident(_:)` avoids reading the baked sparse sample payload back to the CPU. RendererKit still keeps compact CPU brick metadata for bounds/grid setup, but the large `PackedDistanceVolumeSample` brick payload remains in an `MTLBuffer` and is bound directly by the render session:

```swift
let result = try baker.bakeGPUResident(DistanceFieldBakeRequest(
    graph: DistanceFieldBakeGraph(model: formCompiledModel),
    resolution: 96,
    storage: .sparseBricks(brickSize: 8, narrowBand: 0.2),
    fallbackMaterial: moss,
    backend: .metalCompute
))

let fieldID = scene.add(fieldBundle: result.bundle)
```

The first GPU-resident version supports sparse-brick storage for graphs that the Metal baker can evaluate. It currently binds one GPU-resident sparse sample buffer per scene and cannot be mixed with CPU sparse fields in the same render session. That limitation keeps the shader layout stable while establishing the no-readback boundary Form needs.

Live tools can over-allocate the first GPU-resident sample buffer and reuse it across later topology-changing bakes. If the new sparse payload fits in the old resource's `sampleCapacity`, RendererKit writes into the same `MTLBuffer`; otherwise it allocates a larger buffer:

```swift
let first = try baker.bakeGPUResident(
    initialRequest,
    sampleCapacityMultiplier: 2
)

let previous = scene.gpuSparseVolumeInstances[0].resource
let next = try baker.bakeGPUResident(
    editedRequest,
    reusing: previous
)
```

This is the first atlas-style residency layer. It keeps the heavy sample payload stable, while compact brick descriptors and sparse grids are still rebuilt from CPU-visible metadata. During `replaceGPUSparseFieldPreservingSession`, RendererKit also reuses the existing compact SDF metadata buffers when the replacement descriptor/grid payload fits their current capacity.

For live editing where avoiding the CPU classification readback matters more than compact memory use, request direct-grid GPU metadata:

```swift
let live = try baker.bakeGPUResident(
    editedRequest,
    reusing: previous,
    metadataMode: .directGridGPU
)
```

This mode writes renderer-compatible brick descriptors, one grid, grid indices, and brick samples directly from Metal. It uses one potential brick slot per sparse grid cell, so inactive cells cost table/sample capacity but no CPU brick-list construction. The direct-grid kernels evaluate brick samples in parallel with one threadgroup per brick. Direct-grid metadata supports normal scene transforms and is patched with the scene-local volume index at compile time; the current renderer still supports one GPU-resident sparse field per scene.

`DistanceFieldProgram` instruction graphs are supported on this direct-grid path:

```swift
let program = DistanceFieldProgram(instructions: [
    .loadPosition(.init(0)),
    .length(.init(0), .init(0)),
    .setFloat(.init(1), 0.55),
    .subtractFloat(.init(2), .init(0), .init(1)),
    .emit(distance: .init(2), material: moss)
])

let result = try baker.bakeGPUResident(
    DistanceFieldBakeRequest(
        graph: DistanceFieldBakeGraph(program: program),
        resolution: 96,
        storage: .sparseBricks(brickSize: 8, narrowBand: 0.2),
        fallbackMaterial: moss
    ),
    metadataMode: .directGridGPU
)
```

For same-topology program edits, direct-grid resources can be updated by dirty brick index without rebuilding the resource:

```swift
let changedBrickIndices = try previousResource.directGridBrickIndices(
    overlappingLocalBoundsMin: editBounds.min,
    localBoundsMax: editBounds.max,
    padding: editPadding
)
try baker.encodeUpdateGPUResidentProgramBricks(
    previousResource,
    program: updatedProgram,
    brickIndices: changedBrickIndices,
    narrowBand: 0.2,
    fallbackMaterial: moss,
    into: commandBuffer
)
```

For material/attribute-only program edits where the active brick set is known to be unchanged, pass `updatesTopology: false` to skip the macro-grid rebuild:

```swift
let changedBrickIndices = try previousResource.directGridBrickIndices(
    overlappingLocalBoundsMin: editBounds.min,
    localBoundsMax: editBounds.max,
    activeOnly: true
)
try baker.encodeUpdateGPUResidentProgramBricks(
    previousResource,
    program: updatedMaterialProgram,
    brickIndices: changedBrickIndices,
    narrowBand: 0.2,
    fallbackMaterial: moss,
    updatesTopology: false,
    into: commandBuffer
)
```

GPU-resident direct-grid program resources can carry resident compact custom scalar samples and resident generic material-field samples. These fields are intended for geometric attributes and genuinely volumetric/coarse cached data. Surface masks and material decisions should live in `DistanceFieldMaterialProgram` and are associated with the field bundle/instance rather than baked into the sparse payload.

The first replacement API is whole-bundle based and uses the scene-local handle returned by `add(fieldBundle:)`:

```swift
scene.replaceField(fieldID, with: updatedBundle)
```

This is enough for early editor integration where Form rebuilds an affected field and recreates a render session. `RenderFieldID` is intentionally a lightweight scene handle; if the host rebuilds the scene, it should discard old handles.

For live accumulation, prefer `RenderViewport` over managing `RenderSession` directly. `RenderSession` is a compiled snapshot; `RenderViewport` owns the editable scene snapshot plus the current session and restarts accumulation when the scene changes:

```swift
let viewport = try renderer.makeViewport(
    scene: scene,
    settings: RenderSettings(width: 1024, height: 1024, quality: .interactive)
)

try viewport.renderNextSample()

let updatedBundle = RenderFieldBundle(sparse: updatedSparse, fallbackMaterial: moss)
try viewport.replaceField(fieldID, with: updatedBundle)

// sampleCount is back to zero because a new session was built.
try viewport.renderNextSample()
```

`replaceField` is transactional: if the handle is invalid it returns `false`, and if rebuilding the session throws, the previous scene/session remain active. For app-owned Metal frame loops, call `viewport.encodeNextSample(into:)` and then sample `viewport.liveMetalTexture(for:)`.

Camera-only interaction does not need a scene or field rebuild. `RenderViewport.updateCamera(_:)` updates the viewport scene snapshot and the current compiled `RenderSession` in place, preserves geometry/material/light buffers and render targets, resets accumulation, and clears the tile cursor. When no explicit previous camera is supplied, RendererKit uses the camera active before the update for motion-vector output:

```swift
viewport.updateCamera(Camera(
    origin: orbitCameraOrigin,
    target: orbitCameraTarget,
    up: cameraUp,
    verticalFieldOfViewDegrees: 45,
    projection: .perspective
))

try viewport.encodeNextTile(tileWidth: 128, tileHeight: 128, into: commandBuffer)
```

Lower-level integrations that manage `RenderSession` directly can call `session.updateCamera(_:)` with the same semantics.

For UI-constrained editors, `RenderViewport` can accumulate one spiral-ordered tile per call instead of rendering a whole frame. The first tile starts near the center of the image, then tiles expand outward. `sampleCount` advances only after the final tile in the sweep, so every tile in that sweep uses the same accumulation weight:

```swift
let progress = try viewport.encodeNextTile(
    tileWidth: 128,
    tileHeight: 128,
    into: commandBuffer
)

let texture = viewport.liveMetalTexture(for: .beauty)
if progress.completedSample {
    // One full-frame progressive sample is now complete.
}
```

This is intended for Form-style path-traced viewports where the app wants to spend a small bounded amount of GPU work per display refresh, for example one 128x128 tile at 60 Hz. Full-frame `renderNextSample()` / `encodeNextSample(into:)` remain available and reset the tile cursor. `.preview` and `.interactive` are single-pass renderers, so tile calls render the full frame immediately and return `tileCount == 1`; `.final` keeps the spiral tile sweep behavior.

For same-topology GPU-resident edits, Form can update dirty brick payloads without readback and without rebuilding the render session. Encode the bake kernels that write changed brick samples, then encode the RendererKit copy into the field resource, then continue rendering. `RenderViewport` preserves the current session and resets progressive accumulation:

```swift
let commandBuffer = commandQueue.makeCommandBuffer()!
try viewport.encodeUpdateGPUSparseFieldBricks(
    fieldID,
    updates: [
        RenderGPUSparseFieldBrickUpdate(
            brickIndex: changedBrickIndex,
            sourceBuffer: freshlyBakedBrickSamples
        )
    ],
    into: commandBuffer
)
try viewport.encodeNextSample(into: commandBuffer)
commandBuffer.commit()
```

For direct-grid `DistanceFieldProgram` fields, the viewport can map field-local edit bounds to brick slots and ask the baker to update only those slots:

```swift
let commandBuffer = commandQueue.makeCommandBuffer()!
try viewport.encodeUpdateGPUResidentProgramBricks(
    fieldID,
    baker: baker,
    program: updatedProgram,
    overlappingLocalBoundsMin: editBounds.min,
    localBoundsMax: editBounds.max,
    padding: editPadding,
    narrowBand: 0.2,
    fallbackMaterial: moss,
    into: commandBuffer
)
try viewport.encodeNextTile(tileWidth: 128, tileHeight: 128, into: commandBuffer)
commandBuffer.commit()
```

If the edit bounds are already in scene/world space, use the world-bounds overload. The viewport expands the AABB by `padding` in world units, then transforms the eight corners through the field instance transform before selecting direct-grid brick slots:

```swift
try viewport.encodeUpdateGPUResidentProgramBricks(
    fieldID,
    baker: baker,
    program: updatedProgram,
    overlappingWorldBoundsMin: worldEditBounds.min,
    worldBoundsMax: worldEditBounds.max,
    padding: editPadding,
    narrowBand: 0.2,
    fallbackMaterial: moss,
    into: commandBuffer
)
```

For material/attribute-only edits where occupancy is unchanged, combine `activeOnly: true` with `updatesTopology: false`:

```swift
try viewport.encodeUpdateGPUResidentProgramBricks(
    fieldID,
    baker: baker,
    program: updatedMaterialProgram,
    overlappingLocalBoundsMin: editBounds.min,
    localBoundsMax: editBounds.max,
    activeOnly: true,
    narrowBand: 0.2,
    fallbackMaterial: moss,
    updatesTopology: false,
    into: commandBuffer
)
```

Dirty-brick updates keep the sparse topology fixed: existing brick indices, dimensions, transforms, and sample counts must remain valid. If an edit adds or removes occupied bricks, changes the field bounds, or changes resolution/brick size, use `replaceField` with a freshly baked bundle.

For topology-changing edits that still only replace a GPU-resident sparse field, `RenderViewport` can refresh the SDF buffers while preserving the current `RenderSession` object and render targets:

```swift
let updated = try baker.bakeGPUResident(updatedRequest)
try viewport.replaceGPUSparseFieldPreservingSession(fieldID, with: updated.bundle)
```

This path refreshes volume descriptors, sparse brick descriptors, sparse grids, and the GPU sample buffer binding, then resets accumulation. It reuses existing render-side SDF buffers when the new compact payload fits; otherwise it grows only the buffers that need more capacity. Direct-grid GPU metadata resources can provide those descriptor/grid buffers directly. This path is meant for edits where the field's brick occupancy changes but the rest of the scene is stable. Use full `replaceField` / `replaceScene` if the edit also changes meshes, material tables, textures, lights, camera, or other non-field scene state.

`DistanceVolumeAttributeLayout` supports named compact scalar fields for geometric attributes and custom tools. Samples are packed in `SIMD4<Float>` groups. Use this for stable field data such as growth age, radius, branch id, or other low-frequency structure values:

```swift
let attributes = DistanceVolumeAttributeLayout(channels: [
    DistanceVolumeAttributeChannel(name: "growthAge"),
    DistanceVolumeAttributeChannel(name: "growthRadius")
])
```

Multiple SDF primitives can be compiled into one material-aware dense volume before adding it to a scene:

```swift
let red = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.9, 0.1, 0.1)))
let blue = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.1, 0.2, 0.9)))
let model = SDFModel(
    primitives: [
        SDFPrimitive(
            shape: .sphere(radius: 0.55),
            material: red,
            materialFields: DistanceVolumeMaterialFields(baseColor: SIMD3<Float>(0.9, 0.16, 0.08), roughness: 0.82),
            attributes: DistanceVolumeAttributeValues(["growthAge": 0.35, "growthRadius": 0.6]),
            transform: .translation(SIMD3<Float>(-0.25, 0, 0))
        ),
        SDFPrimitive(shape: .sphere(radius: 0.55), material: blue, transform: .translation(SIMD3<Float>(0.25, 0, 0)), smoothUnionRadius: 0.2)
    ],
    attributeLayout: attributes
)
let field = try DistanceVolumeBuilder.build(model: model, settings: DistanceVolumeBuildSettings(resolution: 48))
scene.add(volume: field, material: red)
```

The dense builder writes distance, material payload samples, packed custom attribute samples, and optional generic baked material fields. Smooth unions can produce two-material blend weights so material transitions follow the same blend region as the distance field. Primitive and program material fields are candidate-aware and can be blended when both sides contribute the same channel. The flat Metal path applies baked material fields generically after material-ID blending; this path is for volumetric/coarse data, while visible surface styling should be evaluated by the field's hit-time material program. The scene instance material remains the fallback for manually authored single-material volumes.

For larger or editable SDF compositions, the same model can be compiled into sparse CPU-side bricks:

```swift
let sparse = try DistanceVolumeBuilder.buildSparse(
    model: model,
    settings: SparseDistanceVolumeBuildSettings(
        denseSettings: DistanceVolumeBuildSettings(resolution: 96),
        brickSize: SIMD3<Int>(repeating: 8),
        narrowBand: 0.12
    )
)
let previewField = sparse.denseVolume()
scene.add(volume: previewField, material: red)
```

`SparseDistanceVolume` stores only bricks that overlap the signed-distance narrow band. `SparseDistanceVolumeBuildSettings.sampleScale` can be set above `1` for sparse builds that need better surface quality inside occupied bricks: the builder increases sample density and brick size together, keeping the coarse sparse grid roughly stable while storing more distance samples only where bricks exist. SceneScript exposes the same setting as `sampleScale` on sparse `sdf` lines, and `DistanceFieldBaker` applies the same layout rule to GPU-resident sparse fields. Sparse volumes can also be added directly to a scene:

```swift
scene.add(sparseVolume: sparse, material: red)
```

Scene compilation emits sparse brick descriptors, brick sample payloads, and brick attribute payloads. The flat Metal path traces dense volumes through dense buffers and sparse volumes through brick bounds plus brick-local samples, so sparse SDF scenes no longer need to be densified for rendering. A future optimization can replace the flat brick list with a brick BVH or atlas indirection without changing the scene API.

`RenderSettings.collectsSDFTraversalStats` enables opt-in GPU counters for profiling dense and sparse SDF traversal. It is disabled by default because collection uses shader atomics. `RenderSession.sdfTraversalStats()` returns cumulative counters for the current session, and `resetSDFTraversalStats()` clears them before a profiling pass:

```swift
let session = try renderer.makeSession(
    scene: scene,
    settings: RenderSettings(
        width: 512,
        height: 512,
        collectsSDFTraversalStats: true
    )
)

session.resetSDFTraversalStats()
try session.render(samples: 8)
let stats = session.sdfTraversalStats()
```

The CLI exposes the same path with `--sdf-stats`, printing dense volume tests/march steps, sparse grid cells, derived empty grid cells, sparse macro skips, sparse brick tests, invalid/range-culled bricks, sparse brick marches, sparse brick march steps, sparse brick hits, and primary/bounce/shadow scene-query counts in the render report.

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

`RenderScene.worldBounds()` returns combined world-space bounds for mesh instances, dense SDF volumes, sparse SDF volumes, and GPU-resident sparse fields. Use it with `Camera.framing` to implement Form-style frame-all / frame-selection behavior without rebuilding render fields:

```swift
if let bounds = scene.worldBounds() {
    let camera = Camera.framing(
        bounds,
        viewDirection: currentOrbitDirection,
        up: SIMD3<Float>(0, 1, 0),
        aspectRatio: Float(viewWidth) / Float(viewHeight),
        padding: 1.18,
        centerOffset: SIMD2<Float>(0.08, -0.04),
        projection: .perspective(verticalFieldOfViewDegrees: 42)
    )
    viewport.updateCamera(camera)
}
```

`centerOffset` is measured in fitted-frame units on the camera plane. Positive X moves the framed object center to the right of the image; positive Y moves it up. `targetOffset` is a world-space offset for hosts that want an explicit authored framing pivot.

Depth of field is represented by `CameraLens`. `apertureRadius == 0` is pinhole rendering. For concept/look renders, either set a focus distance directly or derive it from a focus point:

```swift
let focused = viewport.scene.camera.focused(
    on: selectedObjectCenter,
    apertureRadius: 0.035
)
viewport.updateCamera(focused)
```

The path-traced renderers use the thin-lens model for beauty rays. `.preview` keeps camera rays deterministic and currently ignores aperture so editing remains crisp and cheap.

Use `RenderViewport.updateCamera(_:)` for orbit, pan, zoom, FOV, and perspective/orthographic changes in an active viewport. That path only repacks the GPU camera arguments and resets accumulation; it does not rebuild SDF fields, triangle acceleration, material buffers, or render targets.

## Materials and Textures

`Material` is the expanded renderer material representation. It currently exposes scalar base color, emission, roughness, metallic, dielectric specular weight/color/anisotropy, index of refraction, clearcoat weight/tint/attenuation/thickness/roughness/IOR, thin-film interference strength/thickness/IOR, sheen/fuzz weight/color/roughness, random-walk subsurface weight/color/radius/scale/anisotropy, opacity, dielectric transmission weight/color/roughness/IOR/absorption/thin-wall mode, transmissive volume scattering controls, plus optional in-memory texture inputs:

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

Preset identifiers are stable strings such as `matte.clay`, `organic.wood`, `organic.plant`, `metal.brushed-aluminum`, `coating.iridescent-amber`, `glass.thin-pane`, `ceramic.white`, and `emission.warm-panel`. Lookup is case-insensitive and treats underscores like hyphens. `BuiltInMaterialLibrary.previews` exposes the same ordered identifiers with display name, category, description, and repository-relative generated thumbnail path for material-browser UIs.

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

`RenderSettings.transparentBackground` makes primary camera rays that miss the scene write zero alpha to beauty output and PNG export. It defaults to `false`, preserving the opaque sky background. `RenderSettings.showsEnvironmentBackground` controls whether primary camera misses draw the environment when the background is opaque. Set it to `false` for viewports that want a controlled `backgroundColor` while keeping the environment active for lighting, reflections, and glass refraction after a surface hit.

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

`RenderSettings.quality` communicates preview, interactive, or final-render intent to renderer integrations. `.preview` selects a backend-independent flat single-hit renderer that resolves the same mesh/SDF/volume intersections, material IDs, generic material fields, masks/custom attributes, texture base color, and AOVs without path-tracing bounces. `.interactive` selects a backend-independent realtime material-preview renderer: it resolves the same primary hits and material payloads, then approximates the path tracer with deterministic direct area-light shading, transparent shadows, short-range contact ambient occlusion, low-frequency diffuse environment fill, roughness-filtered reflections with separate clearcoat response, simple transmission, and SSS-style material cheats. `.final` remains the progressive path-traced reference integrator. Command-line tools also use quality to choose a default path depth when `--max-bounces` is omitted. `RenderSettings.sampleRadianceClamp` limits the peak RGB value of a single Monte Carlo sample contribution before progressive accumulation. It is a biased but useful firefly control for glossy metals, clearcoat, glass, small bright emitters, and HDR environments. Leave it as `nil` to inherit the quality default (`preview` is stricter, `final` is gentler), set a positive value for reproducible review renders, or set `0` to disable contribution clamping when validating physically unbounded energy.

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

The package currently includes built-in reference scenes:

* `RenderScene.cornellBox()` for global illumination, color bleeding, area light orientation, and camera sanity checks.
* `RenderScene.materialReference()` for the current diffuse, GGX-style rough metallic, and emissive material baseline.
* `RenderScene.materialVariantReference(mesh:)` for rendering one caller-supplied mesh through multiple material variants, suitable for local benchmark meshes such as a Stanford Dragon PLY or OBJ.
* `RenderScene.transparentMaterialReference()` for opacity, cutout, and transparent / refractive material planning.
* `RenderScene.distanceVolumeReference()` for one compiled dense SDF volume containing multiple primitives, transformed primitive bounds, transparent / transmissive volume surfaces, and volume AOV validation.

The reference scenes are intentionally small. They should grow as the renderer gains semi-transparent blending, nested dielectric priority, layered materials, sparse distance-volume bricks, and richer texture reference coverage.

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
