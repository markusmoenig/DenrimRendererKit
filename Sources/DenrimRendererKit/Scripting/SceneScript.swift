import Foundation
import simd

/// Errors produced while parsing a scene script.
public enum SceneScriptError: Error, LocalizedError, Equatable {
    case unknownCommand(String, line: Int)
    case invalidArgumentCount(String, line: Int)
    case invalidNumber(String, line: Int)
    case unknownMaterial(String, line: Int)
    case includeResolverMissing(String, line: Int)
    case includeCycle(String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .unknownCommand(let command, let line):
            "Unknown scene script command '\(command)' on line \(line)."
        case .invalidArgumentCount(let command, let line):
            "Invalid argument count for scene script command '\(command)' on line \(line)."
        case .invalidNumber(let value, let line):
            "Invalid numeric value '\(value)' on line \(line)."
        case .unknownMaterial(let name, let line):
            "Unknown material '\(name)' on line \(line)."
        case .includeResolverMissing(let name, let line):
            "Scene script include '\(name)' on line \(line) requires an include resolver."
        case .includeCycle(let name, let line):
            "Scene script include cycle for '\(name)' on line \(line)."
        }
    }
}

/// Parser for the small DenrimRendererKit scene scripting language.
public enum SceneScript {
    /// Resolves an included scene script fragment by name.
    public typealias IncludeResolver = (String) throws -> String

    /// Parses a line-based scene script into a render scene.
    public static func parse(
        _ source: String,
        includeResolver: IncludeResolver? = nil
    ) throws -> RenderScene {
        var scene = RenderScene()
        var materials: [String: MaterialID] = [:]
        var includeStack: [String] = []

        try parseLines(
            source,
            into: &scene,
            materials: &materials,
            includeResolver: includeResolver,
            includeStack: &includeStack
        )

        return scene
    }

    private static func parseLines(
        _ source: String,
        into scene: inout RenderScene,
        materials: inout [String: MaterialID],
        includeResolver: IncludeResolver?,
        includeStack: inout [String]
    ) throws {
        for (lineIndex, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = tokens.first?.lowercased() else {
                continue
            }

            switch command {
            case "include":
                let includeName = try parseInclude(tokens, line: lineNumber)
                guard let includeResolver else {
                    throw SceneScriptError.includeResolverMissing(includeName, line: lineNumber)
                }
                if includeStack.contains(includeName) {
                    throw SceneScriptError.includeCycle(includeName, line: lineNumber)
                }

                includeStack.append(includeName)
                let includedSource = try includeResolver(includeName)
                try parseLines(
                    includedSource,
                    into: &scene,
                    materials: &materials,
                    includeResolver: includeResolver,
                    includeStack: &includeStack
                )
                includeStack.removeLast()
            case "camera":
                scene.camera = try parseCamera(tokens, line: lineNumber)
            case "material":
                let parsed = try parseMaterial(tokens, line: lineNumber)
                materials[parsed.name] = scene.addMaterial(parsed.material)
            case "quad":
                let parsed = try parseQuad(tokens, line: lineNumber, materials: materials)
                scene.add(mesh: parsed.mesh, material: parsed.material)
            case "box":
                let parsed = try parseBox(tokens, line: lineNumber, materials: materials)
                scene.add(mesh: parsed.mesh, material: parsed.material, transform: parsed.transform)
            default:
                throw SceneScriptError.unknownCommand(command, line: lineNumber)
            }
        }
    }

    private static func stripComment(_ line: String) -> String {
        guard let commentStart = line.firstIndex(of: "#") else {
            return line
        }
        return String(line[..<commentStart])
    }

    private static func parseInclude(_ tokens: [String], line: Int) throws -> String {
        guard tokens.count == 2 else {
            throw SceneScriptError.invalidArgumentCount("include", line: line)
        }
        return tokens[1]
    }

    private static func parseCamera(_ tokens: [String], line: Int) throws -> Camera {
        guard tokens.count == 8 else {
            throw SceneScriptError.invalidArgumentCount("camera", line: line)
        }

        let values = try floats(tokens.dropFirst(), line: line)
        return Camera(
            origin: SIMD3<Float>(values[0], values[1], values[2]),
            target: SIMD3<Float>(values[3], values[4], values[5]),
            verticalFieldOfViewDegrees: values[6]
        )
    }

    private static func parseMaterial(_ tokens: [String], line: Int) throws -> (name: String, material: Material) {
        guard tokens.count >= 5 else {
            throw SceneScriptError.invalidArgumentCount("material", line: line)
        }

        let name = tokens[1]
        let base = try floats(tokens[2..<5], line: line)

        if tokens.count == 9 && canParseFloats(tokens[5..<9]) {
            let emission = try floats(tokens[5..<9], line: line)
            return (
                name,
                Material(
                    baseColor: SIMD3<Float>(base[0], base[1], base[2]),
                    emission: SIMD3<Float>(emission[0], emission[1], emission[2]),
                    emissionStrength: emission[3]
                )
            )
        }

        var material = Material(baseColor: SIMD3<Float>(base[0], base[1], base[2]))
        var index = 5

        while index < tokens.count {
            let keyword = tokens[index].lowercased()
            switch keyword {
            case "emission":
                guard index + 4 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 4)], line: line)
                material.emission = SIMD3<Float>(values[0], values[1], values[2])
                material.emissionStrength = values[3]
                index += 5
            case "roughness":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.roughness = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "metallic":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.metallic = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "opacity":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.opacity = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            default:
                throw SceneScriptError.invalidArgumentCount("material", line: line)
            }
        }

        return (
            name,
            material
        )
    }

    private static func parseQuad(
        _ tokens: [String],
        line: Int,
        materials: [String: MaterialID]
    ) throws -> (mesh: Mesh, material: MaterialID) {
        guard tokens.count == 14 else {
            throw SceneScriptError.invalidArgumentCount("quad", line: line)
        }
        let material = try material(named: tokens[1], line: line, materials: materials)
        let values = try floats(tokens[2..<14], line: line)

        return (
            Mesh.quad(
                SIMD3<Float>(values[0], values[1], values[2]),
                SIMD3<Float>(values[3], values[4], values[5]),
                SIMD3<Float>(values[6], values[7], values[8]),
                SIMD3<Float>(values[9], values[10], values[11])
            ),
            material
        )
    }

    private static func parseBox(
        _ tokens: [String],
        line: Int,
        materials: [String: MaterialID]
    ) throws -> (mesh: Mesh, material: MaterialID, transform: Transform) {
        guard tokens.count == 8 || tokens.count == 9 else {
            throw SceneScriptError.invalidArgumentCount("box", line: line)
        }
        let material = try material(named: tokens[1], line: line, materials: materials)
        let values = try floats(tokens[2..<tokens.count], line: line)
        let mesh = Mesh.box(size: SIMD3<Float>(values[3], values[4], values[5]))
        var transform = Transform.translation(SIMD3<Float>(values[0], values[1], values[2]))
        if values.count == 7 {
            transform = transform * Transform.rotationY(radians: values[6])
        }

        return (mesh, material, transform)
    }

    private static func material(
        named name: String,
        line: Int,
        materials: [String: MaterialID]
    ) throws -> MaterialID {
        guard let material = materials[name] else {
            throw SceneScriptError.unknownMaterial(name, line: line)
        }
        return material
    }

    private static func floats<S: Sequence>(_ tokens: S, line: Int) throws -> [Float] where S.Element == String {
        try tokens.map { token in
            guard let value = Float(token) else {
                throw SceneScriptError.invalidNumber(token, line: line)
            }
            return value
        }
    }

    private static func canParseFloats<S: Sequence>(_ tokens: S) -> Bool where S.Element == String {
        tokens.allSatisfy { Float($0) != nil }
    }
}
