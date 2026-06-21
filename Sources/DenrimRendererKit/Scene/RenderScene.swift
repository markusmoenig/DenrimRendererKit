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

    /// Creates the built-in material reference scene for diffuse, metallic, roughness, and emissive baseline checks.
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
        let violet = scene.addMaterial(Material(baseColor: SIMD3<Float>(0.62, 0.36, 0.95), roughness: 0.35, metallic: 0.55))
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

    func compileForGPU() throws -> SceneCompilation {
        guard !materials.isEmpty else {
            throw DenrimRendererError.invalidScene("At least one material is required.")
        }

        let instanceAcceleration = try InstanceAccelerationBuilder().build(scene: self)

        return SceneCompilation(
            triangles: instanceAcceleration.materializedTriangles(),
            materials: materials.map(\.gpuMaterial),
            instanceAcceleration: instanceAcceleration
        )
    }
}

struct SceneCompilation {
    var triangles: [GPUTriangle]
    var materials: [GPUMaterial]
    var instanceAcceleration: InstanceAcceleration
}
