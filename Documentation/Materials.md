# Materials

DenrimRendererKit currently ships a deliberately small material model while the renderer core, acceleration backends, AOVs, texture path, and reference tests stabilize.

The current public `Material` supports:

* `baseColor`
* `roughness`
* `metallic`
* `specular`
* `specularColor`
* `indexOfRefraction`
* `specularAnisotropy`
* `clearcoat`
* `clearcoatColor`
* `clearcoatAttenuationColor`
* `clearcoatThickness`
* `clearcoatRoughness`
* `clearcoatIndexOfRefraction`
* `sheen`
* `sheenColor`
* `sheenRoughness`
* `emission`
* `emissionStrength`
* `opacity`
* `transmission`
* `transmissionColor`
* `transmissionRoughness`
* `transmissionIndexOfRefraction`
* `transmissionAbsorptionColor`
* `transmissionAbsorptionDistance`
* `thinWalled`
* `baseColorTexture`
* `normalMap`

`specular`, `specularColor`, `indexOfRefraction`, and `specularAnisotropy` are active shader controls. They drive the dielectric Fresnel F0 and anisotropic GGX base-specular lobe; the default IOR of 1.5, white specular color, and zero anisotropy keep the earlier hard-coded 0.04 isotropic dielectric F0 behavior. The anisotropic lobe uses mesh tangent / bitangent frames, including normal-map-adjusted frames, for direct lighting, MIS PDFs, and sampled indirect specular bounces. Specular and clearcoat bounce sampling use visible-normal GGX sampling, lobe-probability compensation, and GGX `BRDF * cos / PDF` weighting rather than Fresnel-only throughput. Sampled diffuse and base-specular indirect bounces apply the same Fresnel and clearcoat base-layer attenuation used by direct BRDF evaluation. `clearcoat`, `clearcoatColor`, `clearcoatAttenuationColor`, `clearcoatThickness`, `clearcoatRoughness`, and `clearcoatIndexOfRefraction` are active shader controls for a secondary isotropic GGX coating lobe that attenuates the base layer. `clearcoatColor` tints the coating Fresnel response. `clearcoatAttenuationColor` controls Beer-style attenuation through the coating depth and inherits `clearcoatColor` when omitted; thickness zero keeps the previous dielectric clearcoat behavior.

`sheen`, `sheenColor`, and `sheenRoughness` are active shader controls for a MoonRay-inspired fuzz / fabric lobe. The implementation uses a grazing Charlie-style sheen response for direct lighting and folds sheen energy into the diffuse sampling path for indirect bounces. It is intended for cloth, velvet-like stylized surfaces, dusty clay, and soft edge highlights without introducing a separate production fabric material yet.

`transmission`, `transmissionColor`, `transmissionRoughness`, `transmissionIndexOfRefraction`, `transmissionAbsorptionColor`, `transmissionAbsorptionDistance`, and `thinWalled` are active as dielectric transport controls. Transmissive solid surfaces sample reflection or refraction using exact dielectric Fresnel, independent roughness-driven GGX micro-normals, explicit transmission tint, independent transmission IOR, Beer-style exit absorption, and transparent direct-light shadow rays. Omitted transmission color, roughness, and IOR inherit from `baseColor`, `roughness`, and `indexOfRefraction` so existing materials keep their previous behavior. Absorption is disabled by default with distance zero; when enabled, `transmissionAbsorptionColor` is the remaining color after traveling `transmissionAbsorptionDistance` scene units through the solid. The same exit-distance absorption is applied to transparent direct-light shadow rays so tinted glass affects both visible paths and light visibility. `thinWalled` switches transmission to a zero-thickness sheet path that can reflect by Fresnel but transmits straight through without entering a refractive volume. This is suitable for glass validation assets such as the DiningRoom table and thin panes, leaves, or film-like sheets. It is not yet the final production dielectric stack: nested dielectric priority, caustic controls, dispersion, and semi-transparent blending are still future work.

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
* Specular: implemented first with specular weight, specular color, IOR, and anisotropy; later expand to anisotropy rotation and model selection.
* Transmission: implemented first with transmission weight, transmission color, transmission roughness, transmission IOR, and measured absorption; later expand to dispersion, nested dielectric priority, and caustic controls.
* Thin surfaces: implemented first with thin-walled specular transmission; later expand to diffuse transmission and richer shadow transparency controls.
* Clearcoat: implemented first with clearcoat weight, tint, independent attenuation color, thickness-based attenuation, roughness, and IOR; later expand to independent clearcoat normals.
* Sheen / fuzz: implemented first with sheen weight, sheen color, and sheen roughness; later expand to independent normal input and richer fabric / velvet controls.
* Subsurface: SSS weight, radius, color, scale, and model selection.
* Emission: emission color, strength, and light-record integration.
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

* `RenderScene.materialReference()` covers diffuse, rough metallic, material-controlled specular tint / IOR, sheen / fuzz shader control, clearcoat shader control, and emissive baseline behavior.
* `RenderScene.materialVariantReference(mesh:)` renders one caller-supplied mesh through matte / sheen, plastic, anisotropic brushed metal, polished metal, and tinted-clearcoat variants for visual material validation. It is suitable for local benchmark assets such as a Stanford Dragon PLY or OBJ without requiring the package to redistribute that mesh.
* `Examples/SceneScripts/MaterialVariants/material-variants.denrim` provides the same idea as a script template with reusable material includes, relative mesh paths, and checked-in rendered output.
* `Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim` is a self-contained glossy reflection target for polished, rough, and clearcoated silver. Bright, dark, and warm reflection cards make it useful for validating metal energy, Fresnel, and clearcoat behavior without tuning a large interior scene.
* `Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim` applies the same material set to the Stanford Dragon after `./Examples/Tools/fetch-stanford-dragon.sh` downloads the benchmark mesh.
* `RenderScene.transparentMaterialReference()` covers opacity planning, semi-transparent albedo alpha, fully transparent camera-ray cutout pass-through, measured absorption setup, and a rear visible surface for transmission / refraction comparison.

The transparent scene is intentionally a planning reference. Today it proves that opacity data reaches AOVs, fully transparent cutouts reveal rear surfaces, and transmissive materials exercise rough dielectric refraction with measured absorption parameters. It should keep growing into the first visual target for semi-transparent blending, nested dielectric priority, caustics behavior, and layered material behavior.
