# Architecture

DenrimRendererKit keeps the public app-facing API separate from the internal rendering backend.

The first implementation is intentionally small:

* Public Swift scene types describe cameras, materials, meshes, dense distance volumes, and render settings.
* `RenderSession` owns a snapshot of the compiled scene.
* Scene compilation now builds a BLAS/TLAS-style instance acceleration model before materializing triangles for the current GPU path.
* The acceleration backend prepares triangle, dense distance-volume, material, texture, environment texture / importance distribution, emissive light-index, flat BVH node, and primitive-index GPU buffers.
* `RenderSession` currently uses an experimental Metal ray tracing acceleration backend wrapper that builds guarded BLAS/TLAS resources while preserving the flat BVH fallback.
* A small internal Metal ray tracing traversal probe can trace one ray against the TLAS for CPU-reference comparison.
* Metal compute kernels trace rays, sample emissive triangles for direct lighting, accumulate samples, write an image, and record primary-surface AOVs.
* The current render session uses the hardware TLAS traversal kernel when available for mesh-only scenes and falls back to the flat BVH / mixed volume kernel otherwise.
* Internal render acceleration mode selection lets tests force either backend for parity checks.

The important architectural boundary is the internal acceleration backend.

Today it exposes a flat GPU BVH render path and an experimental Metal ray tracing traversal path. Later it can become:

* CPU-built BVH with GPU traversal.
* Hardened hardware Metal ray tracing traversal.
* Metal 4 ray tracing backend.
* Mixed geometry backend for meshes, heightmaps, SDFs, and voxels.

The public Denrim API should not change when those internal backends change.

## Current Scripting

`SceneScript` provides a small line-based scene language.

The first version supports:

* Comments
* Camera setup
* Equirectangular environment images
* Solid, checker, and image texture definitions
* OBJ and PLY mesh definitions
* Materials
* Base color texture and normal-map bindings
* Quads
* Boxes
* Imported mesh instances

Environment image, image texture, and mesh paths are resolved through caller-controlled base URLs so tests and apps can choose their own bundle or filesystem policy. This is meant to make reference scenes easier to author and eventually make Denrim Render scriptable. It should remain a focused scene-description layer, not a replacement for import formats such as OBJ, glTF, or USDZ.

The first asset import paths are Wavefront OBJ and PLY via `Mesh(contentsOf:)`. They are deliberately small and feed the same `Mesh` API used by procedural primitives, reference scenes, and scene scripts. The OBJ path uses a byte scanner to keep large text-mesh imports usable for fixtures such as DiningRoom. The PLY path supports ASCII and binary little-endian mesh files with vertex positions, optional normals / UVs, and polygon face lists. glTF/GLB import remains future work.

## Current Instances

Mesh instances have a public `Transform`.

The current implementation builds an internal instance acceleration model:

* `MeshAccelerationRecord` stores local mesh triangles, local bounds, and a local BVH.
* `SceneInstanceRecord` stores the material, object ID, transform, mesh reference, and transformed world bounds.
* `InstanceAcceleration` stores a top-level BVH over transformed instance bounds.

The current Metal compute backend still materializes transformed triangles from that structure because the shader traverses one flat triangle BVH. The important step is that scene compilation now has a TLAS-like boundary that future backends can preserve instead of baking all instance transforms immediately.

Later acceleration backends can use this boundary more directly:

* CPU/GPU BVH traversal can move from one flat triangle BVH toward local mesh BVHs plus transformed top-level bounds.
* Metal ray tracing can map records to TLAS / BLAS style instance acceleration.
* Mixed geometry backends can keep per-object transforms for SDFs, heightmaps, and voxel objects.

## Current Distance Volumes

`RenderScene` supports dense signed-distance volumes through `DistanceVolume` and `DistanceVolumeInstance`.

The implementation stores `GPUVolumeSample` records with distance plus a material field payload, alongside `GPUVolumeDescriptor` records containing world bounds, local bounds, transforms, sample offsets, object IDs, and an optional hit-time material program index. The material payload starts with two blendable material IDs and can also carry baked per-sample channel overrides for base color, opacity, emission, roughness, metallic, specular, transmission, and emission strength. Those baked material fields remain available for volumetric or coarse cached data, but visible surface styling should run in `DistanceFieldMaterialProgram` after the final hit point is known. Volumes can also carry separate packed custom scalar buffers described by `GPUVolumeAttributeDescriptor`; these are intended for stable geometric attributes such as growth age, radius, branch id, or local growth coordinates. The flat Metal path traces triangles through the existing BVH, then raymarches bounded volumes only up to the nearest triangle candidate. Volume hits return the same shader `Hit` structure as triangles, so material evaluation, direct lighting, environment lighting, progressive accumulation, and primary AOV writes are shared.

`SDFModel`, `SDFPrimitive`, and `DistanceFieldBaker` provide the first public authoring/compiler layer: many primitives can be baked into one material-aware field bundle, including smooth-union material blends, constant primitive material fields, and compact primitive attributes. This is the preferred path for SDF modeling over one dense volume per primitive, and it is the renderer-side shape needed for procedural products where an editable operator graph bakes a distance field plus material/attribute fields for fast rendering. `DistanceVolumeBuilder` remains the CPU reference implementation underneath that API.

`DistanceFieldProgram` is the geometry authoring layer for procedural products such as Denrim Form. It is a small renderer-owned scalar/vector VM, not arbitrary Metal source and not a list of product-specific hardcoded operators. Form geometry modules should compile into generic instructions and field `emit` calls, so deformations, curves, growth controls, and stable geometric attributes can be authored without RendererKit adding one public op per Form node. The named operation layer remains only as convenience syntax and compatibility sugar. The VM currently supports constants, scalar/vector arithmetic, min/max/abs, sin/cos, clamp/mix/smoothstep/step/saturate, fract/floor/mod, vector compose/extract, dot/length/normalize/distance, 3D value noise, 3D FBM, 3D cellular/Worley noise, box/cylinder/tapered-capsule/spline-tube distance intrinsics, union/subtract/smooth-union emit, candidate-scoped custom attributes, and optional coarse material field writes. Spline tube segments are the first organic-growth curve primitive; tapered capsules remain the lower-level straight segment primitive. Form can chain spline tube segments to approximate branch geometry while the editable timeline still owns the higher-level curve representation. A conservative optimizer folds constant instruction sequences before CPU/reference bakes and GPU packing. The VM runs in the CPU/reference baker for dense and sparse validation, and in the Metal direct-grid GPU-resident sparse baker for live-editable no-readback geometry and custom-attribute payloads.

`DistanceFieldMaterialProgram` is the hit-time surface authoring layer. It runs after SDF intersection at the final surface point, reads hit/local/world position, normal, base material state, and baked geometric attributes, then writes generic material fields. Its instruction set mirrors the geometry VM's scalar/vector math, procedural noise intrinsics, and SDF distance intrinsics, so Form can reuse the same expression compiler for procedural coordinates, masks, rings, ramps, and shape-aware material decisions. Its mask A-D lanes are program registers, not volume attributes. Form material/style modules such as cracks, dots, rings, wetness, moss, age tint, wood, and plant styling should compile here so material detail is independent of SDF field density and does not inherit voxel shell artifacts.

The baker can now emit either a dense `DistanceVolume` or a sparse `SparseDistanceVolume` made of occupied sample bricks. The Metal compute bake path currently handles transformed spheres, rounded boxes, cylinders, union/subtract, smooth union, and material IDs; graphs with compact attributes or baked material fields fall back to the CPU reference path to preserve correctness. Sparse bricks preserve distance/material/attribute samples and can expand back into a dense volume for CPU comparisons. `RenderScene` can carry sparse volume instances; scene compilation emits sparse volume descriptors, brick descriptors, brick sample payloads, and packed brick attribute payloads.

The flat Metal path renders dense volumes by raymarching dense volume buffers and sparse volumes by testing brick bounds before marching brick-local samples. The current sparse traversal uses a flat brick list; the next backend step is to replace that with a brick BVH or atlas indirection for larger edited fields. Metal ray tracing acceleration currently remains mesh-only; scenes containing distance volumes use the flat mixed-geometry path.

Renderer quality is treated as an internal integrator selection, not a host-side scene format change. `.preview` uses a flat single-hit kernel that shares the same mesh, dense-volume, sparse-brick, GPU-resident field, material, texture, generic material-field, mask/custom attribute, and AOV bindings as the path tracer but skips bounces, shadows, and accumulation blending. `.interactive` uses a realtime material-preview kernel over the same backend intersections and material payloads, adding deterministic direct area-light shading, transparent shadows, short-range scene-space contact ambient occlusion, low-frequency diffuse environment fill, roughness-filtered reflections with separate clearcoat response, simple transmission, and SSS-style material approximations without path-traced bounces. `.final` stays the progressive path-traced reference path. Pipelines are created lazily per quality so creating a `DenrimRenderer` or a Form viewport does not eagerly compile the full path tracer when only preview or interactive rendering is needed.

`RenderFieldBundle` is the public boundary for procedural host products. Denrim Form should keep its own editable timeline/operator document format, compile that authoring state into a `RenderFieldBundle`, and pass the bundle directly to `RenderScene`. RendererKit owns the bundle storage contract (`RenderFieldStorage.dense` / `.sparse` / `.gpuSparse`), optional hit-time `DistanceFieldMaterialProgram`, scene-local `RenderFieldID` handles, and future GPU upload details. SceneScript can represent comparable SDF bundles for examples, debugging, and CLI validation, but it is not the production realtime interchange format.

GPU-resident sparse field bundles are the first no-readback version of that contract. RendererKit's Metal baker can produce a `RenderGPUSparseFieldResource` whose large brick sample payload remains in an `MTLBuffer`; program bakes can also keep custom attribute samples and coarse material-field override samples resident. Scene compilation still creates compact descriptor/grid metadata and the render session binds those resident buffers directly. This first version intentionally supports one GPU-resident sparse sample buffer per scene and does not yet mix CPU sparse fields with GPU sparse fields. `RenderViewport.encodeUpdateGPUSparseFieldBricks` supports same-topology dirty-brick replacement by copying freshly baked GPU brick payloads into the resident field buffer and resetting accumulation without rebuilding the render session. `RenderViewport.replaceGPUSparseFieldPreservingSession` handles topology-changing GPU sparse edits by refreshing only the SDF descriptor/grid/sample buffers while keeping render targets and the session object alive; those compact buffers are updated in place when the replacement payload fits their current capacity. The baker can also over-allocate and reuse a previous GPU sparse sample buffer across topology-changing bakes, which gives Form an initial atlas-style residency path without reallocating the large payload buffer when the edited field still fits. For live edits that prefer no readback over compactness, `GPUResidentSparseMetadataMode.directGridGPU` writes renderer-compatible brick descriptors, grid indices, samples, program custom attribute samples, and program material-field samples directly on the GPU using one potential brick slot per grid cell; direct-grid bakes now use one threadgroup per brick so brick samples are evaluated in parallel. Sparse `sampleScale` is applied before both compacted and direct-grid GPU bakes by increasing sample dimensions and brick payload size together, preserving coarse brick topology while improving in-brick surface quality. `RenderGPUSparseFieldResource.directGridBrickIndices(overlappingLocalBoundsMin:localBoundsMax:padding:activeOnly:)` maps field-local edit bounds to direct-grid brick slots, so host apps do not duplicate RendererKit's grid math. `DistanceFieldBaker.encodeUpdateGPUResidentProgramBricks` can rebake selected direct-grid program brick slots in place for same-topology edits, and `RenderViewport.encodeUpdateGPUResidentProgramBricks` wraps that for live sessions by resolving the field handle, optionally converting world-space edit bounds through the instance transform, and resetting accumulation; material/attribute-only edits can pass `updatesTopology: false` to skip the macro-grid rebuild when the active brick set is unchanged. Scene compilation patches the scene-local volume index into those buffers, and sparse DDA intersects brick local bounds so transformed instances remain valid. The next residency step is GPU compaction/prefix-sum metadata and table indirection for multiple live fields.

The general update model is whole-bundle replacement through `replaceField`, with lower-level `replaceDenseField` / `replaceSparseField` helpers for tests and specialized code. `RenderViewport` is the live integration layer above this: it owns a `RenderScene` snapshot and current `RenderSession`, rebuilds the session transactionally after broad field or settings changes, and thereby restarts accumulation without making the host app manage stale session state. Camera-only edits use `RenderViewport.updateCamera(_:)`, which repacks the session's GPU camera arguments, preserves render targets and scene buffers, resets accumulation, and keeps the viewport scene snapshot current. For GPU sparse fields, dirty-brick updates preserve the session and only reset accumulation, while GPU sparse topology replacement refreshes only the SDF buffers. That gives editing apps a stable first contract without making Form own RendererKit's full GPU buffer format.

## Current Materials

`RenderScene.materials` stores plain renderer `Material` payloads. Built-in presets are convenience `Material` values, not a separate authored material layer. Dense and sparse volume hits apply generic baked material fields after material-ID blending. Form owns mask interpretation and material component styling; RendererKit owns generic transport, storage, and shading.

## Current Acceleration

The current render path uses GPU BVH traversal for scene intersections.

The package also contains a CPU BVH builder that:

* Computes triangle bounds.
* Splits primitives by centroid along the largest axis.
* Produces leaf nodes with bounded primitive counts.
* Preserves a primitive index remap.

The BVH is flattened into Metal-friendly buffers:

* `GPUAccelerationNode` stores minimum bounds, maximum bounds, child indices, first primitive, and primitive count.
* A primitive index buffer maps leaf primitive ranges back to triangle indices.
* `RenderSession` allocates these buffers as part of scene setup.
* `PathTrace.metal` traverses the flat BVH with a fixed local stack and falls back to linear traversal only if BVH data is absent.

`MetalRayTracingAccelerationBackend` currently wraps the flat BVH backend and, on devices where `supportsRaytracing` is true, creates per-mesh BLAS resources, a TLAS resource over scene instances, and shader-side local triangle / instance buffers. `MetalRayTracingTraversalProbe` can trace a single ray against that TLAS and compare the result with CPU intersection. `pathTraceHardwareKernel` now uses the TLAS for bounce and shadow intersections when `RenderSession` can bind the hardware resources; `pathTraceKernel` remains the flat BVH fallback. Tests can force either backend through an internal acceleration mode to compare deterministic primary AOVs.

Scene compilation builds compact emissive light records for direct light sampling. Each record stores the triangle index, material index, area, and geometric normal, so both the flat BVH and hardware TLAS kernels avoid scanning every triangle and avoid recomputing per-light area/normal data at each shading point. Materialized emissive triangles store their one-based light-record index, allowing BSDF-sampled emissive-hit MIS to recover the matching light PDF without scanning the whole light list.

## Current Lighting

The first path tracing kernel supports:

* Diffuse triangle surfaces.
* GGX-style rough metallic path sampling using material roughness and metallic parameters.
* Visible-normal GGX sampling and probability-compensated `BRDF * cos / PDF` weighting for sampled specular and clearcoat bounces.
* Schlick Fresnel weighting for direct light evaluation and GGX reflection lobes.
* Matching Fresnel and thickness-based clearcoat attenuation on sampled diffuse / base-specular indirect bounces, so the layered BRDF energy split is consistent between direct lighting and path continuation.
* Material-controlled dielectric specular weight, specular color, and index of refraction for GGX Fresnel F0.
* Material-controlled anisotropic GGX base-specular evaluation and sampling from mesh tangent frames.
* Clearcoat GGX lobe with material-controlled weight, Fresnel tint, independent attenuation color, thickness-based base-layer attenuation, roughness, and IOR.
* In-memory base color texture and tangent-space normal-map sampling from mesh UVs.
* ImageIO texture asset loading with explicit sRGB or linear import into `Texture2D`.
* Radiance `.hdr` texture loading for equirectangular environment lighting.
* HDRI importance sampling and MIS for direct environment lighting.
* Host-authored mesh light rigs by adding emissive triangle meshes or `QuadLight` instances to the scene. RendererKit does not add default lights to an empty `RenderScene`.
* Byte-scanned Wavefront OBJ import for large text meshes.
* Imported vertex normals are preserved when meshes are converted to GPU triangles.
* Packed texture nearest and bilinear filtering shared by flat BVH and hardware TLAS kernels.
* Emissive triangle lights.
* Power-weighted direct area-light sampling from compiled emissive light records for faster multi-light scenes.
* Constant-time light-record lookup for BSDF-sampled emissive-hit MIS through per-triangle light indices.
* First-pass MIS using power-heuristic weights between direct light samples and BSDF-sampled emissive hits.
* Cosine-weighted diffuse bounce sampling for non-metallic energy.
* Energy-preserving Russian roulette path termination after early bounces instead of a hard low-throughput cutoff.
* Progressive accumulation.
* Optional transparent background behavior for beauty output alpha and PNG export, plus camera-background environment visibility control for opaque viewports that still need HDRI lighting/refraction.
* Fully transparent alpha-cutout camera-ray pass-through before primary AOV capture.
* Rough dielectric transmissive transport with IOR/Fresnel reflection and refraction, measured exit absorption for visible paths and direct-light shadows, thin-walled straight-through sheet transmission, and transparent shadowing.
* Optional simple spatial GPU denoising for beauty output, guided by depth, normal, and albedo AOVs.

This is still a starter integrator. It exists to create a useful visual baseline before the renderer grows mipmapped Metal texture objects, semi-transparent blending, nested dielectric priority, layered materials, MetalFX / neural denoising, or richer Metal ray tracing features.

## Current AOVs

The current render session allocates internal AOV textures for:

* Depth
* Encoded normal
* Albedo
* Material ID
* Object ID
* Motion vector

These are written from the primary camera hit in `PathTrace.metal`.

The albedo output preserves primary material opacity in alpha. Fully transparent primary camera surfaces are skipped as alpha cutouts before AOV capture, but semi-transparent blending and refractive transport are not yet implemented.

They are used for tests, simple spatial denoising, export groundwork, and public output readback.

The public API exposes these outputs through `RenderOutput`. Applications can read exact floating-point pixels or export selected outputs to visualization PNGs. The PNG path uses output-specific encoding: ACES-fitted beauty tonemapping with alpha preservation, display gamma and opacity alpha preservation for albedo, display gamma for normals, dynamic visible-depth normalization, deterministic palette colors for material/object IDs, and neutral-gray signed motion-vector visualization. Denoising is off by default. When `RenderSettings.denoise` is explicitly set to `.appleSVGF`, beauty readback/export is sourced from Apple's MPS SVGF denoiser using packed depth/normal guidance and preserved beauty alpha. `.simpleSpatial` remains available as an internal experimental comparison filter, while the auxiliary outputs remain raw guidance buffers.

For app integrations that already own a Metal presentation path, `RenderSession.encodeNextSample(into:)` and `RenderSession.liveMetalTexture(for:)` expose a GPU-only live viewport path. `RenderViewport` forwards the same calls while also owning rebuild/reset behavior for editable scenes. This keeps progressive render modes, such as Denrim Forge's camera-only Render mode, on the GPU: the app can encode one renderer sample into its frame command buffer, fetch the raw beauty texture without launching hidden renderer work, and composite or blit it into its own viewport before presenting. These textures remain owned by the render session; public callers should treat them as read-only presentation resources rather than mutable render targets. `RenderSession.metalTexture(for:)` remains the synchronous access path for callers that want denoised beauty output resolved before using the texture.

The Metal camera packs perspective and orthographic projection into the same `GPUCamera` argument layout. Perspective cameras place the image plane one unit in front of the origin and use `origin.w == 0`. Orthographic cameras place the image plane at the camera origin, scale it by the requested vertical world-space size and aspect ratio, and use `origin.w == 1` so the shader emits parallel rays from per-pixel plane positions. This lets Forge pass its isometric camera scale directly instead of approximating an orthographic viewport with a distant perspective camera.

Scene framing is a RendererKit service because the renderer owns mesh, dense-volume, sparse-volume, GPU-resident field, and transform bounds. Hosts such as Form should use `RenderScene.worldBounds()` and `Camera.framing(...)` for frame-all / frame-selection behavior, then apply the result through `RenderViewport.updateCamera(_:)`. Host UI still owns the interaction policy, such as preserving orbit direction, applying authored center offsets, or animating the transition. `CameraLens` extends the same camera contract with focus distance and aperture radius; path-traced render qualities use a thin-lens camera ray while flat preview keeps deterministic pinhole rays.

The Metal path binds placeholder buffers for optional shader arrays such as texture descriptors, texture pixels, explicit lights, and environment samples when their logical counts are zero. This keeps hardware validation satisfied for kernels that declare those argument slots while preserving zero-count shader branches and public scene behavior.
