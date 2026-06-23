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
    private let hardwareRayTracingPipeline: MTLComputePipelineState?
    private let simpleSpatialDenoisePipeline: MTLComputePipelineState?
    private let svgfDepthNormalPipeline: MTLComputePipelineState?
    private let svgfOutputCopyPipeline: MTLComputePipelineState?

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
        if device.supportsRaytracing,
           let hardwareFunction = library.makeFunction(name: "pathTraceHardwareKernel") {
            self.hardwareRayTracingPipeline = try? device.makeComputePipelineState(function: hardwareFunction)
        } else {
            self.hardwareRayTracingPipeline = nil
        }
        if let denoiseFunction = library.makeFunction(name: "simpleSpatialDenoiseKernel") {
            self.simpleSpatialDenoisePipeline = try device.makeComputePipelineState(function: denoiseFunction)
        } else {
            self.simpleSpatialDenoisePipeline = nil
        }
        if let packFunction = library.makeFunction(name: "packSVGFDepthNormalKernel"),
           let copyFunction = library.makeFunction(name: "copySVGFOutputKernel") {
            self.svgfDepthNormalPipeline = try device.makeComputePipelineState(function: packFunction)
            self.svgfOutputCopyPipeline = try device.makeComputePipelineState(function: copyFunction)
        } else {
            self.svgfDepthNormalPipeline = nil
            self.svgfOutputCopyPipeline = nil
        }
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: .module),
           library.makeFunction(name: "pathTraceKernel") != nil,
           library.makeFunction(name: "simpleSpatialDenoiseKernel") != nil,
           library.makeFunction(name: "packSVGFDepthNormalKernel") != nil,
           library.makeFunction(name: "copySVGFOutputKernel") != nil {
            return library
        }

        let shaderURLs = shaderSourceURLs()

        guard !shaderURLs.isEmpty else {
            guard let pathTraceURL = Bundle.module.url(forResource: "PathTrace", withExtension: "metal") else {
                throw DenrimRendererError.missingShaderFunction("Shaders")
            }
            let source = try String(contentsOf: pathTraceURL, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        }

        let source = try shaderURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n")
        return try device.makeLibrary(source: source, options: nil)
    }

    private static func shaderSourceURLs() -> [URL] {
        let names = ["Denoise", "PathTrace"]
        var urls: [URL] = []

        for name in names {
            if let url = Bundle.module.url(
                forResource: name,
                withExtension: "metal",
                subdirectory: "Shaders"
            ) ?? Bundle.module.url(forResource: name, withExtension: "metal") {
                urls.append(url)
            }
        }

        if urls.isEmpty {
            urls = Bundle.module.urls(forResourcesWithExtension: "metal", subdirectory: "Shaders")
                ?? Bundle.module.urls(forResourcesWithExtension: "metal", subdirectory: nil)
                ?? []
        }

        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Creates a progressive render session for a scene and settings.
    public func makeSession(
        scene: RenderScene,
        settings: RenderSettings = RenderSettings()
    ) throws -> RenderSession {
        try makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: .automatic
        )
    }

    func makeSession(
        scene: RenderScene,
        settings: RenderSettings = RenderSettings(),
        accelerationMode: RenderAccelerationMode
    ) throws -> RenderSession {
        try RenderSession(
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline,
            hardwareRayTracingPipeline: hardwareRayTracingPipeline,
            simpleSpatialDenoisePipeline: simpleSpatialDenoisePipeline,
            svgfDepthNormalPipeline: svgfDepthNormalPipeline,
            svgfOutputCopyPipeline: svgfOutputCopyPipeline,
            scene: scene,
            settings: settings,
            accelerationMode: accelerationMode
        )
    }
}
