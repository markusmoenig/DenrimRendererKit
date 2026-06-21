DenrimRendererKit

Concept

DenrimRendererKit is an open source Swift Package providing a high quality Metal based path tracer for the Denrim ecosystem.

The goal is to create one shared rendering core which can be used by all current and future Denrim products:

* Denrim: Forge
* Denrim: Voxel
* Denrim: Terrain
* Denrim: Render
* Future Denrim tools

The renderer should be Apple native, written in Swift and Metal, and designed for macOS and iPadOS.

The architecture is inspired by professional production renderers such as MoonRay, but intentionally smaller, focused, embeddable, and suitable for Apple platforms.

Core Goal

Build a best quality reusable path tracer with a clean scene abstraction and an extensible hit/intersection system.

The renderer should focus first on triangle meshes, but the architecture must allow additional primitive systems later:

* Meshes
* Voxel scenes
* Heightmaps
* Signed distance fields
* Procedural primitives

The path tracer itself should not care what kind of object was hit. It should only receive a unified hit result.

Conceptually:

Ray → Scene Intersection → Hit → Material Evaluation → Path Tracing

Every geometry backend should implement the same conceptual operation:

intersect(ray) -> closest Hit?

Multiple geometry systems must be able to live in the same scene.

For example, a single render may contain:

* Imported triangle meshes
* Voxel-derived meshes
* Bounded SDF rocks
* Heightmap terrain
* Procedural primitives

The path tracer should not contain separate mesh, SDF, voxel, or terrain shading paths. It should ask the scene for the closest surface interaction and receive one common Hit structure.

Conceptually:

closestSurfaceHit(ray)

* Mesh backend
* Heightmap backend
* Voxel backend
* SDF backend
* Procedural primitive backend

Return nearest Hit.

This keeps mixed scenes possible without turning the renderer core into a set of special cases.

Design Philosophy

DenrimRendererKit should be:

* Apple native
* Metal first
* Metal 4 ready where available
* Swift Package based
* Open source by default
* Reusable across apps
* High quality rather than game-engine real-time
* Progressive and interactive
* Simple to integrate
* Small enough to understand
* Professional in architecture
* Open source friendly

Open source as a Swift Package is the right distribution model.

It gives DenrimRendererKit:

* A clean reusable boundary across Denrim products
* Direct integration into macOS and iPadOS apps
* A familiar dependency model for Swift developers
* A simple public API surface
* A natural place for DocC documentation
* A practical path for community use and contribution

The public API should remain stable even as the internal Metal backend improves.

Applications should integrate DenrimRendererKit through scene, material, camera, render session, and output APIs. They should not depend on whether a given device uses a Swift-built BVH, Metal ray tracing acceleration structures, Metal 4 acceleration structures, or future Apple denoising and machine-learning APIs internally.

It should not attempt to become a full MoonRay, Cycles, or Blender replacement.

It should instead be a focused renderer for Denrim-style assets:

* Stylized meshes
* Low-poly models
* Voxel-derived geometry
* Heightmap terrain
* Procedural SDF details
* Small to medium scenes
* High quality still renders
* Progressive viewport previews

Package Structure

DenrimRendererKit/

Package.swift

Sources/

DenrimRendererKit/

Renderer/

* DenrimRenderer.swift
* RenderSession.swift
* RenderSettings.swift
* RenderTarget.swift

Scene/

* Scene.swift
* Camera.swift
* Transform.swift
* Instance.swift
* Light.swift
* Material.swift
* Texture.swift

Geometry/

* Mesh.swift
* MeshInstance.swift
* GeometryProvider.swift
* Heightmap.swift
* SDFObject.swift
* VoxelGeometry.swift

Acceleration/

* BVH.swift
* BVHBuilder.swift
* MetalAccelerationBuilder.swift
* AccelerationBackend.swift

Metal/

* MetalDevice.swift
* MetalPipeline.swift
* MetalBuffers.swift
* MetalPathTracer.swift
* MetalRayTracingBackend.swift
* MetalFeatureSupport.swift

Import/

* OBJImporter.swift
* GLTFImporter.swift

Denoising/

* Denoiser.swift
* TemporalAccumulator.swift
* SimpleSpatialDenoiser.swift
* MetalFXDenoiser.swift

Documentation/

* API.md
* Architecture.md
* Integration.md
* RenderSettings.md
* Materials.md
* Geometry.md
* Outputs.md
* Testing.md
* WebsiteExport.md

Tests/

* DenrimRendererKitTests/
* RenderReferenceTests/
* ShaderTests/
* TestScenes/

Resources/
Shaders/

* PathTrace.metal
* Intersections.metal
* Materials.metal
* Sampling.metal
* Lights.metal
* Random.metal
* Accumulation.metal
* Denoise.metal
* Media.metal
* SDF.metal
* Heightmap.metal
* Voxel.metal

Public API

The external API should be simple.

Example usage:

import DenrimRendererKit

let renderer = try DenrimRenderer(device: metalDevice)

let scene = RenderScene()

scene.add(mesh)
scene.add(material)
scene.add(light)

let session = try renderer.makeSession(scene: scene)

session.renderNextSample()

The application should never need to know about:

* BVH layout
* Shader internals
* Sampling implementation
* Acceleration structures
* GPU memory management
* Metal feature fallbacks
* Denoiser implementation details

API Documentation

API documentation should be maintained from day one.

The documentation is part of the renderer, not a separate marketing layer. Every public type, public method, and public setting should have clear comments and examples before it becomes part of the stable API.

Documentation should be collected inside this package first.

The local documentation should serve three purposes:

* Help Denrim apps integrate the renderer correctly
* Define the stable public API contract
* Provide source material for the Denrim website

The website at ../Denrim-Web should consume or mirror the documentation later, but DenrimRendererKit remains the source of truth for renderer API documentation.

Documentation targets:

* Swift DocC comments for all public Swift APIs
* Markdown guides in Documentation/
* Architecture notes explaining internal renderer design
* Integration guides for Forge, Voxel, Terrain, and Render
* Render setting reference
* Material and geometry reference
* Output buffer and denoising reference
* Website export notes for syncing into ../Denrim-Web

Documentation should evolve with the API.

When a public API changes, the documentation should change in the same commit or work step. Undocumented public API should be treated as unfinished API.

Testing and Visual Evaluation

DenrimRendererKit should have tests from the beginning.

The test system should include both normal automated tests and render-based visual evaluation.

Test categories:

* Unit tests for Swift scene, material, camera, transform, and BVH code
* Shader validation tests where practical
* CPU reference checks for geometry intersection
* GPU render smoke tests
* Reference image tests for known scenes
* Visual evaluation renders for material, lighting, and global illumination behavior
* Performance benchmarks for sample throughput and acceleration builds

Render tests should produce images.

They should be used for:

* Regression detection
* Visual quality review
* Comparing denoisers
* Comparing acceleration backends
* Checking platform differences between macOS and iPadOS
* Documenting renderer progress over time

Reference test scenes should include small, known scenes that exercise specific renderer behavior:

* Cornell Box for indirect illumination and color bleeding
* Material ball grid for roughness, metallic, specular, emission, and opacity
* Area light scene for soft shadows
* Environment lighting scene for HDR and sky behavior
* Transparent background scene for exports
* Smooth normals scene for mesh shading
* UV texture scene for texture correctness
* Instance scene for transforms and TLAS behavior
* Sponza-style scene for complex indirect lighting
* Terrain scene for heightmap rendering
* Bounded SDF scene for procedural primitive evaluation
* Mixed geometry scene with mesh, heightmap, voxel, and SDF objects
* Future atmosphere scene for sky and fog evaluation

Reference images should not be treated as perfect truth for all time. Path tracers evolve, sampling changes, denoisers change, and Apple GPU behavior may differ by device. The test system should support:

* Exact or near-exact checks for deterministic low-level tests
* Tolerant image comparisons for render tests
* Manual visual approval for major renderer improvements
* Stored before/after images for important quality changes
* Optional benchmark baselines per device class

Visual evaluation should become part of development culture.

Every major renderer feature should add or update at least one scene that makes the feature visible.

Rendering Modes

RenderQuality

* Preview
* Interactive
* Final

Preview

Fast progressive rendering for editing.

* Low sample count
* Lower bounce count
* Fast reset
* Optional denoising

Interactive

Higher quality for viewport work.

* Better lighting
* More samples
* Indirect illumination
* Progressive accumulation

Final

Maximum quality output.

* High sample counts
* Multiple bounces
* Full resolution
* Transparent background export
* Optional macOS denoising

Geometry Abstraction

The most important architectural decision.

The path tracer must never know which geometry type it is intersecting.

Conceptually:

closestHit(ray)

* Mesh BVH
* Heightmap accelerator
* SDF objects
* Voxel accelerator

Return nearest hit.

The renderer should always operate on a unified Hit structure.

This allows future geometry systems without modifying the renderer core.

Unified Hit

The Hit structure should describe a surface interaction, not the implementation that produced it.

It should contain:

* Ray distance
* World position
* Geometric normal
* Shading normal
* UV coordinates when available
* Material ID
* Object ID
* Instance ID
* Primitive ID
* Geometry kind for debugging and diagnostics

The geometry kind is useful for debug views and selection, but normal material evaluation should not branch into separate renderers for meshes, SDFs, heightmaps, or voxels.

Mixed Geometry

Scenes must support mixed geometry.

A scene may contain mesh instances, terrain heightmaps, bounded SDF objects, and voxel accelerators at the same time.

The scene intersection system is responsible for querying all active geometry backends and returning the closest valid Hit.

Conceptually:

* Query mesh acceleration
* Query heightmap acceleration
* Query voxel acceleration
* Query SDF bounds and local SDF intersections
* Return the closest hit across all systems

The path tracer then shades that hit through the normal material system.

Meshes

Version 1 focus.

Used by:

* Denrim Forge
* Imported OBJ
* Imported GLB
* Converted voxel meshes

Requirements:

* Triangle mesh rendering
* Instances
* Smooth normals
* UV coordinates
* Materials
* BVH acceleration

Heightmaps

Future geometry type.

Possible approaches:

* Triangle patches
* Native heightfield traversal
* Tile acceleration
* Heightfield BVH

Used by:

* Denrim Terrain
* Real-world terrain rendering
* Procedural landscapes

Voxels

Initially converted into meshes.

Future native support:

* Sparse voxel hierarchy
* Brick structures
* DDA traversal
* Material IDs

Used by:

* Denrim Voxel

SDF Objects

Future geometry type.

Each SDF object contains:

* Bounding box
* Distance function
* Material
* Transform

Used for:

* Procedural rocks
* Rounded primitives
* Boolean operations
* Caves
* Organic structures

The entire scene should not be one giant SDF.

SDFs should be bounded local objects.

Bounded SDFs allow procedural detail without forcing the entire scene to become one global signed distance field.

Each SDF object should have:

* Local transform
* World-space bounding box
* Distance function ID
* Material ID
* Ray-marching settings

The acceleration system should first intersect the ray with the SDF object's bounds. Only then should it run the SDF traversal inside that local volume.

Participating Media

Atmosphere, fog, clouds, smoke, and other participating media should be supported later as a separate concept from surface geometry.

Surfaces answer:

intersectSurface(ray) -> Hit?

Media answer:

sampleMedium(ray, maxDistance) -> MediumEvent?

The path tracer should eventually evaluate both:

Ray → Surface Intersection → Medium Sampling → Surface or Volume Shading → Next Ray

This makes it possible to support:

* Sky atmosphere
* Ground fog
* Local fog volumes
* Volumetric light beams
* Clouds
* Dust and haze
* Underwater attenuation
* Terrain atmosphere
* Voxel volumes

Version 1 should not implement participating media. The scene and renderer architecture should simply avoid choices that would make media difficult later.

Medium Event

A future MediumEvent should describe a volume interaction.

It may contain:

* Ray distance
* World position
* Medium ID
* Scattering coefficient
* Absorption coefficient
* Emission
* Phase function ID

This keeps surface shading and volume shading cleanly separated while allowing them to interact in the same path tracing loop.

Acceleration

High quality rendering requires strong acceleration structures.

Acceleration should be represented internally by a backend abstraction.

The first implementation can use a CPU-built flat BVH with GPU traversal. Later implementations can use Apple Metal ray tracing acceleration structures and Metal 4 APIs where available.

Conceptually:

AccelerationBackend

* Build or update acceleration data
* Encode GPU resources
* Provide scene intersection support to Metal shaders

Public Denrim APIs should not change when the acceleration backend changes.

Phase 1:

* CPU BVH builder in Swift
* Flat BVH representation
* GPU traversal in Metal

Phase 2:

* Metal ray tracing integration
* TLAS / BLAS style hierarchy
* Instance acceleration
* Hardware acceleration where available
* Software fallback where required

Future:

* Heightmap acceleration
* Voxel acceleration
* SDF acceleration
* Mixed-geometry acceleration
* Local medium acceleration

The acceleration system must remain internal.

The public API should never change because of acceleration improvements.

Apple Metal Integration

DenrimRendererKit should use modern Apple GPU APIs wherever they are available while keeping compatibility fallbacks internally.

Preferred Apple technologies:

* Metal compute for path tracing kernels
* Metal ray tracing acceleration structures
* TLAS / BLAS style instance acceleration
* Metal 4 acceleration and command APIs where available
* Argument buffers for scene data
* Heaps and resource aliasing where useful
* Binary archives or packaged libraries for shader startup performance
* MetalFX denoising for interactive preview and viewport rendering
* MetalFX upscaling where appropriate for interactive modes
* Future Metal machine-learning command encoders for neural tone mapping or custom denoisers

The renderer should detect available device and OS capabilities and choose the best backend automatically.

Render settings may allow users to request quality and behavior, but not require app code to manage low-level Metal feature selection.

Materials

Start simple.

Material properties:

* Base Color
* Roughness
* Metallic
* Specular
* Emission
* Opacity

Future:

* Textures
* Normal maps
* Material layering
* Principled shading

Avoid node-based materials in the first versions.

Lights

Version 1:

* Directional light
* Sun light
* Point light
* Area light
* Emissive materials
* Sky gradient

Future:

* HDR environments
* Importance sampling
* Environment maps

Output Buffers

Support multiple render outputs.

Version 1:

* Beauty
* Depth
* Normal
* Albedo
* Object ID
* Material ID
* Motion vectors

These are useful for:

* Denoising
* Selection
* Compositing
* Debugging
* Temporal stability

Interactive denoising requires high quality auxiliary buffers. Albedo, normals, depth, and motion vectors should be produced deliberately rather than treated as debug-only outputs.

Denoising

Denoising must remain optional.

Support levels:

1. None
2. Temporal accumulation
3. Simple spatial denoiser
4. À-trous / bilateral denoiser
5. MetalFX denoising where available
6. Open Image Denoise on macOS

The renderer must remain fully functional without MetalFX or Open Image Denoise.

MetalFX should be a first-class target for Preview and Interactive quality modes because it is integrated with Apple platforms and designed for low-sample interactive rendering.

Final quality rendering should still be able to converge without denoising.

Metal Shader Organization

Shaders:

* PathTrace.metal
* Intersections.metal
* Materials.metal
* Sampling.metal
* Lights.metal
* Random.metal
* Accumulation.metal
* Denoise.metal
* Media.metal
* SDF.metal
* Heightmap.metal
* Voxel.metal

Shaders should be packaged inside the Swift Package.

Progressive Rendering

The renderer should always be progressive.

Each frame contributes additional samples.

When the camera, scene, materials, or lights change:

resetAccumulation()

Rendering then restarts from sample one.

This makes the renderer suitable for all editor workflows.

Integration Targets

Denrim Forge

* High quality model rendering
* Material preview
* Turntables
* Transparent PNG export
* Asset thumbnails

Denrim Voxel

* Voxel asset rendering
* Ambient occlusion
* Stylized lighting
* Export images

Denrim Terrain

* Heightmap rendering
* Terrain previews
* Sun and sky lighting
* Large landscape rendering

Denrim Render

Standalone renderer application built entirely on DenrimRendererKit.

Functions:

* Import files
* Assign materials
* Configure lighting
* Render still images
* Showcase renderer capabilities

Import Support

Version 1:

* OBJ

Version 2:

* GLB
* glTF

Optional:

* USDZ

Reference scenes:

* Cornell Box
* Stanford Bunny
* Stanford Dragon
* Damaged Helmet
* Sponza

Non Goals

Version 1 should not implement:

* Full USD pipeline
* Material node graphs
* Animation rendering
* Volumes
* Atmosphere
* Hair
* Spectral rendering
* Distributed rendering
* Blender replacement
* Full production renderer complexity

Development Roadmap

Phase 1

Swift Package, documentation foundation, and minimal mesh path tracer.

* Public scene API
* Public API documentation structure
* Initial DocC comments
* Documentation/ source guides
* Initial test structure
* Cornell Box render test
* Render sessions
* Camera rays
* Triangle intersection
* Progressive accumulation
* PNG export
* Cornell Box

Phase 2

Acceleration abstraction and BVH.

* Internal AccelerationBackend protocol
* CPU BVH builder
* GPU BVH traversal
* Instances
* Stanford Bunny
* Stanford Dragon
* BVH intersection tests

Phase 3

Metal ray tracing backend.

* Metal acceleration structures
* TLAS / BLAS style instances
* Hardware acceleration where available
* CPU BVH fallback where required
* Mixed backend capability detection
* Backend comparison render tests

Phase 4

Lighting and materials.

* Principled material
* Area lights
* Emissive materials
* Multiple bounces
* Importance sampling
* HDR environment foundation
* Material and lighting reference scenes

Phase 5

Output buffers and denoising.

* Beauty
* Depth
* Normal
* Albedo
* Object ID
* Material ID
* Motion vectors
* Temporal accumulation
* MetalFX denoising where available
* Denoiser comparison scenes

Phase 6

Forge integration.

* Asset rendering
* Thumbnails
* Transparent exports

Phase 7

Importers.

* OBJ
* GLB
* Textures
* Damaged Helmet

Phase 8

Terrain support.

* Heightmap rendering
* Tile acceleration
* Mixed mesh and heightmap scenes

Phase 9

SDF support.

* Bounded SDF objects
* Procedural primitives
* Mixed mesh and SDF scenes
* Local SDF acceleration

Phase 10

Voxel acceleration.

* Native voxel traversal
* Sparse voxel hierarchy
* Brick structures
* Mixed mesh, SDF, heightmap, and voxel scenes

Phase 11

Participating media.

* Sky atmosphere
* Local fog volumes
* Clouds
* MediumEvent abstraction
* Surface and medium path tracing

Phase 12

Standalone application.

* Denrim Render
* File import
* Lighting setup
* High quality exports

Quality Target

The renderer is designed for beautiful still images rather than game-engine frame rates.

Goals:

* Soft shadows
* Global illumination
* Ambient occlusion
* Progressive convergence
* Accurate materials
* Transparent exports
* Attractive defaults
* Professional image quality

Summary

DenrimRendererKit is a shared Swift/Metal rendering framework for the entire Denrim ecosystem.

The renderer starts with high quality BVH-accelerated mesh rendering and evolves toward a unified rendering architecture supporting meshes, heightmaps, voxels, and SDFs through a common hit abstraction.

Inspired by MoonRay and other production renderers, it focuses on Apple platforms, Swift Package integration, Metal acceleration, beautiful image quality, and long-term reuse across all Denrim products.

Current Implementation Status

The first implementation slice is now underway.

Implemented:

* Swift Package scaffold
* Public renderer, render session, render settings, scene, camera, transform, mesh, material, ray, and surface hit APIs
* Public render output API for beauty, depth, normal, albedo, material ID, object ID, and motion vector
* Public floating-point output pixel readback
* Built-in Cornell Box scene
* Small line-based scene scripting language for test scenes and automation
* Reusable scene script includes/fragments with caller-provided resolution
* Metal compute path tracing kernel
* Progressive accumulation
* Diffuse triangle surfaces
* GGX-style rough metallic path sampling using material roughness and metallic parameters
* Schlick Fresnel weighting for direct light evaluation and specular bounce sampling
* Emissive triangle lights
* Direct area-light sampling
* Built-in material reference scene for diffuse, GGX-style rough metallic, and emissive baseline checks
* Box mesh primitive for reference scenes
* PNG export
* Command line preview renderer
* Unit tests for API defaults and scene construction
* CPU triangle intersection reference tests
* Render smoke test with image decoding and orientation regression check
* Material reference render smoke test with image decoding and color variation checks
* Stored metric baselines for Cornell Box and material reference render tests
* Tolerant reference metric comparison for visual regression testing
* Internal AOV textures for depth, normal, albedo, material ID, object ID, and motion vector
* AOV readback tests for primary surface data
* PNG export for selected render outputs
* Output-specific PNG visualization encoding for depth, ID, and motion-vector buffers
* Primary-hit camera motion vector AOV using previous-camera projection
* Internal acceleration backend abstraction
* Internal BLAS/TLAS-style instance acceleration model with local mesh BVHs, instance records, and top-level instance bounds
* CPU BVH builder with bounds, centroid splitting, leaf nodes, and tests
* Flattened GPU-friendly BVH node and primitive-index buffers
* GPU BVH traversal in the Metal path tracing kernel
* Materialized mesh instance transforms for the current flat-triangle Metal compute path
* Local documentation seeds in Documentation/

Not yet implemented:

* Metal ray tracing acceleration structures
* Hardware TLAS/BLAS-backed Metal ray tracing traversal
* Texture and normal-map inputs
* Transmission, opacity, and layered material behavior
* Denoising
* OBJ / GLB import
* Heightmaps, voxels, SDFs, and participating media

Immediate next milestones:

1. Start Metal ray tracing acceleration structure experiments behind the acceleration backend.
2. Add texture and normal-map inputs to the material path.
3. Add transmission, opacity, and layered material behavior.
4. Extend motion vectors to include object/instance deformation on top of instance records.
5. Add light-list scene compilation for emissive geometry.
