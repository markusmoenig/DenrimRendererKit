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
* ProceduralMaterial.swift
* MaterialGraph.swift

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
* MetalRayTracingAccelerationBackend.swift

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
* Performance.md
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
* Persistent benchmark JSON outputs for device-specific historical comparison

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
* Explicit timing splits for scene loading, acceleration/session build, and sample rendering

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

Current Quality Direction

DenrimRendererKit should keep quality controls explicit and testable rather than hiding every choice inside the shader.

The current renderer already uses:

* Progressive accumulation
* Multiple-bounce path tracing
* Direct-light MIS for emissive triangles
* HDRI environment importance sampling
* BSDF / light MIS for emissive hits and environment misses
* Visible-normal GGX sampling for glossy specular and clearcoat bounces
* Russian roulette for deep low-contribution paths
* Optional denoising through raw AOV-guided outputs

Glossy artifacts are a near-term quality target. Low-roughness metals, clearcoat, glass, small emitters, and bright HDR texels can produce isolated hot samples long before a preview has enough samples to converge.

The first implemented mitigation is a per-sample radiance clamp exposed as `RenderSettings.sampleRadianceClamp` and the preview / benchmark `--quality` / `--sample-radiance-clamp` options. The setting defaults from `RenderQuality`: preview renders are stricter, interactive renders are moderate, and final renders preserve more high-energy samples. A value of `0` disables the clamp for physically stricter reference checks.

This clamp is intentionally a preview and review stability tool, not a replacement for better sampling. Future quality work should reduce the need for clamping by improving:

* Multiple importance sampling for all light paths
* Environment sampling resolution and filtering
* Rough dielectric transmission PDFs
* Caustic strategy for glass and polished surfaces
* Adaptive sampling / variance estimation
* Material-specific roughness and normal anti-aliasing
* Denoiser comparisons using stable AOV contracts

Material Quality Direction

The material system should remain small but grow along a Denrim Standard Surface path inspired by MoonRay production categories.

Current active material controls include base color, opacity, roughness, metallic, dielectric specular weight / color / IOR / anisotropy, clearcoat tint / thickness / attenuation / roughness / IOR, thin-film interference, sheen / fuzz, random-walk subsurface scattering, emission, rough transmission, measured absorption, thin-walled transmission, base color textures, and normal maps.

The priority is not to expose many inert fields. Each material control should either affect rendering, be documented as planning metadata, or stay out of the public API until the renderer can honor it.

Near-term material quality work:

* Continue validating metals, coated plastics, glass, ceramics, fabrics, and emissive panels through built-in presets.
* Improve low-roughness glossy stability without dulling polished material identity.
* Add clearer material-browser metadata for Denrim product UIs.
* Add normal-map anti-aliasing and authored normal strength.
* Expand transparent material behavior toward semi-transparent blending, nested dielectric priority, and caustic controls.
* Keep the material test ball, glossy metal reference, Dragon material variants, and DiningRoom fixture as manual visual review targets.

Speed and Tooling Direction

Performance should be measured as part of quality work, because quality regressions often arrive through slow scenes that no one wants to rerender.

The current tooling direction is:

* `denrim` is the main CLI for rendering `.denrim` files. It exports beauty and AOV outputs, defaults missing output paths to `./out.png`, accepts quality, bounce, backend, denoiser, transparency, and glossy-clamp options, writes optional benchmark JSON, and prints timing / throughput data after every render.
* `denrim material <preset-or-definition>` renders the material testball by injecting `PreviewMaterial` through SceneScript include resolution, so presets like `matte.clay` can be previewed without editing files.
* `denrim-render-preview` remains as a compatibility helper for built-in preview scenes.
* `denrim-render-benchmark` records scene loading, renderer creation, session / acceleration build, sample render time, quality, requested / active backend, path depth, throughput, and clamp setting in JSON.
* Example scripts render material variants, glossy-metal references, Dragon variants, DiningRoom quality images, and DiningRoom benchmarks with reproducible command lines.
* DiningRoom remains the heavy manual fixture for OBJ loading, texture loading, glossy interiors, glass, and material-tuning work.

Near-term speed work should focus on avoiding repeated work:

* Reuse `SceneAssetCache` from Denrim apps and tools that repeatedly parse the same scene.
* Cache parsed SceneScript structure where app lifetimes allow it.
* Avoid rebuilding unchanged BLAS / TLAS data between sessions.
* Separate scene compilation, acceleration build, and sample rendering timings everywhere.
* Keep hardware TLAS traversal and flat BVH parity tests close enough that speed work does not fork visual behavior.

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

The first implementation can use a CPU-built flat BVH with GPU traversal. The current architecture already has a guarded Metal ray tracing acceleration-structure path behind the acceleration backend: it maps local mesh records to Metal triangle geometry descriptors, builds BLAS resources, builds a TLAS over scene instances, includes a small hardware traversal probe that can be compared against CPU intersection, and uses a production hardware traversal kernel when the device supports it. The flat BVH render path remains the compatibility fallback. Later implementations should harden hardware-path parity, add more scene coverage, and adopt Metal 4 APIs where available.

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

* TLAS / BLAS style hierarchy
* Instance acceleration
* Metal ray tracing descriptor and sizing experiments
* Guarded Metal BLAS/TLAS resource builds
* Minimal hardware traversal probe with CPU reference comparison

Phase 3:

* Metal ray tracing integration in the production path tracing shader
* Hardware acceleration where available
* Software fallback where required
* Render session backend selection between hardware TLAS traversal and flat BVH traversal
* Initial hardware-vs-flat-BVH primary AOV parity test
* Built-in Cornell/material reference scene primary AOV parity tests
* Hardware-vs-flat-BVH beauty/direct-lighting parity metrics for reference scenes

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

Start simple, but design the public API and scripting system so procedural material inputs can grow without a breaking rewrite.

Material properties:

* Base Color
* Roughness
* Metallic
* Specular
* Emission
* Opacity

Version 1 material inputs:

* Textures
* Normal maps
* Simple generated textures
* Script-authored procedural masks

Future:

* Procedural noise, ramps, curvature, object-space, world-space, and triplanar inputs
* Material layering
* Principled shading / Denrim Standard Surface
* Material graph compilation and diagnostics

Procedural material support should be exposed through both:

* Swift API builders for Denrim apps
* SceneScript commands for tests, examples, automation, and Denrim Render

The scripting system should not merely assign fixed scalar material fields. It should be able to define reusable procedural values and bind them into material parameters.

Example SceneScript direction:

```text
proc noise marbleNoise noise3d scale 18 octaves 5 seed 7 space object
proc ramp marbleRamp marbleNoise 0.0 0.18 0.12 0.08 1.0 0.9 0.82 0.68
proc noise scratchMask noise2d scale 90 octaves 3 seed 12 space uv

material marble 1 1 1 roughness 0.38 specular 0.5 baseColorProc marbleRamp
material brushedMetal 0.8 0.76 0.68 metallic 1 roughnessProc scratchMask
```

Example Swift API direction:

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

The initial procedural model should be deliberately bounded:

* Constant values
* Solid colors
* Checker patterns
* 2D / 3D noise
* Fractal noise
* Ramps / color gradients
* Mix, multiply, add, clamp, remap
* UV, object-space, world-space, and triplanar coordinates
* Bump / normal perturbation from procedural height

These should compile into a compact GPU representation used by the same Metal material evaluation code as image textures. SceneScript and Swift should create the same intermediate representation so examples and app-authored scenes behave identically.

Procedural graphs should be deterministic, serializable, and suitable for visual regression scenes. Seeds, coordinate spaces, scale, and filtering behavior must be explicit.

Avoid an open-ended node editor or arbitrary user shader language in the first versions. Start with a small, typed procedural material graph that is scriptable, testable, and GPU-friendly.

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
3. Apple MPS SVGF denoiser
4. Simple spatial denoiser
5. À-trous / bilateral denoiser
6. MetalFX denoising where available
7. Open Image Denoise on macOS

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

* Metal acceleration structure descriptor planning
* Real Metal acceleration structure builds
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
* Procedural material inputs through both Swift API and SceneScript
* Procedural masks/noise/ramps for base color, roughness, metallic, specular, opacity, clearcoat, emission, and bump/normal inputs
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
* Wavefront OBJ and PLY mesh import through `Mesh(contentsOf:)`
* Byte-scanned OBJ importer for large text-mesh assets
* Imported vertex normals preserved through GPU triangle conversion
* Built-in Cornell Box scene
* Small line-based scene scripting language for test scenes and automation
* Reusable scene script includes/fragments with caller-provided resolution
* Scene script solid/checker texture definitions and material texture bindings
* Scene script image texture definitions with caller-provided base URL resolution
* Scene script OBJ/PLY mesh asset definitions and imported mesh instances with caller-provided base URL resolution
* Scene script file parsing with script-relative include, texture, and mesh asset resolution
* Scene script named/grouped geometry arguments with comma separators for camera, quad, box, and instance commands
* Scene script explicit sRGB/linear image decoding and nearest/linear sampler selection
* Scene script material specular color and IOR parameters
* Scene script material anisotropy parameter
* Scene script clearcoat weight, tint, attenuation color, thickness, roughness, IOR, and thin-film interference parameters
* Scene script transmission color, roughness, and IOR parameters
* Scene script transmission absorption color and distance parameters
* Scene script thin-walled material parameter for sheet transmission
* Metal compute path tracing kernel
* Progressive accumulation
* Diffuse triangle surfaces
* Mesh UV coordinates and per-triangle tangent frames for material evaluation
* GGX-style rough metallic path sampling using material roughness and metallic parameters
* Visible-normal GGX sampling and probability-compensated `BRDF * cos / PDF` weighting for sampled specular and clearcoat bounces
* Schlick Fresnel weighting for direct light evaluation and GGX reflection lobes
* Matched Fresnel and thickness-based clearcoat base-layer attenuation for sampled diffuse / base-specular indirect bounces
* Material-controlled dielectric specular weight, specular color, and index of refraction for GGX Fresnel F0
* Material-controlled anisotropic GGX base-specular evaluation, MIS PDF, and visible-normal sampling from mesh tangent frames
* Material-controlled clearcoat weight, Fresnel tint, independent attenuation color, thickness-based attenuation, roughness, index of refraction, and thin-film interference as a secondary GGX coating lobe
* Material-controlled transmission color, roughness, and independent index of refraction for rough dielectric transport
* Material-controlled measured absorption through transmissive solids using exit-distance Beer attenuation
* Material-controlled thin-walled transmission for zero-thickness sheets that reflect by Fresnel and transmit straight through
* MoonRay-inspired sheen / fuzz material controls with active shader evaluation
* Built-in material preset catalog queryable through Swift API and SceneScript, including generated preview metadata / thumbnails
* In-memory `Texture2D` inputs for base color textures and tangent-space normal maps
* ImageIO texture asset loading into `Texture2D`
* Radiance HDR/RGBE texture asset loading into `Texture2D`
* Scene environment API with equirectangular HDRI sampling on ray miss
* HDRI environment importance distribution and MIS for direct lighting
* Explicit sRGB-to-linear and linear texture import paths for color textures and data textures
* Metal nearest and bilinear texture sampling path shared by the flat BVH and hardware TLAS kernels
* Scene script nearest/linear sampler selection for generated textures
* Scene script environment image command with relative asset resolution
* Emissive triangle lights
* Direct area-light sampling
* Compiled emissive triangle light records shared by the flat BVH and hardware TLAS direct-light kernels
* Power-weighted direct-light importance sampling over compiled emissive light records
* Per-triangle light-record indices for constant-time BSDF-sampled emissive-hit MIS PDF lookup
* First-pass MIS weights between direct light sampling and BSDF-sampled emissive hits
* Energy-preserving Russian roulette path termination after early bounces
* Built-in material reference scene for diffuse, GGX-style rough metallic, specular tint / IOR, clearcoat control, and emissive baseline checks
* Material-variant reference scene for rendering one caller-supplied mesh with matte, plastic, anisotropic brushed metal, polished metal, and tinted clearcoat material variants
* Bundled SceneScript material-variant template with reusable material include, self-contained PLY fixture, and checked-in rendered output for visual validation
* Bundled glossy-metal SceneScript reference with bright, dark, and warm reflection cards for validating polished / rough / clearcoated metal behavior
* Persistent example SceneScript and render-output folder for future examples and references
* Stanford Dragon example scene and fetch script for local benchmark rendering
* Built-in transparent material reference scene for opacity, cutout, measured absorption setup, and transmission/refraction planning
* MoonRay-inspired material roadmap in `Documentation/Materials.md`
* Box mesh primitive for reference scenes
* PNG export
* Transparent beauty export with alpha-preserving PNG output
* Material opacity preserved in albedo AOV alpha and albedo PNG export
* Fully transparent alpha-cutout camera-ray pass-through for rear-surface visibility
* Rough dielectric transmissive material transport with independent IOR/Fresnel reflection and refraction, independent roughness, explicit tint, measured exit absorption for visible paths and direct-light shadows, thin-walled sheet transmission, and transparent shadowing
* Command line preview renderer
* Command line preview rendering for SceneScript files with relative asset resolution
* Unit tests for API defaults and scene construction
* Unit tests for OBJ mesh import, ASCII PLY import, binary little-endian PLY import, quad triangulation, relative indices, scientific-notation floats, imported normal preservation, and unsupported format reporting
* Unit tests for material specular color / IOR / anisotropy / clearcoat tint, attenuation color, thickness, thin-film controls, sheen, transmission, absorption, and thin-walled GPU parameter packing
* Texture asset loading tests for image dimensions, alpha, missing files, and sRGB/linear import behavior
* CPU triangle intersection reference tests
* Render smoke test with image decoding and orientation regression check
* Material reference render smoke test with image decoding and color variation checks
* Stored metric baselines for Cornell Box and material reference render tests
* Tolerant reference metric comparison for visual regression testing
* Stored scripted UV/normal-map AOV metric baselines for texture visual regression testing
* Stored transparent export alpha metric baseline
* Internal AOV textures for depth, normal, albedo, material ID, object ID, and motion vector
* Opt-in Apple MPS SVGF denoiser backend for beauty output guided by packed depth/normal AOVs, motion vectors, and temporal depth-normal history
* Opt-in experimental simple spatial GPU denoiser prototype for beauty output guided by depth, normal, and albedo AOVs
* AOV readback tests for primary surface data
* Material opacity AOV tests for albedo readback and PNG alpha preservation
* Alpha-cutout transport tests proving fully transparent primary surfaces reveal rear albedo and emission
* Transparent export tests for raw beauty alpha, default opaque sky behavior, PNG alpha preservation, and reference alpha metrics
* Transparent material reference render test proving semi-transparent albedo alpha and cutout rear-surface visibility
* Apple MPS SVGF and simple spatial denoiser render tests proving opt-in denoised beauty output is finite and distinct from raw low-sample beauty output
* Render-driven texture tests proving checker base color and normal-map data reach AOVs
* Render-driven texture filtering test proving bilinear sampling produces blended albedo
* Scripted UV/normal-map render test proving the DSL can author textured visual evaluation scenes
* Scripted image-texture render test proving external decoded assets can feed material albedo
* Scripted imported-mesh render test proving external OBJ/PLY assets can feed visual evaluation scenes
* Bundled material-variant script render test proving reusable scripted visual-validation scenes load and render
* Scene script file parsing tests for script-relative includes and assets
* PNG export for selected render outputs
* Output-specific PNG visualization encoding for depth, ID, and motion-vector buffers
* Primary-hit camera motion vector AOV using previous-camera projection
* Internal acceleration backend abstraction
* Internal BLAS/TLAS-style instance acceleration model with local mesh BVHs, instance records, and top-level instance bounds
* Deduplicated mesh acceleration records so repeated mesh instances share local BVH / BLAS setup
* CPU BVH builder with bounds, centroid splitting, leaf nodes, and tests
* Flattened GPU-friendly BVH node and primitive-index buffers
* GPU BVH traversal in the Metal path tracing kernel
* Emissive triangle light-record scene compilation with tests for emissive and non-emissive scenes
* Materialized mesh instance transforms for the current flat-triangle Metal compute path
* Experimental Metal ray tracing acceleration backend scaffold that detects `supportsRaytracing`, creates per-mesh BLAS resources, creates a TLAS resource over scene instances, records acceleration-structure and scratch-buffer sizes, and preserves the current BVH render path
* Minimal Metal ray tracing traversal probe kernel that traces a ray against the TLAS and is tested against the CPU triangle intersector
* Production Metal ray tracing path tracing kernel that traverses the TLAS for bounce and shadow intersections on supported devices, with flat BVH fallback still available
* Automatic hardware traversal sessions skip unused flat fallback BVH construction when Metal ray tracing resources are available
* Internal render acceleration mode selection for parity testing and fallback validation
* First hardware-vs-flat-BVH parity render test comparing depth, normal, and albedo AOVs
* Built-in Cornell Box and material reference hardware-vs-flat-BVH parity tests comparing depth, normal, albedo, material ID, and object ID outputs
* Hardware-vs-flat-BVH beauty/direct-lighting parity metrics comparing average and maximum RGB difference for reference scenes
* Command line render benchmark executable for timing scene load, renderer creation, session creation, and render throughput
* Command line benchmark JSON output for persistent comparison in `Examples/Benchmarks`
* Opt-in XCTest performance benchmarks gated by `DENRIM_RUN_PERFORMANCE_TESTS=1`
* `Documentation/Performance.md` with benchmark commands, JSON fields, and first optimization targets
* DiningRoom scene-load benchmark reduced from roughly 5.39s to roughly 0.66s on Apple M1 Max by replacing string-tokenized OBJ parsing with byte-scanned parsing
* Local documentation seeds in Documentation/

Not yet implemented:

* Texture mipmapping, GPU texture objects, and richer sampler-state control
* Procedural material graph API and matching SceneScript procedural commands
* Procedural noise, ramps, coordinate nodes, color/value math, triplanar mapping, and procedural bump/normal inputs
* Stored performance baselines by Apple device class and backend
* Broader Denrim Standard Surface material API with anisotropy rotation, independent clearcoat normals, subsurface, layering, and material diagnostics
* Semi-transparent blending, nested dielectric priority, caustic controls, and layered material behavior
* MetalFX integration, Open Image Denoise backends, deeper temporal denoising controls, and denoiser comparison scenes
* GLB import
* Heightmaps, voxels, SDFs, and participating media

Immediate next milestones:

1. Add texture mipmapping, GPU texture objects, and richer sampler-state control.
2. Add a small procedural material graph shared by the Swift API and SceneScript, starting with noise, ramps, math, coordinate nodes, and bindings to base color, roughness, metallic, opacity, clearcoat, and bump/normal inputs.
3. Add performance baselines for Cornell, material reference, material variants, and Stanford Dragon scenes by Apple device class and backend.
4. Continue staging the Denrim Standard Surface API, then add semi-transparent blending, nested dielectric priority, caustic controls, and layered material behavior.
5. Extend motion vectors to include object/instance deformation on top of instance records.
6. Add stored metrics or image baselines for the transparent material reference scene once semi-transparent transport stabilizes.
