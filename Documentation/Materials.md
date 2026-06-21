# Materials

DenrimRendererKit currently ships a deliberately small material model while the renderer core, acceleration backends, AOVs, texture path, and reference tests stabilize.

The current public `Material` supports:

* `baseColor`
* `roughness`
* `metallic`
* `specular`
* `specularColor`
* `indexOfRefraction`
* `clearcoat`
* `clearcoatRoughness`
* `clearcoatIndexOfRefraction`
* `emission`
* `emissionStrength`
* `opacity`
* `baseColorTexture`
* `normalMap`

`specular`, `specularColor`, and `indexOfRefraction` are active shader controls. They drive the dielectric Fresnel F0 used by the current GGX specular lobe; the default IOR of 1.5 and white specular color keep the earlier hard-coded 0.04 dielectric F0 behavior. `clearcoat`, `clearcoatRoughness`, and `clearcoatIndexOfRefraction` are active shader controls for a secondary GGX coating lobe that attenuates the base layer.

This is enough for the first reusable path tracing vertical slice, but it is not the intended final material system.

## MoonRay Reference

MoonRay's material system is much broader than the current Denrim API. Its `DwaSolidDielectricMaterial` is documented as having about 90 attributes, and the MoonRay docs describe `DwaBaseMaterial` as an uber shader for transferring values from third-party uber shaders while `DwaSolidDielectricMaterial` is the general-purpose material for wood, paint, plastic, stone, clay, and similar surfaces.

Relevant MoonRay material families and properties include:

* Diffuse and albedo controls.
* Diffuse roughness and diffuse transmission.
* Subsurface scattering with BSSRDF model, scattering color, and scattering radius.
* Specular roughness, anisotropy, tangent direction, metallic color, edge color, specular model, and IOR.
* Transmission and refraction with transmission color, transmission roughness, independent IOR, and dispersion.
* Clearcoat with roughness, thickness, IOR, attenuation color, and independent clearcoat normals.
* Presence / cutout visibility for masks and thin geometry.
* Fuzz / sheen style lobes.
* Iridescence controls.
* Glitter controls.
* Normal maps, normal strength, and normal anti-aliasing behavior.
* Layered, mixed, switched, two-sided, emissive, refractive, skin, fabric, toon, velvet, metal, and hair materials.
* Production controls such as light sets, caustic flags, material labels, extra AOVs, and material priority for overlapping dielectrics.

DenrimRendererKit should learn from those categories without copying MoonRay wholesale. The goal is a focused Apple-native renderer for Denrim products, not a complete production renderer clone.

## Denrim Standard Surface Direction

The next public material shape should become a Denrim Standard Surface that can grow without breaking existing scenes.

Recommended staged properties:

* Base: base color, opacity / presence, roughness, metallic, normal map.
* Specular: implemented first with specular weight, specular color, and IOR; later expand to anisotropy, anisotropy rotation, and model selection.
* Transmission: transmission weight, transmission color, transmission roughness, transmission IOR.
* Thin surfaces: thin-walled mode, diffuse transmission, shadow transparency.
* Clearcoat: implemented first with clearcoat weight, clearcoat roughness, and clearcoat IOR; later expand to clearcoat tint, thickness, attenuation color, and independent clearcoat normals.
* Sheen / fuzz: sheen weight, sheen color, sheen roughness.
* Subsurface: SSS weight, radius, color, scale, and model selection.
* Emission: emission color, strength, and light-list integration.
* Layering: material layering or coating as an explicit API rather than a large bag of unrelated fields.
* Diagnostics: material AOV labels and stable IDs.

Each property should be added only when the renderer can either implement it or clearly document it as stored planning metadata. Controls that do nothing should not be exposed as if they are physically active.

## Procedural Materials

Procedural material support should be a first-class part of the Denrim Standard Surface direction, exposed through both the Swift API and SceneScript.

The intended model is a small typed material graph, not an arbitrary shader language. Swift code and scripts should both be able to create the same procedural inputs and bind them to material parameters such as base color, roughness, metallic, specular, opacity, clearcoat, emission, and bump/normal.

Initial procedural nodes should include:

* Constant scalar and color values.
* Checker, 2D noise, 3D noise, and fractal noise.
* Ramps and color gradients.
* Mix, add, multiply, clamp, and remap.
* UV, object-space, world-space, and triplanar coordinate sources.
* Procedural bump / normal perturbation from height values.

The graph must be deterministic and serializable so scripted reference scenes can produce stable visual validation images. Seeds, coordinate spaces, scale, filtering, and color-space behavior should be explicit in both APIs.

## Current Reference Coverage

Current built-in material reference scenes:

* `RenderScene.materialReference()` covers diffuse, rough metallic, material-controlled specular tint / IOR, clearcoat shader control, and emissive baseline behavior.
* `RenderScene.materialVariantReference(mesh:)` renders one caller-supplied mesh through matte, plastic, metallic, polished, and clearcoat variants for visual material validation. It is suitable for local benchmark assets such as a Stanford Dragon PLY or OBJ without requiring the package to redistribute that mesh.
* `Examples/SceneScripts/MaterialVariants/material-variants.denrim` provides the same idea as a script template with reusable material includes, relative mesh paths, and checked-in rendered output.
* `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim` applies the same material set to the Stanford Dragon after `./Examples/Tools/fetch-stanford-dragon.sh` downloads the benchmark mesh.
* `RenderScene.transparentMaterialReference()` covers opacity planning, semi-transparent albedo alpha, fully transparent camera-ray cutout pass-through, and a rear visible surface for future transmission / refraction comparison.

The transparent scene is intentionally a planning reference. Today it proves that opacity data reaches AOVs and that fully transparent cutouts reveal rear surfaces. Later it should become the first visual target for semi-transparent blending, shadow transparency, transmission, refraction, and layered material behavior.
