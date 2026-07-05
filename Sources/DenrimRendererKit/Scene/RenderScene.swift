import Foundation
import simd

/// Optional render defaults authored by a scene script or host application.
public struct RenderDefaults: Sendable {
    /// Default output path. Relative script-authored paths are resolved by `SceneScript.parse(contentsOf:)`.
    public var outputPath: String?

    /// Default output type.
    public var output: RenderOutput?

    /// Default progressive sample count.
    public var samples: Int?

    /// Default output width.
    public var width: Int?

    /// Default output height.
    public var height: Int?

    /// Default quality intent.
    public var quality: RenderQuality?

    /// Default maximum path depth.
    public var maxBounces: Int?

    /// Default acceleration backend.
    public var accelerationMode: RenderAccelerationMode?

    /// Default per-sample radiance clamp.
    public var sampleRadianceClamp: Float?

    /// Default transparent background export behavior.
    public var transparentBackground: Bool?

    /// Default denoising settings.
    public var denoise: DenoiseSettings?

    /// Default SDF volume build resolution for scene-script volumes.
    public var sdfResolution: Int?

    /// Creates empty render defaults.
    public init(
        outputPath: String? = nil,
        output: RenderOutput? = nil,
        samples: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        quality: RenderQuality? = nil,
        maxBounces: Int? = nil,
        accelerationMode: RenderAccelerationMode? = nil,
        sampleRadianceClamp: Float? = nil,
        transparentBackground: Bool? = nil,
        denoise: DenoiseSettings? = nil,
        sdfResolution: Int? = nil
    ) {
        self.outputPath = outputPath
        self.output = output
        self.samples = samples
        self.width = width
        self.height = height
        self.quality = quality
        self.maxBounces = maxBounces
        self.accelerationMode = accelerationMode
        self.sampleRadianceClamp = sampleRadianceClamp
        self.transparentBackground = transparentBackground
        self.denoise = denoise
        self.sdfResolution = sdfResolution
    }
}

/// A renderable scene containing camera, materials, mesh instances, and distance volumes.
public struct RenderScene: Sendable {
    /// Scene camera.
    public var camera: Camera

    /// Materials available to scene geometry.
    public private(set) var materials: [Material]

    /// Authored material sources. These are the material system source of truth;
    /// `materials` stores their resolved renderer payloads.
    public private(set) var materialSources: [SemanticMaterial]

    /// Mesh instances in the scene.
    public private(set) var meshInstances: [MeshInstance]

    /// Distance-volume instances in the scene.
    public private(set) var volumeInstances: [DistanceVolumeInstance]

    /// Sparse distance-volume instances in the scene.
    public private(set) var sparseVolumeInstances: [SparseDistanceVolumeInstance]

    /// Environment lighting sampled by rays that miss scene geometry.
    public var environment: Environment

    /// Optional render defaults used by command-line tools and host applications.
    public var renderDefaults: RenderDefaults

    /// Creates an empty render scene.
    public init(
        camera: Camera = Camera(
            origin: SIMD3<Float>(0, 1, 4),
            target: SIMD3<Float>(0, 1, 0)
        ),
        environment: Environment = .sky,
        renderDefaults: RenderDefaults = RenderDefaults()
    ) {
        self.camera = camera
        self.environment = environment
        self.renderDefaults = renderDefaults
        self.materialSources = []
        self.materials = []
        self.meshInstances = []
        self.volumeInstances = []
        self.sparseVolumeInstances = []
    }

    /// Adds an expanded renderer material and returns its scene-local identifier.
    @discardableResult
    public mutating func addMaterial(_ material: Material) -> MaterialID {
        addMaterial(SemanticMaterial.physical(material))
    }

    /// Adds an authored semantic material and returns its scene-local identifier.
    @discardableResult
    public mutating func addMaterial(_ material: SemanticMaterial) -> MaterialID {
        let id = MaterialID(rawValue: UInt32(materialSources.count))
        materialSources.append(material)
        materials.append(material.resolvedMaterial())
        return id
    }

    /// Adds a mesh instance using an existing material.
    public mutating func add(
        mesh: Mesh,
        material: MaterialID,
        transform: Transform = .identity
    ) {
        meshInstances.append(MeshInstance(
            mesh: mesh,
            material: material,
            transform: transform
        ))
    }

    /// Adds a signed-distance volume instance using an existing material.
    public mutating func add(
        volume: DistanceVolume,
        material: MaterialID,
        transform: Transform = .identity
    ) {
        volumeInstances.append(DistanceVolumeInstance(
            volume: volume,
            material: material,
            transform: transform
        ))
    }

    /// Adds a sparse signed-distance volume instance using an existing material.
    public mutating func add(
        sparseVolume: SparseDistanceVolume,
        material: MaterialID,
        transform: Transform = .identity
    ) {
        sparseVolumeInstances.append(SparseDistanceVolumeInstance(
            volume: sparseVolume,
            material: material,
            transform: transform
        ))
    }

    /// Adds a renderable SDF field bundle using its fallback material.
    ///
    /// This is the preferred integration point for procedural products such as
    /// Denrim Form. The bundle may be backed by dense samples or sparse bricks;
    /// RendererKit routes it to the current mixed-geometry backend.
    @discardableResult
    public mutating func add(
        fieldBundle: RenderFieldBundle,
        transform: Transform = .identity
    ) -> RenderFieldID {
        switch fieldBundle.storage {
        case .dense(let volume):
            let index = volumeInstances.count
            add(volume: volume, material: fieldBundle.fallbackMaterial, transform: transform)
            return RenderFieldID(storage: .dense, index: index)
        case .sparse(let volume):
            let index = sparseVolumeInstances.count
            add(sparseVolume: volume, material: fieldBundle.fallbackMaterial, transform: transform)
            return RenderFieldID(storage: .sparse, index: index)
        }
    }

    /// Replaces an existing field using a handle returned by `add(fieldBundle:)`.
    ///
    /// The current replacement API preserves the field storage family. If an
    /// editor wants to switch a field from dense to sparse, rebuild the scene or
    /// add a new field and discard the old handle.
    @discardableResult
    public mutating func replaceField(
        _ id: RenderFieldID,
        with fieldBundle: RenderFieldBundle,
        transform: Transform? = nil
    ) -> Bool {
        switch id.storage {
        case .dense:
            return replaceDenseField(at: id.index, with: fieldBundle, transform: transform)
        case .sparse:
            return replaceSparseField(at: id.index, with: fieldBundle, transform: transform)
        }
    }

    /// Replaces an existing dense field instance.
    ///
    /// This first replacement API is intentionally whole-bundle based. Interactive
    /// editors can use it for near-term rebuilds while RendererKit grows partial
    /// dirty-brick update support.
    @discardableResult
    public mutating func replaceDenseField(
        at index: Int,
        with fieldBundle: RenderFieldBundle,
        transform: Transform? = nil
    ) -> Bool {
        guard volumeInstances.indices.contains(index) else {
            return false
        }
        guard case .dense(let volume) = fieldBundle.storage else {
            return false
        }
        let existingTransform = volumeInstances[index].transform
        volumeInstances[index] = DistanceVolumeInstance(
            volume: volume,
            material: fieldBundle.fallbackMaterial,
            transform: transform ?? existingTransform
        )
        return true
    }

    /// Replaces an existing sparse field instance.
    ///
    /// This first replacement API is intentionally whole-bundle based. Interactive
    /// editors can use it for near-term rebuilds while RendererKit grows partial
    /// dirty-brick update support.
    @discardableResult
    public mutating func replaceSparseField(
        at index: Int,
        with fieldBundle: RenderFieldBundle,
        transform: Transform? = nil
    ) -> Bool {
        guard sparseVolumeInstances.indices.contains(index) else {
            return false
        }
        guard case .sparse(let volume) = fieldBundle.storage else {
            return false
        }
        let existingTransform = sparseVolumeInstances[index].transform
        sparseVolumeInstances[index] = SparseDistanceVolumeInstance(
            volume: volume,
            material: fieldBundle.fallbackMaterial,
            transform: transform ?? existingTransform
        )
        return true
    }

    /// Adds an app-authored quad area light.
    ///
    /// RendererKit does not create lights by default. Host applications can use this
    /// helper to express rectangular area lights without manually creating the
    /// emissive material and quad mesh.
    @discardableResult
    public mutating func addQuadLight(_ light: QuadLight) -> MaterialID {
        let material = addMaterial(light.material)
        add(
            mesh: .quad(light.a, light.b, light.c, light.d),
            material: material
        )
        return material
    }

    /// Creates the built-in Cornell Box reference scene.
    public static func cornellBox() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 1, 3.4),
                target: SIMD3<Float>(0, 1, 0),
                verticalFieldOfViewDegrees: 42
            )
        )

        let white = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.78, 0.78, 0.74)))
        let red = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.65, 0.05, 0.04)))
        let green = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.12, 0.45, 0.15)))
        let light = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            emission: SIMD3<Float>(1, 0.86, 0.62),
            emissionStrength: 14
        ))

        scene.add(mesh: .quad(
            SIMD3<Float>(-1, 0, 1),
            SIMD3<Float>(1, 0, 1),
            SIMD3<Float>(1, 0, -1),
            SIMD3<Float>(-1, 0, -1)
        ), material: white)
        scene.add(mesh: .quad(
            SIMD3<Float>(-1, 2, -1),
            SIMD3<Float>(1, 2, -1),
            SIMD3<Float>(1, 2, 1),
            SIMD3<Float>(-1, 2, 1)
        ), material: white)
        scene.add(mesh: .quad(
            SIMD3<Float>(-1, 0, -1),
            SIMD3<Float>(1, 0, -1),
            SIMD3<Float>(1, 2, -1),
            SIMD3<Float>(-1, 2, -1)
        ), material: white)
        scene.add(mesh: .quad(
            SIMD3<Float>(-1, 0, 1),
            SIMD3<Float>(-1, 0, -1),
            SIMD3<Float>(-1, 2, -1),
            SIMD3<Float>(-1, 2, 1)
        ), material: red)
        scene.add(mesh: .quad(
            SIMD3<Float>(1, 0, -1),
            SIMD3<Float>(1, 0, 1),
            SIMD3<Float>(1, 2, 1),
            SIMD3<Float>(1, 2, -1)
        ), material: green)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.28, 1.99, -0.25),
            SIMD3<Float>(0.28, 1.99, -0.25),
            SIMD3<Float>(0.28, 1.99, 0.25),
            SIMD3<Float>(-0.28, 1.99, 0.25)
        ), material: light)

        return scene
    }

    /// Creates the built-in material reference scene for diffuse, metallic, roughness, clearcoat, and emissive baseline checks.
    public static func materialReference() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 1.65, 5.2),
                target: SIMD3<Float>(0, 0.75, 0),
                verticalFieldOfViewDegrees: 38
            )
        )

        let floor = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.62, 0.62, 0.58)))
        let back = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.38, 0.42, 0.48)))
        let warm = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.95, 0.42, 0.24), roughness: 0.8))
        let cool = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.18, 0.44, 0.9), roughness: 0.18, metallic: 1))
        let green = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.72, 0.35),
            roughness: 0.58,
            sheen: 0.65,
            sheenColor: SIMD3<Float>(0.72, 1.0, 0.82),
            sheenRoughness: 0.72
        ))
        let violet = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.62, 0.36, 0.95),
            roughness: 0.35,
            metallic: 0.55,
            specularColor: SIMD3<Float>(0.85, 0.72, 1.0),
            indexOfRefraction: 1.65,
            clearcoat: 0.35,
            clearcoatRoughness: 0.06,
            clearcoatIndexOfRefraction: 1.55
        ))
        let bright = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.95, 0.86, 0.42), roughness: 0.08, metallic: 1))
        let light = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            emission: SIMD3<Float>(1, 0.9, 0.72),
            emissionStrength: 10
        ))

        scene.add(mesh: .quad(
            SIMD3<Float>(-3, 0, 2.2),
            SIMD3<Float>(3, 0, 2.2),
            SIMD3<Float>(3, 0, -2.2),
            SIMD3<Float>(-3, 0, -2.2)
        ), material: floor)
        scene.add(mesh: .quad(
            SIMD3<Float>(-3, 0, -2.2),
            SIMD3<Float>(3, 0, -2.2),
            SIMD3<Float>(3, 2.8, -2.2),
            SIMD3<Float>(-3, 2.8, -2.2)
        ), material: back)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.8, 2.75, -0.6),
            SIMD3<Float>(0.8, 2.75, -0.6),
            SIMD3<Float>(0.8, 2.75, 0.4),
            SIMD3<Float>(-0.8, 2.75, 0.4)
        ), material: light)

        let box = Mesh.box(size: SIMD3<Float>(0.58, 0.58, 0.58))
        let placements: [(MaterialID, SIMD3<Float>)] = [
            (warm, SIMD3<Float>(-1.6, 0.29, 0.15)),
            (cool, SIMD3<Float>(-0.8, 0.29, -0.1)),
            (green, SIMD3<Float>(0, 0.29, 0.1)),
            (violet, SIMD3<Float>(0.8, 0.29, -0.05)),
            (bright, SIMD3<Float>(1.6, 0.29, 0.12))
        ]

        for (index, placement) in placements.enumerated() {
            let transform = Transform.translation(placement.1)
                * Transform.rotationY(radians: Float(index) * 0.28 - 0.45)
            scene.add(mesh: box, material: placement.0, transform: transform)
        }

        return scene
    }

    /// Creates a reference scene that renders the same mesh with several material variants.
    ///
    /// This is intended for common look-development meshes such as the Stanford Dragon,
    /// but the mesh is caller-supplied so the package does not have to vendor
    /// third-party benchmark assets.
    public static func materialVariantReference(mesh: Mesh) -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 1.45, 5.8),
                target: SIMD3<Float>(0, 0.62, 0),
                verticalFieldOfViewDegrees: 34
            )
        )

        let floor = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.58, 0.58, 0.54), roughness: 0.85))
        let back = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.34, 0.37, 0.43), roughness: 0.75))
        let light = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            emission: SIMD3<Float>(1, 0.93, 0.82),
            emissionStrength: 9
        ))
        let matteClay = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.82, 0.42, 0.26),
            roughness: 0.88,
            specular: 0.35,
            sheen: 0.35,
            sheenColor: SIMD3<Float>(1.0, 0.72, 0.52),
            sheenRoughness: 0.8
        ))
        let satinPlastic = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.45, 0.95),
            roughness: 0.32,
            specular: 0.75,
            specularColor: SIMD3<Float>(0.9, 0.96, 1),
            indexOfRefraction: 1.48
        ))
        let brushedMetal = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.86, 0.72, 0.46),
            roughness: 0.42,
            metallic: 1,
            specularAnisotropy: 0.72
        ))
        let polishedMetal = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.72, 0.78, 0.82), roughness: 0.12, metallic: 1))
        let coated = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.22, 0.72, 0.38),
            roughness: 0.46,
            specular: 0.85,
            indexOfRefraction: 1.52,
            clearcoat: 0.55,
            clearcoatColor: SIMD3<Float>(0.78, 1.0, 0.84),
            clearcoatRoughness: 0.05,
            clearcoatIndexOfRefraction: 1.55
        ))

        scene.add(mesh: .quad(
            SIMD3<Float>(-3.4, 0, 2.25),
            SIMD3<Float>(3.4, 0, 2.25),
            SIMD3<Float>(3.4, 0, -2.25),
            SIMD3<Float>(-3.4, 0, -2.25)
        ), material: floor)
        scene.add(mesh: .quad(
            SIMD3<Float>(-3.4, 0, -2.25),
            SIMD3<Float>(3.4, 0, -2.25),
            SIMD3<Float>(3.4, 2.7, -2.25),
            SIMD3<Float>(-3.4, 2.7, -2.25)
        ), material: back)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.95, 2.62, -0.7),
            SIMD3<Float>(0.95, 2.62, -0.7),
            SIMD3<Float>(0.95, 2.62, 0.45),
            SIMD3<Float>(-0.95, 2.62, 0.45)
        ), material: light)

        let variants: [(MaterialID, SIMD3<Float>, Float)] = [
            (matteClay, SIMD3<Float>(-2.0, 0, 0.1), -0.35),
            (satinPlastic, SIMD3<Float>(-1.0, 0, -0.05), -0.12),
            (brushedMetal, SIMD3<Float>(0, 0, 0.06), 0.08),
            (polishedMetal, SIMD3<Float>(1.0, 0, -0.04), 0.28),
            (coated, SIMD3<Float>(2.0, 0, 0.08), 0.48)
        ]
        let normalized = normalizedMeshTransform(mesh: mesh, targetMaxExtent: 0.82)
        for variant in variants {
            scene.add(
                mesh: mesh,
                material: variant.0,
                transform: Transform.translation(variant.1)
                    * Transform.rotationY(radians: variant.2)
                    * normalized
            )
        }

        return scene
    }

    /// Creates the built-in material-variant reference scene with a simple self-contained mesh.
    public static func materialVariantReference() -> RenderScene {
        materialVariantReference(mesh: .box(size: SIMD3<Float>(0.8, 1.0, 0.8)))
    }

    /// Creates the built-in transparent material planning scene for opacity and future transmission checks.
    public static func transparentMaterialReference() -> RenderScene {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 1.35, 4.6),
                target: SIMD3<Float>(0, 0.7, 0),
                verticalFieldOfViewDegrees: 38
            )
        )

        let floor = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.58, 0.60, 0.56)))
        let back = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.34, 0.38, 0.44)))
        let opaque = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.92, 0.32, 0.20), roughness: 0.55))
        let semiTransparent = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.48, 0.92),
            roughness: 0.18,
            opacity: 0.45,
            transmission: 0.75,
            transmissionColor: SIMD3<Float>(0.58, 0.78, 1.0),
            transmissionRoughness: 0.05,
            transmissionIndexOfRefraction: 1.45,
            transmissionAbsorptionColor: SIMD3<Float>(0.64, 0.82, 1.0),
            transmissionAbsorptionDistance: 0.8
        ))
        let cutout = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            roughness: 0.5,
            opacity: 0
        ))
        let rearPanel = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.82, 0.36),
            emission: SIMD3<Float>(0.18, 0.82, 0.36),
            emissionStrength: 0.6,
            roughness: 0.7
        ))
        let light = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            emission: SIMD3<Float>(1, 0.9, 0.72),
            emissionStrength: 9
        ))

        scene.add(mesh: .quad(
            SIMD3<Float>(-2.4, 0, 1.7),
            SIMD3<Float>(2.4, 0, 1.7),
            SIMD3<Float>(2.4, 0, -1.8),
            SIMD3<Float>(-2.4, 0, -1.8)
        ), material: floor)
        scene.add(mesh: .quad(
            SIMD3<Float>(-2.4, 0, -1.8),
            SIMD3<Float>(2.4, 0, -1.8),
            SIMD3<Float>(2.4, 2.4, -1.8),
            SIMD3<Float>(-2.4, 2.4, -1.8)
        ), material: back)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.65, 2.25, -0.75),
            SIMD3<Float>(0.65, 2.25, -0.75),
            SIMD3<Float>(0.65, 2.25, 0.05),
            SIMD3<Float>(-0.65, 2.25, 0.05)
        ), material: light)

        scene.add(
            mesh: Mesh.box(size: SIMD3<Float>(0.52, 0.52, 0.52)),
            material: opaque,
            transform: Transform.translation(SIMD3<Float>(-0.95, 0.26, 0.05))
                * Transform.rotationY(radians: -0.35)
        )
        scene.add(
            mesh: Mesh.box(size: SIMD3<Float>(0.58, 0.58, 0.58)),
            material: semiTransparent,
            transform: Transform.translation(SIMD3<Float>(0, 0.29, -0.05))
                * Transform.rotationY(radians: 0.35)
        )
        scene.add(mesh: .quad(
            SIMD3<Float>(0.72, 0.22, 0.22),
            SIMD3<Float>(1.58, 0.22, 0.22),
            SIMD3<Float>(1.58, 1.06, 0.22),
            SIMD3<Float>(0.72, 1.06, 0.22)
        ), material: cutout)
        scene.add(mesh: .quad(
            SIMD3<Float>(0.72, 0.22, -0.12),
            SIMD3<Float>(1.58, 0.22, -0.12),
            SIMD3<Float>(1.58, 1.06, -0.12),
            SIMD3<Float>(0.72, 1.06, -0.12)
        ), material: rearPanel)

        return scene
    }

    private static func distanceVolumeReferenceContents() -> (
        scene: RenderScene,
        model: SDFModel,
        settings: DistanceVolumeBuildSettings,
        fallbackMaterial: MaterialID
    ) {
        var scene = RenderScene(
            camera: Camera(
                origin: SIMD3<Float>(0, 1.35, 4.8),
                target: SIMD3<Float>(0, 0.68, 0),
                verticalFieldOfViewDegrees: 38
            )
        )

        let floor = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.58, 0.60, 0.56), roughness: 0.74))
        let back = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.32, 0.37, 0.43), roughness: 0.82))
        let red = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.92, 0.22, 0.14),
            roughness: 0.62,
            clearcoat: 0.18,
            clearcoatRoughness: 0.08
        ))
        let transparent = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.56, 0.95),
            roughness: 0.08,
            opacity: 0.42,
            transmission: 0.82,
            transmissionColor: SIMD3<Float>(0.62, 0.84, 1.0),
            transmissionRoughness: 0.03,
            transmissionIndexOfRefraction: 1.38,
            transmissionAbsorptionColor: SIMD3<Float>(0.68, 0.84, 1.0),
            transmissionAbsorptionDistance: 0.9
        ))
        let metal = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.74, 0.86, 0.95),
            roughness: 0.18,
            metallic: 1,
            specularAnisotropy: 0.45,
            clearcoat: 0.12,
            clearcoatRoughness: 0.04
        ))
        let yellow = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.95, 0.72, 0.18),
            roughness: 0.38,
            sheen: 0.25,
            sheenColor: SIMD3<Float>(1.0, 0.86, 0.42)
        ))
        let rearPanel = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.84, 0.42),
            emission: SIMD3<Float>(0.18, 0.84, 0.42),
            emissionStrength: 0.7,
            roughness: 0.65
        ))
        let light = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(1, 1, 1),
            emission: SIMD3<Float>(1, 0.9, 0.72),
            emissionStrength: 10
        ))

        scene.add(mesh: .quad(
            SIMD3<Float>(-3.0, 0, 2.0),
            SIMD3<Float>(3.0, 0, 2.0),
            SIMD3<Float>(3.0, 0, -2.0),
            SIMD3<Float>(-3.0, 0, -2.0)
        ), material: floor)
        scene.add(mesh: .quad(
            SIMD3<Float>(-3.0, 0, -2.0),
            SIMD3<Float>(3.0, 0, -2.0),
            SIMD3<Float>(3.0, 2.5, -2.0),
            SIMD3<Float>(-3.0, 2.5, -2.0)
        ), material: back)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.8, 2.36, -0.75),
            SIMD3<Float>(0.8, 2.36, -0.75),
            SIMD3<Float>(0.8, 2.36, 0.25),
            SIMD3<Float>(-0.8, 2.36, 0.25)
        ), material: light)
        scene.add(mesh: .quad(
            SIMD3<Float>(-0.66, 0.16, -0.38),
            SIMD3<Float>(0.36, 0.16, -0.38),
            SIMD3<Float>(0.36, 1.16, -0.38),
            SIMD3<Float>(-0.66, 1.16, -0.38)
        ), material: rearPanel)

        let model = SDFModel(primitives: [
            SDFPrimitive(
                shape: .sphere(radius: 0.5),
                material: red,
                transform: Transform.translation(SIMD3<Float>(-1.25, 0.55, 0.1))
                    * Transform.scale(SIMD3<Float>(1.0, 1.1, 0.9))
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.5),
                material: transparent,
                transform: Transform.translation(SIMD3<Float>(-0.2, 0.48, 0.0))
                    * Transform.scale(SIMD3<Float>(0.88, 0.96, 0.88)),
                smoothUnionRadius: 0.08
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.5),
                material: metal,
                transform: Transform.translation(SIMD3<Float>(0.86, 0.42, 0.06))
                    * Transform.scale(SIMD3<Float>(0.84, 0.84, 0.84))
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.5),
                material: yellow,
                transform: Transform.translation(SIMD3<Float>(1.55, 0.26, 0.38))
                    * Transform.scale(SIMD3<Float>(0.52, 0.52, 0.52))
            ),
            SDFPrimitive(
                shape: .sphere(radius: 0.5),
                material: yellow,
                transform: Transform.translation(SIMD3<Float>(-1.85, 0.23, 0.62))
                    * Transform.scale(SIMD3<Float>(0.46, 0.46, 0.46))
            )
        ])
        let settings = DistanceVolumeBuildSettings(
            dimensions: SIMD3<Int>(48, 36, 32),
            boundsMin: SIMD3<Float>(-2.35, -0.02, -0.72),
            boundsMax: SIMD3<Float>(2.1, 1.2, 0.92)
        )

        return (scene, model, settings, red)
    }

    /// Creates a built-in dense distance-volume reference scene for mixed SDF rendering checks.
    public static func distanceVolumeReference() -> RenderScene {
        var contents = distanceVolumeReferenceContents()
        let volume = try! DistanceVolumeBuilder.build(
            model: contents.model,
            settings: contents.settings
        )
        contents.scene.add(volume: volume, material: contents.fallbackMaterial)

        return contents.scene
    }

    /// Creates a built-in sparse-brick distance-volume reference scene for mixed SDF rendering checks.
    public static func sparseDistanceVolumeReference() -> RenderScene {
        var contents = distanceVolumeReferenceContents()
        let volume = try! DistanceVolumeBuilder.buildSparse(
            model: contents.model,
            settings: SparseDistanceVolumeBuildSettings(
                denseSettings: contents.settings,
                brickSize: SIMD3<Int>(8, 8, 8),
                narrowBand: 0.28
            )
        )
        contents.scene.add(sparseVolume: volume, material: contents.fallbackMaterial)

        return contents.scene
    }

    private static func normalizedMeshTransform(mesh: Mesh, targetMaxExtent: Float) -> Transform {
        guard let bounds = meshBounds(mesh), targetMaxExtent > 0 else {
            return .identity
        }

        let minimum = bounds.minimum
        let maximum = bounds.maximum
        let center = (minimum + maximum) * 0.5
        let extent = maximum - minimum
        let maxExtent = max(extent.x, max(extent.y, extent.z))
        guard maxExtent > 1e-6 else {
            return .identity
        }

        let scale = targetMaxExtent / maxExtent
        let floorOffset = -(minimum.y - center.y) * scale
        return Transform.translation(SIMD3<Float>(0, floorOffset, 0))
            * Transform.scale(SIMD3<Float>(repeating: scale))
            * Transform.translation(-center)
    }

    private static func meshBounds(_ mesh: Mesh) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>)? {
        guard var minimum = mesh.vertices.first else {
            return nil
        }

        var maximum = minimum
        for vertex in mesh.vertices.dropFirst() {
            minimum = simd_min(minimum, vertex)
            maximum = simd_max(maximum, vertex)
        }
        return (minimum, maximum)
    }

    func compileForGPU() throws -> SceneCompilation {
        guard !materialSources.isEmpty else {
            throw DenrimRendererError.invalidScene("At least one material is required.")
        }

        let instanceAcceleration = try InstanceAccelerationBuilder().build(scene: self)

        let volumeResources = try LinearTriangleAccelerationBackend.gpuVolumes(scene: self)
        let volumeBrickResources = try LinearTriangleAccelerationBackend.gpuVolumeBricks(scene: self)
        let resolvedMaterials = materialSources.map { $0.resolvedMaterial() }

        return SceneCompilation(
            triangles: instanceAcceleration.materializedTriangles(),
            materials: resolvedMaterials.map { $0.gpuMaterial() },
            materialSemantics: materialSources.map(LinearTriangleAccelerationBackend.gpuMaterialSemanticDescriptor),
            volumes: volumeResources.descriptors,
            volumeSamples: volumeResources.samples,
            volumeAttributeDescriptors: volumeResources.attributeDescriptors,
            volumeAttributeSamples: volumeResources.attributeSamples,
            volumeBricks: volumeBrickResources.descriptors,
            volumeBrickSamples: volumeBrickResources.samples,
            volumeBrickAttributeDescriptors: volumeBrickResources.attributeDescriptors,
            volumeBrickAttributeSamples: volumeBrickResources.attributeSamples,
            instanceAcceleration: instanceAcceleration
        )
    }
}

struct SceneCompilation {
    var triangles: [GPUTriangle]
    var materials: [GPUMaterial]
    var materialSemantics: [GPUMaterialSemanticDescriptor]
    var volumes: [GPUVolumeDescriptor]
    var volumeSamples: [GPUVolumeSample]
    var volumeAttributeDescriptors: [GPUVolumeAttributeDescriptor]
    var volumeAttributeSamples: [SIMD4<Float>]
    var volumeBricks: [GPUVolumeBrickDescriptor]
    var volumeBrickSamples: [GPUVolumeSample]
    var volumeBrickAttributeDescriptors: [GPUVolumeAttributeDescriptor]
    var volumeBrickAttributeSamples: [SIMD4<Float>]
    var instanceAcceleration: InstanceAcceleration
}
