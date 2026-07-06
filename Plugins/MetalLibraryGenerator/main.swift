import Foundation

#if os(macOS)

enum GeneratorError: Error, LocalizedError {
    case invalidArguments
    case processFailed([String], Int32, String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: MetalLibraryGenerator <metallib-output> <shader.metal>..."
        case .processFailed(let command, let status, let output):
            return "Command failed (\(status)): \(command.joined(separator: " "))\n\(output)"
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    throw GeneratorError.invalidArguments
}

let metallibOutputURL = URL(fileURLWithPath: arguments[0])
let shaderURLs = arguments.dropFirst().map { URL(fileURLWithPath: $0) }
let fileManager = FileManager.default
try fileManager.createDirectory(
    at: metallibOutputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

if outputIsCurrent(output: metallibOutputURL, inputs: shaderURLs) {
    exit(0)
}

let airDirectory = metallibOutputURL.deletingLastPathComponent()
    .appendingPathComponent("MetalAIR", isDirectory: true)
try fileManager.createDirectory(at: airDirectory, withIntermediateDirectories: true)

let airURLs = try shaderURLs.enumerated().map { index, shaderURL in
    let airURL = airDirectory.appendingPathComponent("\(index)-\(shaderURL.deletingPathExtension().lastPathComponent).air")
    if !outputIsCurrent(output: airURL, inputs: [shaderURL]) {
        try run([
            "/usr/bin/xcrun",
            "metal",
            "-c",
            shaderURL.path,
            "-o",
            airURL.path
        ])
    }
    return airURL
}

if !outputIsCurrent(output: metallibOutputURL, inputs: airURLs) {
    try run([
        "/usr/bin/xcrun",
        "metallib"
    ] + airURLs.map(\.path) + [
        "-o",
        metallibOutputURL.path
    ])
}

func run(_ command: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw GeneratorError.processFailed(command, process.terminationStatus, output)
    }
}

func outputIsCurrent(output: URL, inputs: [URL]) -> Bool {
    guard let outputDate = modificationDate(output) else {
        return false
    }
    return inputs.allSatisfy { input in
        guard let inputDate = modificationDate(input) else {
            return false
        }
        return inputDate <= outputDate
    }
}

func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
}

#else

fatalError("MetalLibraryGenerator can only run on macOS.")

#endif
