import Foundation
import simd

/// Errors produced while parsing a scene script.
public enum SceneScriptError: Error, LocalizedError, Equatable {
    case unknownCommand(String, line: Int)
    case invalidArgumentCount(String, line: Int)
    case invalidNumber(String, line: Int)
    case unknownMaterial(String, line: Int)
    case unknownMaterialPreset(String, line: Int)
    case unknownTexture(String, line: Int)
    case unknownMesh(String, line: Int)
    case environmentLoadFailed(String, line: Int)
    case textureLoadFailed(String, line: Int)
    case meshLoadFailed(String, line: Int)
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
        case .unknownMaterialPreset(let name, let line):
            "Unknown built-in material preset '\(name)' on line \(line)."
        case .unknownTexture(let name, let line):
            "Unknown texture '\(name)' on line \(line)."
        case .unknownMesh(let name, let line):
            "Unknown mesh '\(name)' on line \(line)."
        case .environmentLoadFailed(let path, let line):
            "Could not load environment image '\(path)' on line \(line)."
        case .textureLoadFailed(let path, let line):
            "Could not load texture image '\(path)' on line \(line)."
        case .meshLoadFailed(let path, let line):
            "Could not load mesh '\(path)' on line \(line)."
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
    ///
    /// Pass `baseURL` to resolve relative image texture paths used by `texture image` commands.
    public static func parse(
        _ source: String,
        baseURL: URL? = nil,
        assetCache: SceneAssetCache? = nil,
        includeResolver: IncludeResolver? = nil
    ) throws -> RenderScene {
        var scene = RenderScene()
        var materials: [String: MaterialID] = [:]
        var textures: [String: Texture2D] = [:]
        var meshes: [String: Mesh] = [:]
        var includeStack: [String] = []

        try parseLines(
            source,
            into: &scene,
            materials: &materials,
            textures: &textures,
            meshes: &meshes,
            baseURL: baseURL,
            assetCache: assetCache,
            includeResolver: includeResolver,
            includeStack: &includeStack
        )

        return scene
    }

    /// Parses a scene script file, resolving relative assets and includes beside that file.
    public static func parse(contentsOf url: URL, assetCache: SceneAssetCache? = nil) throws -> RenderScene {
        let source = try String(contentsOf: url, encoding: .utf8)
        let baseURL = url.deletingLastPathComponent()
        return try parse(
            source,
            baseURL: baseURL,
            assetCache: assetCache,
            includeResolver: { includeName in
                try String(
                    contentsOf: assetURL(path: includeName, baseURL: baseURL),
                    encoding: .utf8
                )
            }
        )
    }

    private static func parseLines(
        _ source: String,
        into scene: inout RenderScene,
        materials: inout [String: MaterialID],
        textures: inout [String: Texture2D],
        meshes: inout [String: Mesh],
        baseURL: URL?,
        assetCache: SceneAssetCache?,
        includeResolver: IncludeResolver?,
        includeStack: inout [String]
    ) throws {
        for (lineIndex, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let tokens = tokenize(line)
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
                    textures: &textures,
                    meshes: &meshes,
                    baseURL: baseURL,
                    assetCache: assetCache,
                    includeResolver: includeResolver,
                    includeStack: &includeStack
                )
                includeStack.removeLast()
            case "camera":
                scene.camera = try parseCamera(tokens, line: lineNumber)
            case "environment":
                scene.environment = try parseEnvironment(
                    tokens,
                    line: lineNumber,
                    baseURL: baseURL,
                    assetCache: assetCache
                )
            case "texture":
                let parsed = try parseTexture(
                    tokens,
                    line: lineNumber,
                    baseURL: baseURL,
                    textures: textures,
                    assetCache: assetCache
                )
                textures[parsed.name] = parsed.texture
            case "mesh":
                let parsed = try parseMeshAsset(
                    tokens,
                    line: lineNumber,
                    baseURL: baseURL,
                    assetCache: assetCache
                )
                meshes[parsed.name] = parsed.mesh
            case "material":
                let parsed = try parseMaterial(tokens, line: lineNumber, textures: textures)
                materials[parsed.name] = scene.addMaterial(parsed.material)
            case "quad":
                let parsed = try parseQuad(tokens, line: lineNumber, materials: materials)
                scene.add(mesh: parsed.mesh, material: parsed.material)
            case "box":
                let parsed = try parseBox(tokens, line: lineNumber, materials: materials)
                scene.add(mesh: parsed.mesh, material: parsed.material, transform: parsed.transform)
            case "instance":
                let parsed = try parseInstance(tokens, line: lineNumber, materials: materials, meshes: meshes)
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

    private static func tokenize(_ line: String) -> [String] {
        line
            .replacingOccurrences(of: "(", with: " ( ")
            .replacingOccurrences(of: ")", with: " ) ")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func parseInclude(_ tokens: [String], line: Int) throws -> String {
        guard tokens.count == 2 else {
            throw SceneScriptError.invalidArgumentCount("include", line: line)
        }
        return tokens[1]
    }

    private static func parseCamera(_ tokens: [String], line: Int) throws -> Camera {
        if tokens.count == 8 {
            let values = try floats(tokens.dropFirst(), line: line)
            return Camera(
                origin: SIMD3<Float>(values[0], values[1], values[2]),
                target: SIMD3<Float>(values[3], values[4], values[5]),
                verticalFieldOfViewDegrees: values[6]
            )
        }

        var origin: SIMD3<Float>?
        var target: SIMD3<Float>?
        var fov: Float?
        var index = 1

        while index < tokens.count {
            let keyword = tokens[index].lowercased()
            switch keyword {
            case "origin", "position", "eye":
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                origin = parsed.value
                index = parsed.nextIndex
            case "target", "lookat", "look":
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                target = parsed.value
                index = parsed.nextIndex
            case "fov", "fieldofview":
                let parsed = try parseNamedFloat(tokens, index: index, line: line)
                fov = parsed.value
                index = parsed.nextIndex
            default:
                throw SceneScriptError.invalidArgumentCount("camera", line: line)
            }
        }

        guard let origin, let target, let fov else {
            throw SceneScriptError.invalidArgumentCount("camera", line: line)
        }

        return Camera(
            origin: origin,
            target: target,
            verticalFieldOfViewDegrees: fov
        )
    }

    private static func parseTexture(
        _ tokens: [String],
        line: Int,
        baseURL: URL?,
        textures: [String: Texture2D],
        assetCache: SceneAssetCache?
    ) throws -> (name: String, texture: Texture2D) {
        guard tokens.count >= 4 else {
            throw SceneScriptError.invalidArgumentCount("texture", line: line)
        }

        let name = tokens[1]
        let kind = tokens[2].lowercased()
        switch kind {
        case "solid":
            guard tokens.count == 7 || tokens.count == 8 else {
                throw SceneScriptError.invalidArgumentCount("texture", line: line)
            }
            let color = try rgba(tokens[3..<7], line: line)
            let samplingMode = try textureSamplingMode(tokens.dropFirst(7), line: line)
            return (name, .solid(color, samplingMode: samplingMode))
        case "checker":
            guard tokens.count == 11 || tokens.count == 12 else {
                throw SceneScriptError.invalidArgumentCount("texture", line: line)
            }
            let a = try rgba(tokens[3..<7], line: line)
            let b = try rgba(tokens[7..<11], line: line)
            let samplingMode = try textureSamplingMode(tokens.dropFirst(11), line: line)
            return (name, .checker(a, b, samplingMode: samplingMode))
        case "image":
            guard tokens.count >= 4 else {
                throw SceneScriptError.invalidArgumentCount("texture", line: line)
            }
            let options = try imageTextureOptions(tokens.dropFirst(4), line: line)
            let url = assetURL(path: tokens[3], baseURL: baseURL)
            do {
                return (
                    name,
                    try assetCache?.texture(
                        contentsOf: url,
                        colorEncoding: options.colorEncoding,
                        samplingMode: options.samplingMode
                    ) ?? Texture2D(
                            contentsOf: url,
                            colorEncoding: options.colorEncoding,
                            samplingMode: options.samplingMode
                        )
                )
            } catch {
                throw SceneScriptError.textureLoadFailed(tokens[3], line: line)
            }
        default:
            if kind == "normalfrom" || kind == "normalfromtexture" {
                guard tokens.count == 4 || tokens.count == 6 else {
                    throw SceneScriptError.invalidArgumentCount("texture", line: line)
                }

                var strength: Float = 1
                if tokens.count == 6 {
                    guard tokens[4].lowercased() == "strength" else {
                        throw SceneScriptError.invalidArgumentCount("texture", line: line)
                    }
                    strength = try floats([tokens[5]], line: line)[0]
                }

                let sourceTexture = try texture(named: tokens[3], line: line, textures: textures)
                return (name, sourceTexture.derivedNormalMap(strength: strength))
            }

            throw SceneScriptError.invalidArgumentCount("texture", line: line)
        }
    }

    private static func parseEnvironment(
        _ tokens: [String],
        line: Int,
        baseURL: URL?,
        assetCache: SceneAssetCache?
    ) throws -> Environment {
        guard tokens.count >= 2 else {
            throw SceneScriptError.invalidArgumentCount("environment", line: line)
        }

        let kind = tokens[1].lowercased()
        if kind == "sky" || kind == "default" {
            guard tokens.count == 2 else {
                throw SceneScriptError.invalidArgumentCount("environment", line: line)
            }
            return .sky
        }

        guard kind == "image" || kind == "hdri" || kind == "hdr" else {
            throw SceneScriptError.invalidArgumentCount("environment", line: line)
        }
        guard tokens.count >= 3 else {
            throw SceneScriptError.invalidArgumentCount("environment", line: line)
        }

        var intensity: Float = 1
        var rotationY: Float = 0
        var maxRadiance: Float = 16
        var index = 3
        while index < tokens.count {
            let keyword = tokens[index].lowercased()
            switch keyword {
            case "intensity", "strength", "exposure":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("environment", line: line)
                }
                intensity = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "rotationy", "rotatey", "yaw":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("environment", line: line)
                }
                rotationY = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "maxradiance", "radianceclamp", "clamp":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("environment", line: line)
                }
                maxRadiance = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            default:
                throw SceneScriptError.invalidArgumentCount("environment", line: line)
            }
        }

        let url = assetURL(path: tokens[2], baseURL: baseURL)
        do {
            let texture = try assetCache?.texture(
                contentsOf: url,
                colorEncoding: .linear,
                samplingMode: .linear
            ) ?? Texture2D(
                contentsOf: url,
                colorEncoding: .linear,
                samplingMode: .linear
            )
            return Environment(
                texture: texture,
                intensity: intensity,
                rotationY: rotationY,
                maxRadiance: maxRadiance
            )
        } catch {
            throw SceneScriptError.environmentLoadFailed(tokens[2], line: line)
        }
    }

    private static func parseMeshAsset(
        _ tokens: [String],
        line: Int,
        baseURL: URL?,
        assetCache: SceneAssetCache?
    ) throws -> (name: String, mesh: Mesh) {
        guard tokens.count == 3 || tokens.count == 4 else {
            throw SceneScriptError.invalidArgumentCount("mesh", line: line)
        }

        var flipsV = false
        if tokens.count == 4 {
            guard tokens[3].lowercased() == "flipv" else {
                throw SceneScriptError.invalidArgumentCount("mesh", line: line)
            }
            flipsV = true
        }

        let url = assetURL(path: tokens[2], baseURL: baseURL)
        do {
            return (
                tokens[1],
                try assetCache?.mesh(contentsOf: url, flipsV: flipsV)
                    ?? loadMesh(contentsOf: url, flipsV: flipsV)
            )
        } catch {
            throw SceneScriptError.meshLoadFailed(tokens[2], line: line)
        }
    }

    private static func loadMesh(contentsOf url: URL, flipsV: Bool) throws -> Mesh {
        var mesh = try Mesh(contentsOf: url)
        if flipsV {
            mesh.flipTexcoordV()
        }
        return mesh
    }

    private static func parseMaterial(
        _ tokens: [String],
        line: Int,
        textures: [String: Texture2D]
    ) throws -> (name: String, material: Material) {
        guard tokens.count >= 3 else {
            throw SceneScriptError.invalidArgumentCount("material", line: line)
        }

        let name = tokens[1]
        let lowercasedSource = tokens[2].lowercased()
        let startingMaterial: Material
        let startingIndex: Int
        if lowercasedSource == "preset" || lowercasedSource == "builtin" || lowercasedSource == "built-in" {
            guard tokens.count >= 4 else {
                throw SceneScriptError.invalidArgumentCount("material", line: line)
            }
            guard let presetMaterial = BuiltInMaterialLibrary.material(named: tokens[3]) else {
                throw SceneScriptError.unknownMaterialPreset(tokens[3], line: line)
            }
            startingMaterial = presetMaterial
            startingIndex = 4
        } else {
            guard tokens.count >= 5 else {
                throw SceneScriptError.invalidArgumentCount("material", line: line)
            }
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
            startingMaterial = Material(baseColor: SIMD3<Float>(base[0], base[1], base[2]))
            startingIndex = 5
        }

        var material = startingMaterial
        var index = startingIndex

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
            case "specular":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.specular = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "specularcolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.specularColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "ior", "indexofrefraction":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.indexOfRefraction = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "anisotropy", "specularanisotropy":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.specularAnisotropy = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "clearcoat":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.clearcoat = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "clearcoatcolor", "clearcoattint":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.clearcoatColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "clearcoatattenuationcolor", "clearcoatabsorptioncolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.clearcoatAttenuationColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "clearcoatthickness", "clearcoatdepth":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.clearcoatThickness = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "clearcoatroughness":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.clearcoatRoughness = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "clearcoatior", "clearcoatindexofrefraction":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.clearcoatIndexOfRefraction = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "thinfilm", "iridescence":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.thinFilm = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "thinfilmthickness", "thinfilmthicknessnm", "iridescencethickness":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.thinFilmThicknessNanometers = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "thinfilmior", "thinfilmindexofrefraction", "iridescenceior":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.thinFilmIndexOfRefraction = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "sheen", "fuzz":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.sheen = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "sheencolor", "fuzzcolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.sheenColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "sheenroughness", "fuzzroughness":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.sheenRoughness = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "subsurface", "subsurfaceweight", "sss":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.subsurface = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "subsurfacecolor", "subsurfacetint", "ssscolor", "scatteringcolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.subsurfaceColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "subsurfaceradius", "subsurfaceradiuscolor", "sssradius", "scatteringradius":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.subsurfaceRadius = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "subsurfacescale", "sssscale", "scatteringscale":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.subsurfaceScale = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "subsurfaceanisotropy", "sssanisotropy", "scatteringanisotropy":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.subsurfaceAnisotropy = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "opacity":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.opacity = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "transmission", "spectrans", "spectraltransmission":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.transmission = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "transmissioncolor", "transmissiontint", "spectranscolor", "spectraltransmissioncolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.transmissionColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "transmissionroughness", "spectransroughness", "spectraltransmissionroughness":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.transmissionRoughness = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "transmissionior", "transmissionindexofrefraction":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.transmissionIndexOfRefraction = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "transmissionabsorptioncolor", "absorptioncolor", "attenuationcolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.transmissionAbsorptionColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "transmissionabsorptiondistance", "absorptiondistance", "attenuationdistance":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.transmissionAbsorptionDistance = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "thinwalled", "thinwall", "thin":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.thinWalled = try floats(tokens[(index + 1)...(index + 1)], line: line)[0] > 0
                index += 2
            case "volumescattering", "volumescatter", "mediumscattering", "mediumscatter":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.volumeScattering = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "volumescatteringcolor", "volumescattercolor", "mediumscatteringcolor", "mediumscattercolor":
                guard index + 3 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
                material.volumeScatteringColor = SIMD3<Float>(values[0], values[1], values[2])
                index += 4
            case "volumescatteringdistance", "volumescatterdistance", "mediumscatteringdistance", "mediumscatterdistance":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.volumeScatteringDistance = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "volumeanisotropy", "mediumanisotropy":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.volumeAnisotropy = try floats(tokens[(index + 1)...(index + 1)], line: line)[0]
                index += 2
            case "basecolortexture":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.baseColorTexture = try texture(named: tokens[index + 1], line: line, textures: textures)
                index += 2
            case "normalmap":
                guard index + 1 < tokens.count else {
                    throw SceneScriptError.invalidArgumentCount("material", line: line)
                }
                material.normalMap = try texture(named: tokens[index + 1], line: line, textures: textures)
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
        if tokens.count == 14 {
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

        guard tokens.count >= 2 else {
            throw SceneScriptError.invalidArgumentCount("quad", line: line)
        }

        let materialParse = try parseOptionalNamedString(
            tokens,
            index: 1,
            keyword: "material",
            defaultConsumesBareValue: true,
            line: line
        )
        let material = try material(named: materialParse.value, line: line, materials: materials)
        var corners: [String: SIMD3<Float>] = [:]
        var texcoords: [String: SIMD2<Float>] = [:]
        var index = materialParse.nextIndex

        while index < tokens.count {
            let name = tokens[index].lowercased()
            if name == "uva" || name == "uvb" || name == "uvc" || name == "uvd" {
                let parsed = try parseNamedVector2(tokens, index: index, line: line)
                texcoords[name] = parsed.value
                index = parsed.nextIndex
            } else {
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                corners[parsed.name.lowercased()] = parsed.value
                index = parsed.nextIndex
            }
        }

        guard let a = corners["a"],
              let b = corners["b"],
              let c = corners["c"],
              let d = corners["d"] else {
            throw SceneScriptError.invalidArgumentCount("quad", line: line)
        }

        let quadTexcoords: [SIMD2<Float>]
        if let uvA = texcoords["uva"],
           let uvB = texcoords["uvb"],
           let uvC = texcoords["uvc"],
           let uvD = texcoords["uvd"] {
            quadTexcoords = [uvA, uvB, uvC, uvD]
        } else if texcoords.isEmpty {
            quadTexcoords = [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(1, 0),
                SIMD2<Float>(1, 1),
                SIMD2<Float>(0, 1)
            ]
        } else {
            throw SceneScriptError.invalidArgumentCount("quad", line: line)
        }

        return (
            Mesh.quad(a, b, c, d, texcoords: quadTexcoords),
            material
        )
    }

    private static func parseBox(
        _ tokens: [String],
        line: Int,
        materials: [String: MaterialID]
    ) throws -> (mesh: Mesh, material: MaterialID, transform: Transform) {
        if tokens.count == 8 || tokens.count == 9 {
            let material = try material(named: tokens[1], line: line, materials: materials)
            let values = try floats(tokens[2..<tokens.count], line: line)
            let mesh = Mesh.box(size: SIMD3<Float>(values[3], values[4], values[5]))
            var transform = Transform.translation(SIMD3<Float>(values[0], values[1], values[2]))
            if values.count == 7 {
                transform = transform * Transform.rotationY(radians: values[6])
            }

            return (mesh, material, transform)
        }

        let materialParse = try parseOptionalNamedString(
            tokens,
            index: 1,
            keyword: "material",
            defaultConsumesBareValue: true,
            line: line
        )
        let material = try material(named: materialParse.value, line: line, materials: materials)
        var position = SIMD3<Float>(repeating: 0)
        var size: SIMD3<Float>?
        var rotationY: Float?
        var index = materialParse.nextIndex

        while index < tokens.count {
            let keyword = tokens[index].lowercased()
            switch keyword {
            case "position", "translation", "translate":
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                position = parsed.value
                index = parsed.nextIndex
            case "size", "scale":
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                size = parsed.value
                index = parsed.nextIndex
            case "rotationy", "rotatey":
                let parsed = try parseNamedFloat(tokens, index: index, line: line)
                rotationY = parsed.value
                index = parsed.nextIndex
            default:
                throw SceneScriptError.invalidArgumentCount("box", line: line)
            }
        }

        guard let size else {
            throw SceneScriptError.invalidArgumentCount("box", line: line)
        }

        let mesh = Mesh.box(size: size)
        var transform = Transform.translation(position)
        if let rotationY {
            transform = transform * Transform.rotationY(radians: rotationY)
        }

        return (mesh, material, transform)
    }

    private static func parseInstance(
        _ tokens: [String],
        line: Int,
        materials: [String: MaterialID],
        meshes: [String: Mesh]
    ) throws -> (mesh: Mesh, material: MaterialID, transform: Transform) {
        if tokens.count == 9 || tokens.count == 10 {
            let mesh = try meshAsset(named: tokens[1], line: line, meshes: meshes)
            let material = try material(named: tokens[2], line: line, materials: materials)
            let values = try floats(tokens[3..<tokens.count], line: line)
            var transform = Transform.translation(SIMD3<Float>(values[0], values[1], values[2]))
                * Transform.scale(SIMD3<Float>(values[3], values[4], values[5]))
            if values.count == 7 {
                transform = Transform.translation(SIMD3<Float>(values[0], values[1], values[2]))
                    * Transform.rotationY(radians: values[6])
                    * Transform.scale(SIMD3<Float>(values[3], values[4], values[5]))
            }

            return (mesh, material, transform)
        }

        var index = 1
        let meshNameParse = try parseOptionalNamedString(
            tokens,
            index: index,
            keyword: "mesh",
            defaultConsumesBareValue: true,
            line: line
        )
        index = meshNameParse.nextIndex
        let materialNameParse = try parseOptionalNamedString(
            tokens,
            index: index,
            keyword: "material",
            defaultConsumesBareValue: true,
            line: line
        )
        index = materialNameParse.nextIndex

        let mesh = try meshAsset(named: meshNameParse.value, line: line, meshes: meshes)
        let material = try material(named: materialNameParse.value, line: line, materials: materials)
        var position = SIMD3<Float>(repeating: 0)
        var scale = SIMD3<Float>(repeating: 1)
        var rotationY: Float?

        while index < tokens.count {
            let keyword = tokens[index].lowercased()
            switch keyword {
            case "position", "translation", "translate":
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                position = parsed.value
                index = parsed.nextIndex
            case "scale":
                let parsed = try parseNamedVector3(tokens, index: index, line: line)
                scale = parsed.value
                index = parsed.nextIndex
            case "rotationy", "rotatey":
                let parsed = try parseNamedFloat(tokens, index: index, line: line)
                rotationY = parsed.value
                index = parsed.nextIndex
            default:
                throw SceneScriptError.invalidArgumentCount("instance", line: line)
            }
        }

        var transform = Transform.translation(position)
        if let rotationY {
            transform = transform * Transform.rotationY(radians: rotationY)
        }
        transform = transform * Transform.scale(scale)

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

    private static func texture(
        named name: String,
        line: Int,
        textures: [String: Texture2D]
    ) throws -> Texture2D {
        guard let texture = textures[name] else {
            throw SceneScriptError.unknownTexture(name, line: line)
        }
        return texture
    }

    private static func meshAsset(
        named name: String,
        line: Int,
        meshes: [String: Mesh]
    ) throws -> Mesh {
        guard let mesh = meshes[name] else {
            throw SceneScriptError.unknownMesh(name, line: line)
        }
        return mesh
    }

    private static func parseOptionalNamedString(
        _ tokens: [String],
        index: Int,
        keyword: String,
        defaultConsumesBareValue: Bool,
        line: Int
    ) throws -> (value: String, nextIndex: Int) {
        guard index < tokens.count else {
            throw SceneScriptError.invalidArgumentCount(keyword, line: line)
        }

        if tokens[index].lowercased() == keyword.lowercased() {
            if tokens.indices.contains(index + 1),
               tokens[index + 1] == "(" {
                guard tokens.indices.contains(index + 3),
                      tokens[index + 3] == ")" else {
                    throw SceneScriptError.invalidArgumentCount(keyword, line: line)
                }
                return (tokens[index + 2], index + 4)
            }

            guard tokens.indices.contains(index + 1) else {
                throw SceneScriptError.invalidArgumentCount(keyword, line: line)
            }
            return (tokens[index + 1], index + 2)
        }

        guard defaultConsumesBareValue else {
            throw SceneScriptError.invalidArgumentCount(keyword, line: line)
        }
        return (tokens[index], index + 1)
    }

    private static func parseNamedVector3(
        _ tokens: [String],
        index: Int,
        line: Int
    ) throws -> (name: String, value: SIMD3<Float>, nextIndex: Int) {
        guard index < tokens.count else {
            throw SceneScriptError.invalidArgumentCount("vector", line: line)
        }

        let name = tokens[index]
        if tokens.indices.contains(index + 1),
           tokens[index + 1] == "(" {
            guard tokens.indices.contains(index + 5),
                  tokens[index + 5] == ")" else {
                throw SceneScriptError.invalidArgumentCount(name, line: line)
            }
            let values = try floats(tokens[(index + 2)...(index + 4)], line: line)
            return (
                name,
                SIMD3<Float>(values[0], values[1], values[2]),
                index + 6
            )
        }

        guard tokens.indices.contains(index + 3) else {
            throw SceneScriptError.invalidArgumentCount(name, line: line)
        }
        let values = try floats(tokens[(index + 1)...(index + 3)], line: line)
        return (
            name,
            SIMD3<Float>(values[0], values[1], values[2]),
            index + 4
        )
    }

    private static func parseNamedVector2(
        _ tokens: [String],
        index: Int,
        line: Int
    ) throws -> (name: String, value: SIMD2<Float>, nextIndex: Int) {
        guard index < tokens.count else {
            throw SceneScriptError.invalidArgumentCount("vector", line: line)
        }

        let name = tokens[index]
        if tokens.indices.contains(index + 1),
           tokens[index + 1] == "(" {
            guard tokens.indices.contains(index + 4),
                  tokens[index + 4] == ")" else {
                throw SceneScriptError.invalidArgumentCount(name, line: line)
            }
            let values = try floats(tokens[(index + 2)...(index + 3)], line: line)
            return (
                name,
                SIMD2<Float>(values[0], values[1]),
                index + 5
            )
        }

        guard tokens.indices.contains(index + 2) else {
            throw SceneScriptError.invalidArgumentCount(name, line: line)
        }
        let values = try floats(tokens[(index + 1)...(index + 2)], line: line)
        return (
            name,
            SIMD2<Float>(values[0], values[1]),
            index + 3
        )
    }

    private static func parseNamedFloat(
        _ tokens: [String],
        index: Int,
        line: Int
    ) throws -> (name: String, value: Float, nextIndex: Int) {
        guard index < tokens.count else {
            throw SceneScriptError.invalidArgumentCount("float", line: line)
        }

        let name = tokens[index]
        if tokens.indices.contains(index + 1),
           tokens[index + 1] == "(" {
            guard tokens.indices.contains(index + 3),
                  tokens[index + 3] == ")" else {
                throw SceneScriptError.invalidArgumentCount(name, line: line)
            }
            return (
                name,
                try floats(tokens[(index + 2)...(index + 2)], line: line)[0],
                index + 4
            )
        }

        guard tokens.indices.contains(index + 1) else {
            throw SceneScriptError.invalidArgumentCount(name, line: line)
        }
        return (
            name,
            try floats(tokens[(index + 1)...(index + 1)], line: line)[0],
            index + 2
        )
    }

    private static func rgba<S: Sequence>(_ tokens: S, line: Int) throws -> SIMD4<Float> where S.Element == String {
        let values = try floats(tokens, line: line)
        guard values.count == 4 else {
            throw SceneScriptError.invalidArgumentCount("texture", line: line)
        }
        return SIMD4<Float>(values[0], values[1], values[2], values[3])
    }

    private static func textureSamplingMode<S: Sequence>(
        _ tokens: S,
        line: Int
    ) throws -> TextureSamplingMode where S.Element == String {
        let values = Array(tokens)
        guard let mode = values.first else {
            return .nearest
        }
        guard values.count == 1 else {
            throw SceneScriptError.invalidArgumentCount("texture", line: line)
        }

        switch mode.lowercased() {
        case "nearest":
            return .nearest
        case "linear":
            return .linear
        default:
            throw SceneScriptError.invalidArgumentCount("texture", line: line)
        }
    }

    private static func imageTextureOptions<S: Sequence>(
        _ tokens: S,
        line: Int
    ) throws -> (colorEncoding: TextureColorEncoding, samplingMode: TextureSamplingMode) where S.Element == String {
        let values = Array(tokens)
        var colorEncoding = TextureColorEncoding.sRGB
        var samplingMode = TextureSamplingMode.linear
        var index = 0

        while index < values.count {
            switch values[index].lowercased() {
            case "color":
                guard index + 1 < values.count else {
                    throw SceneScriptError.invalidArgumentCount("texture", line: line)
                }
                switch values[index + 1].lowercased() {
                case "srgb":
                    colorEncoding = .sRGB
                case "linear":
                    colorEncoding = .linear
                default:
                    throw SceneScriptError.invalidArgumentCount("texture", line: line)
                }
                index += 2
            case "sampler":
                guard index + 1 < values.count else {
                    throw SceneScriptError.invalidArgumentCount("texture", line: line)
                }
                samplingMode = try textureSamplingMode([values[index + 1]], line: line)
                index += 2
            default:
                throw SceneScriptError.invalidArgumentCount("texture", line: line)
            }
        }

        return (colorEncoding, samplingMode)
    }

    private static func assetURL(path: String, baseURL: URL?) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        if let baseURL {
            return baseURL.appendingPathComponent(path)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
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
