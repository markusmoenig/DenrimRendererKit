import Foundation
import simd

/// Errors produced while loading mesh assets.
public enum MeshLoadingError: Error, LocalizedError, Equatable {
    case unsupportedFormat(String)
    case invalidOBJ(String, line: Int)
    case invalidPLY(String, line: Int)
    case invalidIndex(String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let pathExtension):
            "Unsupported mesh format '\(pathExtension)'."
        case .invalidOBJ(let reason, let line):
            "Invalid OBJ mesh on line \(line): \(reason)."
        case .invalidPLY(let reason, let line):
            "Invalid PLY mesh on line \(line): \(reason)."
        case .invalidIndex(let value, let line):
            "Invalid mesh index '\(value)' on line \(line)."
        }
    }
}

public extension Mesh {
    /// Loads a mesh asset from disk.
    ///
    /// The first implementations support Wavefront OBJ and PLY files. glTF/GLB
    /// are planned future import paths.
    init(contentsOf url: URL) throws {
        switch url.pathExtension.lowercased() {
        case "obj":
            self = try OBJMeshImporter.load(url: url)
        case "ply":
            self = try PLYMeshImporter.load(url: url)
        default:
            throw MeshLoadingError.unsupportedFormat(url.pathExtension)
        }
    }
}

private enum OBJMeshImporter {
    private struct VertexKey: Hashable {
        var position: Int
        var texcoord: Int?
        var normal: Int?
    }

    private struct FaceVertex {
        var position: Int
        var texcoord: Int?
        var normal: Int?
    }

    static func load(url: URL) throws -> Mesh {
        let source = try String(contentsOf: url, encoding: .utf8)
        return try parse(source)
    }

    static func parse(_ source: String) throws -> Mesh {
        var sourcePositions: [SIMD3<Float>] = []
        var sourceTexcoords: [SIMD2<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []

        var vertices: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var packedIndices: [VertexKey: UInt32] = [:]

        for (lineIndex, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            let uncommentedLine = rawLine.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? ""
            let tokens = uncommentedLine.split(whereSeparator: \.isWhitespace)
            guard let command = tokens.first else {
                continue
            }

            switch command {
            case "v":
                guard tokens.count >= 4 else {
                    throw MeshLoadingError.invalidOBJ("vertex position requires x y z", line: lineNumber)
                }
                sourcePositions.append(SIMD3<Float>(
                    try float(tokens[1], line: lineNumber),
                    try float(tokens[2], line: lineNumber),
                    try float(tokens[3], line: lineNumber)
                ))
            case "vt":
                guard tokens.count >= 3 else {
                    throw MeshLoadingError.invalidOBJ("texture coordinate requires u v", line: lineNumber)
                }
                sourceTexcoords.append(SIMD2<Float>(
                    try float(tokens[1], line: lineNumber),
                    try float(tokens[2], line: lineNumber)
                ))
            case "vn":
                guard tokens.count >= 4 else {
                    throw MeshLoadingError.invalidOBJ("normal requires x y z", line: lineNumber)
                }
                sourceNormals.append(simd_normalize(SIMD3<Float>(
                    try float(tokens[1], line: lineNumber),
                    try float(tokens[2], line: lineNumber),
                    try float(tokens[3], line: lineNumber)
                )))
            case "f":
                guard tokens.count >= 4 else {
                    throw MeshLoadingError.invalidOBJ("face requires at least three vertices", line: lineNumber)
                }
                let face = try tokens.dropFirst().map {
                    try parseFaceVertex(
                        $0,
                        positions: sourcePositions.count,
                        texcoords: sourceTexcoords.count,
                        normals: sourceNormals.count,
                        line: lineNumber
                    )
                }
                for index in 1..<(face.count - 1) {
                    try append(face[0], sourcePositions, sourceTexcoords, sourceNormals, &vertices, &texcoords, &normals, &indices, &packedIndices)
                    try append(face[index], sourcePositions, sourceTexcoords, sourceNormals, &vertices, &texcoords, &normals, &indices, &packedIndices)
                    try append(face[index + 1], sourcePositions, sourceTexcoords, sourceNormals, &vertices, &texcoords, &normals, &indices, &packedIndices)
                }
            default:
                continue
            }
        }

        guard !vertices.isEmpty, !indices.isEmpty else {
            throw MeshLoadingError.invalidOBJ("mesh contains no faces", line: 0)
        }

        return Mesh(vertices: vertices, indices: indices, normals: normals, texcoords: texcoords)
    }

    private static func float(_ token: some StringProtocol, line: Int) throws -> Float {
        guard let value = Float(token) else {
            throw MeshLoadingError.invalidOBJ("invalid number '\(token)'", line: line)
        }
        return value
    }

    private static func parseFaceVertex(
        _ token: some StringProtocol,
        positions: Int,
        texcoords: Int,
        normals: Int,
        line: Int
    ) throws -> FaceVertex {
        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else {
            throw MeshLoadingError.invalidOBJ("unsupported face vertex '\(token)'", line: line)
        }

        return FaceVertex(
            position: try resolveIndex(parts[0], count: positions, line: line),
            texcoord: parts.count > 1 && !parts[1].isEmpty
                ? try resolveIndex(parts[1], count: texcoords, line: line)
                : nil,
            normal: parts.count > 2 && !parts[2].isEmpty
                ? try resolveIndex(parts[2], count: normals, line: line)
                : nil
        )
    }

    private static func resolveIndex(_ token: some StringProtocol, count: Int, line: Int) throws -> Int {
        guard let rawIndex = Int(token), rawIndex != 0 else {
            throw MeshLoadingError.invalidIndex(String(token), line: line)
        }

        let index = rawIndex > 0 ? rawIndex - 1 : count + rawIndex
        guard index >= 0, index < count else {
            throw MeshLoadingError.invalidIndex(String(token), line: line)
        }
        return index
    }

    private static func append(
        _ faceVertex: FaceVertex,
        _ sourcePositions: [SIMD3<Float>],
        _ sourceTexcoords: [SIMD2<Float>],
        _ sourceNormals: [SIMD3<Float>],
        _ vertices: inout [SIMD3<Float>],
        _ texcoords: inout [SIMD2<Float>],
        _ normals: inout [SIMD3<Float>],
        _ indices: inout [UInt32],
        _ packedIndices: inout [VertexKey: UInt32]
    ) throws {
        let key = VertexKey(
            position: faceVertex.position,
            texcoord: faceVertex.texcoord,
            normal: faceVertex.normal
        )

        if let existing = packedIndices[key] {
            indices.append(existing)
            return
        }

        let next = UInt32(vertices.count)
        packedIndices[key] = next
        vertices.append(sourcePositions[faceVertex.position])
        texcoords.append(faceVertex.texcoord.map { sourceTexcoords[$0] } ?? SIMD2<Float>(0, 0))
        normals.append(faceVertex.normal.map { sourceNormals[$0] } ?? SIMD3<Float>(0, 0, 0))
        indices.append(next)
    }
}

private enum PLYMeshImporter {
    private enum Format {
        case ascii
        case binaryLittleEndian
    }

    private struct Header {
        var format: Format
        var elements: [Element]
        var bodyOffset: Int
    }

    private struct Element {
        var name: String
        var count: Int
        var properties: [Property]
    }

    private struct Property {
        var name: String
        var scalarType: ScalarType?
        var listCountType: ScalarType?
        var listValueType: ScalarType?

        var isList: Bool {
            listCountType != nil
        }
    }

    private enum ScalarType: String {
        case int8 = "char"
        case uint8 = "uchar"
        case int16 = "short"
        case uint16 = "ushort"
        case int32 = "int"
        case uint32 = "uint"
        case float32 = "float"
        case float64 = "double"

        init?(_ token: String) {
            switch token {
            case "char", "int8":
                self = .int8
            case "uchar", "uint8":
                self = .uint8
            case "short", "int16":
                self = .int16
            case "ushort", "uint16":
                self = .uint16
            case "int", "int32":
                self = .int32
            case "uint", "uint32":
                self = .uint32
            case "float", "float32":
                self = .float32
            case "double", "float64":
                self = .float64
            default:
                return nil
            }
        }

        var byteCount: Int {
            switch self {
            case .int8, .uint8:
                1
            case .int16, .uint16:
                2
            case .int32, .uint32, .float32:
                4
            case .float64:
                8
            }
        }
    }

    static func load(url: URL) throws -> Mesh {
        try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> Mesh {
        let header = try parseHeader(data)
        switch header.format {
        case .ascii:
            return try parseASCII(data, header: header)
        case .binaryLittleEndian:
            return try parseBinaryLittleEndian(data, header: header)
        }
    }

    private static func parseHeader(_ data: Data) throws -> Header {
        let marker = Data("end_header\n".utf8)
        let crlfMarker = Data("end_header\r\n".utf8)
        let range = data.range(of: marker) ?? data.range(of: crlfMarker)
        guard let range else {
            throw MeshLoadingError.invalidPLY("missing end_header", line: 0)
        }

        guard let headerSource = String(data: data[..<range.upperBound], encoding: .utf8) else {
            throw MeshLoadingError.invalidPLY("header is not UTF-8", line: 0)
        }

        let lines = headerSource.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "ply" else {
            throw MeshLoadingError.invalidPLY("missing ply header", line: 1)
        }

        var format: Format?
        var elements: [Element] = []

        for (lineIndex, line) in lines.dropFirst().enumerated() {
            let lineNumber = lineIndex + 2
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = tokens.first else {
                continue
            }

            switch command {
            case "comment", "obj_info", "end_header":
                continue
            case "format":
                guard tokens.count >= 3, tokens[2] == "1.0" else {
                    throw MeshLoadingError.invalidPLY("unsupported format declaration", line: lineNumber)
                }
                switch tokens[1] {
                case "ascii":
                    format = .ascii
                case "binary_little_endian":
                    format = .binaryLittleEndian
                default:
                    throw MeshLoadingError.invalidPLY("unsupported format '\(tokens[1])'", line: lineNumber)
                }
            case "element":
                guard tokens.count == 3, let count = Int(tokens[2]), count >= 0 else {
                    throw MeshLoadingError.invalidPLY("invalid element declaration", line: lineNumber)
                }
                elements.append(Element(name: tokens[1], count: count, properties: []))
            case "property":
                guard !elements.isEmpty else {
                    throw MeshLoadingError.invalidPLY("property before element", line: lineNumber)
                }
                if tokens.count == 5, tokens[1] == "list" {
                    guard let countType = ScalarType(tokens[2]), let valueType = ScalarType(tokens[3]) else {
                        throw MeshLoadingError.invalidPLY("unsupported list property type", line: lineNumber)
                    }
                    elements[elements.count - 1].properties.append(Property(
                        name: tokens[4],
                        scalarType: nil,
                        listCountType: countType,
                        listValueType: valueType
                    ))
                } else if tokens.count == 3 {
                    guard let type = ScalarType(tokens[1]) else {
                        throw MeshLoadingError.invalidPLY("unsupported property type '\(tokens[1])'", line: lineNumber)
                    }
                    elements[elements.count - 1].properties.append(Property(
                        name: tokens[2],
                        scalarType: type,
                        listCountType: nil,
                        listValueType: nil
                    ))
                } else {
                    throw MeshLoadingError.invalidPLY("invalid property declaration", line: lineNumber)
                }
            default:
                continue
            }
        }

        guard let format else {
            throw MeshLoadingError.invalidPLY("missing format declaration", line: 0)
        }

        return Header(format: format, elements: elements, bodyOffset: range.upperBound)
    }

    private static func parseASCII(_ data: Data, header: Header) throws -> Mesh {
        guard let body = String(data: data[header.bodyOffset...], encoding: .utf8) else {
            throw MeshLoadingError.invalidPLY("ASCII body is not UTF-8", line: 0)
        }

        var lineIterator = body.split(whereSeparator: \.isNewline).map(String.init).makeIterator()
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for element in header.elements {
            for elementIndex in 0..<element.count {
                guard let line = lineIterator.next() else {
                    throw MeshLoadingError.invalidPLY("unexpected end of file", line: elementIndex + 1)
                }
                let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
                var tokenIndex = 0

                if element.name == "vertex" {
                    var x: Float?
                    var y: Float?
                    var z: Float?
                    var nx: Float?
                    var ny: Float?
                    var nz: Float?
                    var u: Float?
                    var v: Float?

                    for property in element.properties {
                        if property.isList {
                            try skipASCIIList(property, tokens: tokens, tokenIndex: &tokenIndex, line: elementIndex + 1)
                        } else {
                            guard tokenIndex < tokens.count else {
                                throw MeshLoadingError.invalidPLY("missing vertex property", line: elementIndex + 1)
                            }
                            let value = try asciiFloat(tokens[tokenIndex], line: elementIndex + 1)
                            tokenIndex += 1
                            assignVertexProperty(property.name, value, &x, &y, &z, &nx, &ny, &nz, &u, &v)
                        }
                    }

                    guard let x, let y, let z else {
                        throw MeshLoadingError.invalidPLY("vertex missing x y z", line: elementIndex + 1)
                    }
                    positions.append(SIMD3<Float>(x, y, z))
                    normals.append(SIMD3<Float>(nx ?? 0, ny ?? 0, nz ?? 0))
                    texcoords.append(SIMD2<Float>(u ?? 0, v ?? 0))
                } else if element.name == "face" {
                    for property in element.properties {
                        if property.isList {
                            let values = try readASCIIList(property, tokens: tokens, tokenIndex: &tokenIndex, line: elementIndex + 1)
                            if isVertexIndexProperty(property.name) {
                                try appendFace(values, vertexCount: positions.count, indices: &indices, line: elementIndex + 1)
                            }
                        } else {
                            guard tokenIndex < tokens.count else {
                                throw MeshLoadingError.invalidPLY("missing face property", line: elementIndex + 1)
                            }
                            tokenIndex += 1
                        }
                    }
                } else {
                    try skipASCIIElement(element, tokens: tokens, tokenIndex: &tokenIndex, line: elementIndex + 1)
                }
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else {
            throw MeshLoadingError.invalidPLY("mesh contains no faces", line: 0)
        }

        return Mesh(vertices: positions, indices: indices, normals: normals, texcoords: texcoords)
    }

    private static func parseBinaryLittleEndian(_ data: Data, header: Header) throws -> Mesh {
        var reader = BinaryReader(data: data, offset: header.bodyOffset)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for element in header.elements {
            for elementIndex in 0..<element.count {
                if element.name == "vertex" {
                    var x: Float?
                    var y: Float?
                    var z: Float?
                    var nx: Float?
                    var ny: Float?
                    var nz: Float?
                    var u: Float?
                    var v: Float?

                    for property in element.properties {
                        if property.isList {
                            try reader.skipList(property, line: elementIndex + 1)
                        } else {
                            guard let type = property.scalarType else {
                                throw MeshLoadingError.invalidPLY("missing vertex property type", line: elementIndex + 1)
                            }
                            let value = try Float(reader.readNumber(type, line: elementIndex + 1))
                            assignVertexProperty(property.name, value, &x, &y, &z, &nx, &ny, &nz, &u, &v)
                        }
                    }

                    guard let x, let y, let z else {
                        throw MeshLoadingError.invalidPLY("vertex missing x y z", line: elementIndex + 1)
                    }
                    positions.append(SIMD3<Float>(x, y, z))
                    normals.append(SIMD3<Float>(nx ?? 0, ny ?? 0, nz ?? 0))
                    texcoords.append(SIMD2<Float>(u ?? 0, v ?? 0))
                } else if element.name == "face" {
                    for property in element.properties {
                        if property.isList {
                            let values = try reader.readList(property, line: elementIndex + 1)
                            if isVertexIndexProperty(property.name) {
                                try appendFace(values, vertexCount: positions.count, indices: &indices, line: elementIndex + 1)
                            }
                        } else if let type = property.scalarType {
                            try reader.skip(type, count: 1, line: elementIndex + 1)
                        }
                    }
                } else {
                    try reader.skipElement(element, line: elementIndex + 1)
                }
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else {
            throw MeshLoadingError.invalidPLY("mesh contains no faces", line: 0)
        }

        return Mesh(vertices: positions, indices: indices, normals: normals, texcoords: texcoords)
    }

    private static func assignVertexProperty(
        _ name: String,
        _ value: Float,
        _ x: inout Float?,
        _ y: inout Float?,
        _ z: inout Float?,
        _ nx: inout Float?,
        _ ny: inout Float?,
        _ nz: inout Float?,
        _ u: inout Float?,
        _ v: inout Float?
    ) {
        switch name {
        case "x":
            x = value
        case "y":
            y = value
        case "z":
            z = value
        case "nx":
            nx = value
        case "ny":
            ny = value
        case "nz":
            nz = value
        case "u", "s", "texture_u", "texture_s":
            u = value
        case "v", "t", "texture_v", "texture_t":
            v = value
        default:
            break
        }
    }

    private static func isVertexIndexProperty(_ name: String) -> Bool {
        name == "vertex_indices" || name == "vertex_index"
    }

    private static func appendFace(_ face: [Int], vertexCount: Int, indices: inout [UInt32], line: Int) throws {
        guard face.count >= 3 else {
            return
        }

        for index in face {
            guard index >= 0, index < vertexCount else {
                throw MeshLoadingError.invalidIndex(String(index), line: line)
            }
        }

        for index in 1..<(face.count - 1) {
            indices.append(UInt32(face[0]))
            indices.append(UInt32(face[index]))
            indices.append(UInt32(face[index + 1]))
        }
    }

    private static func asciiFloat(_ token: String, line: Int) throws -> Float {
        guard let value = Float(token) else {
            throw MeshLoadingError.invalidPLY("invalid number '\(token)'", line: line)
        }
        return value
    }

    private static func asciiInt(_ token: String, line: Int) throws -> Int {
        guard let value = Int(token) else {
            throw MeshLoadingError.invalidPLY("invalid integer '\(token)'", line: line)
        }
        return value
    }

    private static func readASCIIList(_ property: Property, tokens: [String], tokenIndex: inout Int, line: Int) throws -> [Int] {
        guard tokenIndex < tokens.count else {
            throw MeshLoadingError.invalidPLY("missing list count", line: line)
        }

        let count = try asciiInt(tokens[tokenIndex], line: line)
        tokenIndex += 1
        guard count >= 0, tokenIndex + count <= tokens.count else {
            throw MeshLoadingError.invalidPLY("invalid list length", line: line)
        }

        var values: [Int] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try asciiInt(tokens[tokenIndex], line: line))
            tokenIndex += 1
        }
        return values
    }

    private static func skipASCIIList(_ property: Property, tokens: [String], tokenIndex: inout Int, line: Int) throws {
        _ = try readASCIIList(property, tokens: tokens, tokenIndex: &tokenIndex, line: line)
    }

    private static func skipASCIIElement(_ element: Element, tokens: [String], tokenIndex: inout Int, line: Int) throws {
        for property in element.properties {
            if property.isList {
                try skipASCIIList(property, tokens: tokens, tokenIndex: &tokenIndex, line: line)
            } else {
                guard tokenIndex < tokens.count else {
                    throw MeshLoadingError.invalidPLY("missing property", line: line)
                }
                tokenIndex += 1
            }
        }
    }

    private struct BinaryReader {
        var data: Data
        var offset: Int

        mutating func readNumber(_ type: ScalarType, line: Int) throws -> Double {
            switch type {
            case .int8:
                return Double(Int8(bitPattern: try readInteger(UInt8.self, line: line)))
            case .uint8:
                return Double(try readInteger(UInt8.self, line: line))
            case .int16:
                return Double(Int16(littleEndian: try readInteger(Int16.self, line: line)))
            case .uint16:
                return Double(UInt16(littleEndian: try readInteger(UInt16.self, line: line)))
            case .int32:
                return Double(Int32(littleEndian: try readInteger(Int32.self, line: line)))
            case .uint32:
                return Double(UInt32(littleEndian: try readInteger(UInt32.self, line: line)))
            case .float32:
                let bits = UInt32(littleEndian: try readInteger(UInt32.self, line: line))
                return Double(Float(bitPattern: bits))
            case .float64:
                let bits = UInt64(littleEndian: try readInteger(UInt64.self, line: line))
                return Double(bitPattern: bits)
            }
        }

        mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type, line: Int) throws -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else {
                throw MeshLoadingError.invalidPLY("unexpected end of binary body", line: line)
            }

            let value = data.withUnsafeBytes { rawBuffer in
                rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
            }
            offset += size
            return value
        }

        mutating func readList(_ property: Property, line: Int) throws -> [Int] {
            guard let countType = property.listCountType, let valueType = property.listValueType else {
                throw MeshLoadingError.invalidPLY("missing list property type", line: line)
            }

            let count = Int(try readNumber(countType, line: line))
            guard count >= 0 else {
                throw MeshLoadingError.invalidPLY("negative list length", line: line)
            }

            var values: [Int] = []
            values.reserveCapacity(count)
            for _ in 0..<count {
                values.append(Int(try readNumber(valueType, line: line)))
            }
            return values
        }

        mutating func skipList(_ property: Property, line: Int) throws {
            _ = try readList(property, line: line)
        }

        mutating func skip(_ type: ScalarType, count: Int, line: Int) throws {
            let byteCount = type.byteCount * count
            guard offset + byteCount <= data.count else {
                throw MeshLoadingError.invalidPLY("unexpected end of binary body", line: line)
            }
            offset += byteCount
        }

        mutating func skipElement(_ element: Element, line: Int) throws {
            for property in element.properties {
                if property.isList {
                    try skipList(property, line: line)
                } else if let type = property.scalarType {
                    try skip(type, count: 1, line: line)
                }
            }
        }
    }
}
