import XCTest
@testable import DenrimRendererKit

final class SceneScriptTests: XCTestCase {
    func testSceneScriptBuildsRenderableScene() throws {
        let source = """
        # Small scripted material test scene
        camera 0 1.4 4.0 0 0.6 0 42
        material floor 0.7 0.7 0.65
        material red 0.9 0.2 0.1
        material light 1 1 1 1 0.9 0.7 8
        quad floor -2 0 2 2 0 2 2 0 -2 -2 0 -2
        quad light -0.4 2 -0.4 0.4 2 -0.4 0.4 2 0.4 -0.4 2 0.4
        box red 0 0.3 0 0.6 0.6 0.6 0.4
        """

        let scene = try SceneScript.parse(source)
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 3)
        XCTAssertEqual(scene.meshInstances.count, 3)
        XCTAssertEqual(compiled.triangles.count, 16)
        XCTAssertEqual(scene.camera.verticalFieldOfViewDegrees, 42)
    }

    func testSceneScriptIgnoresCommentsAndBlankLines() throws {
        let source = """

        # comment only
        camera 0 0 1 0 0 0 45
        material white 1 1 1 # inline comment
        quad white -1 0 0 1 0 0 1 1 0 -1 1 0
        """

        let scene = try SceneScript.parse(source)

        XCTAssertEqual(scene.materials.count, 1)
        XCTAssertEqual(scene.meshInstances.count, 1)
    }

    func testSceneScriptParsesMaterialParameters() throws {
        let source = """
        material compact 0.8 0.7 0.5 roughness 0.22 metallic 1
        material brushed 0.8 0.7 0.5 roughness 0.22 metallic 1 opacity 0.9
        material glow 1 1 1 emission 1 0.8 0.4 6
        """

        let scene = try SceneScript.parse(source)

        XCTAssertEqual(scene.materials.count, 3)
        XCTAssertEqual(scene.materials[0].roughness, 0.22, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[0].metallic, 1, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[1].opacity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(scene.materials[2].emissionStrength, 6, accuracy: 0.0001)
    }

    func testSceneScriptIncludesReusableFragments() throws {
        let source = """
        camera 0 1 4 0 0.5 0 40
        include commonMaterials
        include floor
        box red 0 0.3 0 0.6 0.6 0.6
        """
        let fragments = [
            "commonMaterials": """
            material floor 0.6 0.6 0.55
            material red 0.9 0.15 0.1 roughness 0.4
            """,
            "floor": "quad floor -2 0 2 2 0 2 2 0 -2 -2 0 -2"
        ]

        let scene = try SceneScript.parse(source) { name in
            try XCTUnwrap(fragments[name])
        }
        let compiled = try scene.compileForGPU()

        XCTAssertEqual(scene.materials.count, 2)
        XCTAssertEqual(scene.meshInstances.count, 2)
        XCTAssertEqual(compiled.triangles.count, 14)
    }

    func testSceneScriptReportsMissingIncludeResolver() {
        XCTAssertThrowsError(try SceneScript.parse("include common")) { error in
            XCTAssertEqual(error as? SceneScriptError, .includeResolverMissing("common", line: 1))
        }
    }

    func testSceneScriptReportsIncludeCycles() {
        let fragments = [
            "a": "include b",
            "b": "include a"
        ]

        XCTAssertThrowsError(try SceneScript.parse("include a", includeResolver: { name in
            try XCTUnwrap(fragments[name])
        })) { error in
            XCTAssertEqual(error as? SceneScriptError, .includeCycle("a", line: 1))
        }
    }

    func testSceneScriptReportsUnknownMaterial() {
        let source = """
        material white 1 1 1
        box missing 0 0 0 1 1 1
        """

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .unknownMaterial("missing", line: 2))
        }
    }

    func testSceneScriptReportsBadNumbers() {
        let source = "camera 0 nope 1 0 0 0 45"

        XCTAssertThrowsError(try SceneScript.parse(source)) { error in
            XCTAssertEqual(error as? SceneScriptError, .invalidNumber("nope", line: 1))
        }
    }
}
