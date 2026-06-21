# Architecture

DenrimRendererKit keeps the public app-facing API separate from the internal rendering backend.

The first implementation is intentionally small:

* Public Swift scene types describe cameras, materials, meshes, and render settings.
* `RenderSession` owns a snapshot of the compiled scene.
* Scene compilation now builds a BLAS/TLAS-style instance acceleration model before materializing triangles for the current GPU path.
* The acceleration backend prepares triangle, material, flat BVH node, and primitive-index GPU buffers.
* A Metal compute kernel traces rays, samples emissive triangles for direct lighting, accumulates samples, writes an image, and records primary-surface AOVs.
* The current shader uses flat BVH traversal for scene intersections.

The important architectural boundary is the internal acceleration backend.

Today it is a linear triangle list. Later it can become:

* CPU-built BVH with GPU traversal.
* Metal ray tracing acceleration structures.
* Metal 4 ray tracing backend.
* Mixed geometry backend for meshes, heightmaps, SDFs, and voxels.

The public Denrim API should not change when those internal backends change.

## Current Scripting

`SceneScript` provides a small line-based scene language.

The first version supports:

* Comments
* Camera setup
* Materials
* Quads
* Boxes

This is meant to make reference scenes easier to author and eventually make Denrim Render scriptable. It should remain a focused scene-description layer, not a replacement for import formats such as OBJ, glTF, or USDZ.

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

Direct light sampling still scans the triangle list to find emissive triangles. A future light list should replace that scan once the renderer has more scene compilation structure.

## Current Lighting

The first path tracing kernel supports:

* Diffuse triangle surfaces.
* GGX-style rough metallic path sampling using material roughness and metallic parameters.
* Schlick Fresnel weighting for direct light evaluation and specular bounce sampling.
* Emissive triangle lights.
* Direct area-light sampling for faster Cornell Box convergence.
* Cosine-weighted diffuse bounce sampling for non-metallic energy.
* Progressive accumulation.

This is still a starter integrator. It exists to create a useful visual baseline before the renderer grows transmission, layered materials, denoising, or a Metal ray tracing backend.

## Current AOVs

The current render session allocates internal AOV textures for:

* Depth
* Encoded normal
* Albedo
* Material ID
* Object ID
* Motion vector

These are written from the primary camera hit in `PathTrace.metal`.

They are used for tests, denoising/export groundwork, and public output readback.

The public API exposes these outputs through `RenderOutput`. Applications can read exact floating-point pixels or export selected outputs to visualization PNGs. The PNG path uses output-specific encoding: beauty tonemapping, display gamma for albedo/normal, dynamic visible-depth normalization, deterministic palette colors for material/object IDs, and neutral-gray signed motion-vector visualization.
