import Foundation
import simd

/// A renderable scene containing camera, materials, and mesh instances.
public struct RenderScene: Sendable {
    /// Scene camera.
    public var camera: Camera

    /// Materials available to scene geometry.
    public private(set) var materials: [Material]

    /// Mesh instances in the scene.
    public private(set) var meshInstances: [MeshInstance]

    /// Creates an empty render scene.
    public init(
        camera: Camera = Camera(
            origin: SIMD3<Float>(0, 1, 4),
            target: SIMD3<Float>(0, 1, 0)
        )
    ) {
        self.camera = camera
        self.materials = []
        self.meshInstances = []
    }

    /// Adds a material and returns its scene-local identifier.
    @discardableResult
    public mutating func addMaterial(_ material: Material) -> MaterialID {
        let id = MaterialID(rawValue: UInt32(materials.count))
        materials.append(material)
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
        let green = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.18, 0.72, 0.35), roughness: 0.45))
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
        let matteClay = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.82, 0.42, 0.26), roughness: 0.88, specular: 0.35))
        let satinPlastic = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.18, 0.45, 0.95),
            roughness: 0.32,
            specular: 0.75,
            specularColor: SIMD3<Float>(0.9, 0.96, 1),
            indexOfRefraction: 1.48
        ))
        let brushedMetal = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.86, 0.72, 0.46), roughness: 0.42, metallic: 1))
        let polishedMetal = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.72, 0.78, 0.82), roughness: 0.12, metallic: 1))
        let coated = scene.addMaterial(Material(
            baseColor: SIMD3<Float>(0.22, 0.72, 0.38),
            roughness: 0.46,
            specular: 0.85,
            indexOfRefraction: 1.52,
            clearcoat: 0.55,
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
            opacity: 0.45
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
        guard !materials.isEmpty else {
            throw DenrimRendererError.invalidScene("At least one material is required.")
        }

        let instanceAcceleration = try InstanceAccelerationBuilder().build(scene: self)

        return SceneCompilation(
            triangles: instanceAcceleration.materializedTriangles(),
            materials: materials.map { $0.gpuMaterial() },
            instanceAcceleration: instanceAcceleration
        )
    }
}

struct SceneCompilation {
    var triangles: [GPUTriangle]
    var materials: [GPUMaterial]
    var instanceAcceleration: InstanceAcceleration
}
