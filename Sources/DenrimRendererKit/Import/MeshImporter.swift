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
        try parse(Data(contentsOf: url))
    }

    static func parse(_ source: String) throws -> Mesh {
        try parse(Data(source.utf8))
    }

    private static func parse(_ data: Data) throws -> Mesh {
        var scanner = OBJByteScanner(data: data)
        var sourcePositions: [SIMD3<Float>] = []
        var sourceTexcoords: [SIMD2<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []

        var vertices: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var packedIndices: [VertexKey: UInt32] = [:]

        sourcePositions.reserveCapacity(data.count / 96)
        sourceTexcoords.reserveCapacity(data.count / 128)
        sourceNormals.reserveCapacity(data.count / 128)
        vertices.reserveCapacity(data.count / 96)
        texcoords.reserveCapacity(data.count / 96)
        normals.reserveCapacity(data.count / 96)
        indices.reserveCapacity(data.count / 32)

        while !scanner.isAtEnd {
            scanner.skipHorizontalWhitespace()
            if scanner.consumeLineBreakIfPresent() {
                continue
            }
            if scanner.consumeCommentIfPresent() {
                continue
            }

            let command = scanner.readToken()
            let lineNumber = scanner.line

            if command.matches("v") {
                sourcePositions.append(SIMD3<Float>(
                    try scanner.readFloat(),
                    try scanner.readFloat(),
                    try scanner.readFloat()
                ))
            } else if command.matches("vt") {
                sourceTexcoords.append(SIMD2<Float>(
                    try scanner.readFloat(),
                    try scanner.readFloat()
                ))
            } else if command.matches("vn") {
                sourceNormals.append(simd_normalize(SIMD3<Float>(
                    try scanner.readFloat(),
                    try scanner.readFloat(),
                    try scanner.readFloat()
                )))
            } else if command.matches("f") {
                var first: FaceVertex?
                var previous: FaceVertex?
                var faceVertexCount = 0

                while true {
                    scanner.skipHorizontalWhitespace()
                    if scanner.isAtEnd || scanner.isAtLineBreak || scanner.isAtComment {
                        break
                    }

                    let faceVertex = try scanner.readFaceVertex(
                        positions: sourcePositions.count,
                        texcoords: sourceTexcoords.count,
                        normals: sourceNormals.count
                    )
                    if faceVertexCount == 0 {
                        first = faceVertex
                    } else if faceVertexCount == 1 {
                        previous = faceVertex
                    } else if let first, let previousFace = previous {
                        try append(
                            first,
                            sourcePositions,
                            sourceTexcoords,
                            sourceNormals,
                            &vertices,
                            &texcoords,
                            &normals,
                            &indices,
                            &packedIndices
                        )
                        try append(
                            previousFace,
                            sourcePositions,
                            sourceTexcoords,
                            sourceNormals,
                            &vertices,
                            &texcoords,
                            &normals,
                            &indices,
                            &packedIndices
                        )
                        try append(
                            faceVertex,
                            sourcePositions,
                            sourceTexcoords,
                            sourceNormals,
                            &vertices,
                            &texcoords,
                            &normals,
                            &indices,
                            &packedIndices
                        )
                        previous = faceVertex
                    }
                    faceVertexCount += 1
                }

                guard faceVertexCount >= 3 else {
                    throw MeshLoadingError.invalidOBJ("face requires at least three vertices", line: lineNumber)
                }
            }

            scanner.skipLine()
        }

        guard !vertices.isEmpty, !indices.isEmpty else {
            throw MeshLoadingError.invalidOBJ("mesh contains no faces", line: 0)
        }

        return Mesh(vertices: vertices, indices: indices, normals: normals, texcoords: texcoords)
    }

    private struct OBJCommand {
        var bytes: [UInt8]
        var start: Int
        var end: Int

        func matches(_ literal: StaticString) -> Bool {
            let count = literal.utf8CodeUnitCount
            guard end - start == count else {
                return false
            }
            return literal.withUTF8Buffer { literalBytes in
                for offset in 0..<count where bytes[start + offset] != literalBytes[offset] {
                    return false
                }
                return true
            }
        }
    }

    private struct OBJByteScanner {
        var bytes: [UInt8]
        var index: Int = 0
        var line: Int = 1

        init(data: Data) {
            self.bytes = Array(data)
        }

        var isAtEnd: Bool {
            index >= bytes.count
        }

        var isAtLineBreak: Bool {
            !isAtEnd && bytes[index] == 10
        }

        var isAtComment: Bool {
            !isAtEnd && bytes[index] == 35
        }

        mutating func skipHorizontalWhitespace() {
            while !isAtEnd {
                let byte = bytes[index]
                if byte == 32 || byte == 9 || byte == 13 {
                    index += 1
                } else {
                    break
                }
            }
        }

        mutating func consumeLineBreakIfPresent() -> Bool {
            guard !isAtEnd, bytes[index] == 10 else {
                return false
            }
            index += 1
            line += 1
            return true
        }

        mutating func consumeCommentIfPresent() -> Bool {
            guard isAtComment else {
                return false
            }
            skipLine()
            return true
        }

        mutating func skipLine() {
            while !isAtEnd {
                let byte = bytes[index]
                index += 1
                if byte == 10 {
                    line += 1
                    return
                }
            }
        }

        mutating func readToken() -> OBJCommand {
            let start = index
            while !isAtEnd {
                let byte = bytes[index]
                if byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 35 {
                    break
                }
                index += 1
            }
            return OBJCommand(bytes: bytes, start: start, end: index)
        }

        mutating func readFaceVertex(positions: Int, texcoords: Int, normals: Int) throws -> FaceVertex {
            let position = try resolveIndex(readInt(), count: positions)
            var texcoord: Int?
            var normal: Int?

            if consumeSlash() {
                if !isAtEnd, bytes[index] != 47, !isAtLineBreak, !isAtComment {
                    texcoord = try resolveIndex(readInt(), count: texcoords)
                }

                if consumeSlash(), !isAtEnd, !isAtLineBreak, !isAtComment {
                    normal = try resolveIndex(readInt(), count: normals)
                }
            }

            return FaceVertex(position: position, texcoord: texcoord, normal: normal)
        }

        mutating func readFloat() throws -> Float {
            skipHorizontalWhitespace()
            let start = index
            var sign: Double = 1
            if consume(byte: 45) {
                sign = -1
            } else {
                _ = consume(byte: 43)
            }

            var value: Double = 0
            var hasDigits = false
            while let digit = readDigit() {
                hasDigits = true
                value = value * 10 + Double(digit)
            }

            if consume(byte: 46) {
                var scale: Double = 0.1
                while let digit = readDigit() {
                    hasDigits = true
                    value += Double(digit) * scale
                    scale *= 0.1
                }
            }

            guard hasDigits else {
                throw MeshLoadingError.invalidOBJ("invalid number '\(tokenString(start: start))'", line: line)
            }

            if consume(byte: 101) || consume(byte: 69) {
                var exponentSign = 1
                if consume(byte: 45) {
                    exponentSign = -1
                } else {
                    _ = consume(byte: 43)
                }

                var exponent = 0
                var hasExponentDigits = false
                while let digit = readDigit() {
                    hasExponentDigits = true
                    exponent = exponent * 10 + digit
                }
                guard hasExponentDigits else {
                    throw MeshLoadingError.invalidOBJ("invalid number '\(tokenString(start: start))'", line: line)
                }
                value *= pow(10, Double(exponent * exponentSign))
            }

            return Float(sign * value)
        }

        mutating func readInt() throws -> Int {
            skipHorizontalWhitespace()
            let start = index
            var sign = 1
            if consume(byte: 45) {
                sign = -1
            } else {
                _ = consume(byte: 43)
            }

            var value = 0
            var hasDigits = false
            while let digit = readDigit() {
                hasDigits = true
                value = value * 10 + digit
            }

            guard hasDigits else {
                throw MeshLoadingError.invalidIndex(tokenString(start: start), line: line)
            }

            return value * sign
        }

        private mutating func resolveIndex(_ rawIndex: Int, count: Int) throws -> Int {
            guard rawIndex != 0 else {
                throw MeshLoadingError.invalidIndex("0", line: line)
            }

            let resolved = rawIndex > 0 ? rawIndex - 1 : count + rawIndex
            guard resolved >= 0, resolved < count else {
                throw MeshLoadingError.invalidIndex(String(rawIndex), line: line)
            }
            return resolved
        }

        private mutating func consumeSlash() -> Bool {
            consume(byte: 47)
        }

        private mutating func consume(byte: UInt8) -> Bool {
            guard !isAtEnd, bytes[index] == byte else {
                return false
            }
            index += 1
            return true
        }

        private mutating func readDigit() -> Int? {
            guard !isAtEnd else {
                return nil
            }
            let byte = bytes[index]
            guard byte >= 48, byte <= 57 else {
                return nil
            }
            index += 1
            return Int(byte - 48)
        }

        private func tokenString(start: Int) -> String {
            var end = start
            while end < bytes.count {
                let byte = bytes[end]
                if byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 35 || byte == 47 {
                    break
                }
                end += 1
            }
            return String(decoding: bytes[start..<end], as: UTF8.self)
        }
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
