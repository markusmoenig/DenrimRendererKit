import Foundation
import Metal

/// Errors thrown by DenrimRendererKit.
public enum DenrimRendererError: Error, LocalizedError {
    case noMetalDevice
    case missingShaderFunction(String)
    case invalidScene(String)
    case commandBufferFailed(String)
    case pngExportFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            "No compatible Metal device is available."
        case .missingShaderFunction(let name):
            "Missing Metal shader function: \(name)."
        case .invalidScene(let reason):
            "Invalid render scene: \(reason)."
        case .commandBufferFailed(let reason):
            "Metal command buffer failed: \(reason)."
        case .pngExportFailed(let url):
            "Failed to export PNG at \(url.path)."
        }
    }
}

/// Entry point for creating Metal-backed render sessions.
public final class DenrimRenderer {
    /// The Metal device used by this renderer.
    public let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    /// Creates a renderer using the supplied Metal device or the system default device.
    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else {
            throw DenrimRendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw DenrimRendererError.noMetalDevice
        }

        let library = try Self.makeLibrary(device: device)
        guard let function = library.makeFunction(name: "pathTraceKernel") else {
            throw DenrimRendererError.missingShaderFunction("pathTraceKernel")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: .module) {
            return library
        }

        let shaderURL = Bundle.module.url(
            forResource: "PathTrace",
            withExtension: "metal",
            subdirectory: "Shaders"
        ) ?? Bundle.module.url(forResource: "PathTrace", withExtension: "metal")

        guard let shaderURL else {
            throw DenrimRendererError.missingShaderFunction("PathTrace.metal")
        }

        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        return try device.makeLibrary(source: source, options: nil)
    }

    /// Creates a progressive render session for a scene and settings.
    public func makeSession(
        scene: RenderScene,
        settings: RenderSettings = RenderSettings()
    ) throws -> RenderSession {
        try RenderSession(
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline,
            scene: scene,
            settings: settings
        )
    }
}
