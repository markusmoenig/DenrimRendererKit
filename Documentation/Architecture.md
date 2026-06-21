# Architecture

DenrimRendererKit keeps the public app-facing API separate from the internal rendering backend.

The first implementation is intentionally small:

* Public Swift scene types describe cameras, materials, meshes, and render settings.
* `RenderSession` owns a snapshot of the compiled scene.
* Scene compilation now builds a BLAS/TLAS-style instance acceleration model before materializing triangles for the current GPU path.
* The acceleration backend prepares triangle, material, texture, emissive light-index, flat BVH node, and primitive-index GPU buffers.
* `RenderSession` currently uses an experimental Metal ray tracing acceleration backend wrapper that builds guarded BLAS/TLAS resources while preserving the flat BVH fallback.
* A small internal Metal ray tracing traversal probe can trace one ray against the TLAS for CPU-reference comparison.
* Metal compute kernels trace rays, sample emissive triangles for direct lighting, accumulate samples, write an image, and record primary-surface AOVs.
* The current render session uses the hardware TLAS traversal kernel when available and falls back to the flat BVH kernel otherwise.
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
* Solid, checker, and image texture definitions
* OBJ and PLY mesh definitions
* Materials
* Base color texture and normal-map bindings
* Quads
* Boxes
* Imported mesh instances

Image texture paths are resolved through caller-controlled base URLs so tests and apps can choose their own bundle or filesystem policy. This is meant to make reference scenes easier to author and eventually make Denrim Render scriptable. It should remain a focused scene-description layer, not a replacement for import formats such as OBJ, glTF, or USDZ.

The first asset import paths are Wavefront OBJ and PLY via `Mesh(contentsOf:)`. They are deliberately small and feed the same `Mesh` API used by procedural primitives, reference scenes, and scene scripts. The PLY path supports ASCII and binary little-endian mesh files with vertex positions, optional normals / UVs, and polygon face lists. glTF/GLB import remains future work.

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

Scene compilation builds a compact emissive triangle index list for direct light sampling. Both the flat BVH and hardware TLAS kernels iterate that list instead of scanning every triangle in the scene and filtering non-emissive materials at shading time.

## Current Lighting

The first path tracing kernel supports:

* Diffuse triangle surfaces.
* GGX-style rough metallic path sampling using material roughness and metallic parameters.
* Schlick Fresnel weighting for direct light evaluation and specular bounce sampling.
* Material-controlled dielectric specular weight, specular color, and index of refraction for GGX Fresnel F0.
* Clearcoat GGX lobe with material-controlled weight, roughness, and IOR.
* In-memory base color texture and tangent-space normal-map sampling from mesh UVs.
* ImageIO texture asset loading with explicit sRGB or linear import into `Texture2D`.
* Packed texture nearest and bilinear filtering shared by flat BVH and hardware TLAS kernels.
* Emissive triangle lights.
* Direct area-light sampling from a compiled emissive triangle light list for faster Cornell Box convergence.
* Cosine-weighted diffuse bounce sampling for non-metallic energy.
* Progressive accumulation.
* Optional transparent background behavior for beauty output alpha and PNG export.
* Fully transparent alpha-cutout camera-ray pass-through before primary AOV capture.

This is still a starter integrator. It exists to create a useful visual baseline before the renderer grows mipmapped Metal texture objects, semi-transparent blending, shadow transparency, refraction/transmission, layered materials, denoising, or richer Metal ray tracing features.

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

They are used for tests, denoising/export groundwork, and public output readback.

The public API exposes these outputs through `RenderOutput`. Applications can read exact floating-point pixels or export selected outputs to visualization PNGs. The PNG path uses output-specific encoding: beauty tonemapping with alpha preservation, display gamma and opacity alpha preservation for albedo, display gamma for normals, dynamic visible-depth normalization, deterministic palette colors for material/object IDs, and neutral-gray signed motion-vector visualization.
