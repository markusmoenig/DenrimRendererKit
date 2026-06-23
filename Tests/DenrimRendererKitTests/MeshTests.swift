import Foundation
import XCTest
import simd
@testable import DenrimRendererKit

final class MeshTests: XCTestCase {
    func testBoxCreatesTwelveTriangles() {
        let mesh = Mesh.box(size: SIMD3<Float>(2, 4, 6))

        XCTAssertEqual(mesh.vertices.count, 8)
        XCTAssertEqual(mesh.indices.count, 36)

        let triangles = mesh.gpuTriangles(material: MaterialID(rawValue: 0))
        XCTAssertEqual(triangles.count, 12)
    }

    func testGPUTrianglesCarryIDs() {
        let triangles = Mesh.quad(
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>(1, -1, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(-1, 1, 0)
        ).gpuTriangles(
            material: MaterialID(rawValue: 3),
            objectID: 9
        )

        XCTAssertEqual(triangles[0].materialID, 3)
        XCTAssertEqual(triangles[0].objectID, 9)
        XCTAssertEqual(triangles[0].primitiveID, 0)
        XCTAssertEqual(triangles[1].primitiveID, 1)
    }

    func testGPUTrianglesPreserveImportedVertexNormals() {
        let mesh = Mesh(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            indices: [0, 1, 2],
            normals: [
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(0, 0, 1)
            ]
        )

        let triangle = mesh.gpuTriangles(material: MaterialID(rawValue: 0))[0]

        XCTAssertEqual(triangle.n0.xyz, SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(triangle.n1.xyz, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(triangle.n2.xyz, SIMD3<Float>(0, 0, 1))
    }

    func testBoxBoundsMatchInputCorners() {
        let mesh = Mesh.box(
            minimum: SIMD3<Float>(-1, -2, -3),
            maximum: SIMD3<Float>(4, 5, 6)
        )

        XCTAssertEqual(mesh.vertices.map(\.x).min(), -1)
        XCTAssertEqual(mesh.vertices.map(\.x).max(), 4)
        XCTAssertEqual(mesh.vertices.map(\.y).min(), -2)
        XCTAssertEqual(mesh.vertices.map(\.y).max(), 5)
        XCTAssertEqual(mesh.vertices.map(\.z).min(), -3)
        XCTAssertEqual(mesh.vertices.map(\.z).max(), 6)
    }

    func testLoadsTriangulatedOBJMesh() throws {
        let url = try temporaryMeshURL("TriangulatedQuad.obj")
        let source = """
        # quad with texture coordinates and one normal
        v -1 0 0
        v 1 0 0
        v 1 1 0
        v -1 1 0
        vt 0 0
        vt 1 0
        vt 1 1
        vt 0 1
        vn 0 0 1
        f 1/1/1 2/2/1 3/3/1 4/4/1
        """
        try source.write(to: url, atomically: true, encoding: .utf8)

        let mesh = try Mesh(contentsOf: url)

        XCTAssertEqual(mesh.vertices.count, 4)
        XCTAssertEqual(mesh.indices, [0, 1, 2, 0, 2, 3])
        XCTAssertEqual(mesh.texcoords[2], SIMD2<Float>(1, 1))
        XCTAssertEqual(mesh.normals[0], SIMD3<Float>(0, 0, 1))
    }

    func testOBJLoaderSupportsRelativeFaceIndices() throws {
        let url = try temporaryMeshURL("RelativeTriangle.obj")
        let source = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f -3 -2 -1
        """
        try source.write(to: url, atomically: true, encoding: .utf8)

        let mesh = try Mesh(contentsOf: url)

        XCTAssertEqual(mesh.vertices.count, 3)
        XCTAssertEqual(mesh.indices, [0, 1, 2])
        XCTAssertEqual(mesh.vertices[2], SIMD3<Float>(0, 1, 0))
    }

    func testOBJLoaderParsesScientificNotationFloats() throws {
        let url = try temporaryMeshURL("ScientificNotationTriangle.obj")
        let source = """
        v -1.0e-1 0 0
        v 1.25E+0 0 0
        v 0 2.5e-1 0
        vt 0 0
        vt 1.0e0 0
        vt 0 1
        f 1/1 2/2 3/3
        """
        try source.write(to: url, atomically: true, encoding: .utf8)

        let mesh = try Mesh(contentsOf: url)

        XCTAssertEqual(mesh.indices, [0, 1, 2])
        XCTAssertEqual(mesh.vertices[0].x, -0.1, accuracy: 0.0001)
        XCTAssertEqual(mesh.vertices[1].x, 1.25, accuracy: 0.0001)
        XCTAssertEqual(mesh.vertices[2].y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(mesh.texcoords[1].x, 1, accuracy: 0.0001)
    }

    func testLoadsASCIIPLYMesh() throws {
        let url = try temporaryMeshURL("AsciiQuad.ply")
        let source = """
        ply
        format ascii 1.0
        element vertex 4
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        property float s
        property float t
        element face 1
        property list uchar int vertex_indices
        end_header
        -1 0 0 0 0 1 0 0
        1 0 0 0 0 1 1 0
        1 1 0 0 0 1 1 1
        -1 1 0 0 0 1 0 1
        4 0 1 2 3
        """
        try source.write(to: url, atomically: true, encoding: .utf8)

        let mesh = try Mesh(contentsOf: url)

        XCTAssertEqual(mesh.vertices.count, 4)
        XCTAssertEqual(mesh.indices, [0, 1, 2, 0, 2, 3])
        XCTAssertEqual(mesh.normals[0], SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(mesh.texcoords[2], SIMD2<Float>(1, 1))
    }

    func testLoadsBinaryLittleEndianPLYMesh() throws {
        let url = try temporaryMeshURL("BinaryTriangle.ply")
        let header = "ply\n"
            + "format binary_little_endian 1.0\n"
            + "element vertex 3\n"
            + "property float x\n"
            + "property float y\n"
            + "property float z\n"
            + "element face 1\n"
            + "property list uchar int vertex_indices\n"
            + "end_header\n"
        var data = Data(header.utf8)
        appendLittleEndianFloat(0, to: &data)
        appendLittleEndianFloat(0, to: &data)
        appendLittleEndianFloat(0, to: &data)
        appendLittleEndianFloat(1, to: &data)
        appendLittleEndianFloat(0, to: &data)
        appendLittleEndianFloat(0, to: &data)
        appendLittleEndianFloat(0, to: &data)
        appendLittleEndianFloat(1, to: &data)
        appendLittleEndianFloat(0, to: &data)
        data.append(3)
        appendLittleEndianInt32(0, to: &data)
        appendLittleEndianInt32(1, to: &data)
        appendLittleEndianInt32(2, to: &data)
        try data.write(to: url)

        let mesh = try Mesh(contentsOf: url)

        XCTAssertEqual(mesh.vertices.count, 3)
        XCTAssertEqual(mesh.indices, [0, 1, 2])
        XCTAssertEqual(mesh.vertices[1], SIMD3<Float>(1, 0, 0))
    }

    func testMeshLoaderRejectsUnsupportedFormats() {
        let url = URL(fileURLWithPath: "/tmp/dragon.glb")

        XCTAssertThrowsError(try Mesh(contentsOf: url)) { error in
            XCTAssertEqual(error as? MeshLoadingError, .unsupportedFormat("glb"))
        }
    }

    private func temporaryMeshURL(_ name: String) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenrimRendererKit-MeshImporter", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }

    private func appendLittleEndianFloat(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    private func appendLittleEndianInt32(_ value: Int32, to data: inout Data) {
        var bits = value.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
}
