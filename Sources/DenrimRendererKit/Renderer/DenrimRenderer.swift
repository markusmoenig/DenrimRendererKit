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
    private let library: MTLLibrary
    private var cachedFlatPreviewPipeline: MTLComputePipelineState?
    private var cachedInteractivePipeline: MTLComputePipelineState?
    private var cachedPathTracePipeline: MTLComputePipelineState?
    private var cachedHardwareRayTracingPipeline: MTLComputePipelineState?
    private var cachedSimpleSpatialDenoisePipeline: MTLComputePipelineState?
    private var cachedSVGFDepthNormalPipeline: MTLComputePipelineState?
    private var cachedSVGFOutputCopyPipeline: MTLComputePipelineState?
    private var cachedDistanceFieldBakePipeline: MTLComputePipelineState?
    private var cachedSparseDistanceFieldClassifyPipeline: MTLComputePipelineState?
    private var cachedSparseDistanceFieldBakePipeline: MTLComputePipelineState?
    private var cachedSparseDistanceFieldDirectGridBakePipeline: MTLComputePipelineState?
    private var cachedSparseDistanceFieldMacroGridPipeline: MTLComputePipelineState?
    private var cachedSparseDistanceFieldProgramDirectGridBakePipeline: MTLComputePipelineState?
    private var cachedSparseDistanceFieldProgramDirectGridSelectedBakePipeline: MTLComputePipelineState?
    private let pipelineLock = NSLock()

    /// Creates a renderer using the supplied Metal device or the system default device.
    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else {
            throw DenrimRendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw DenrimRendererError.noMetalDevice
        }

        self.device = device
        self.commandQueue = commandQueue
        self.library = try Self.makeLibrary(device: device)
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let metallibURL = Bundle.module.url(
            forResource: "DenrimRendererKit",
            withExtension: "metallib"
        ),
           let library = try? device.makeLibrary(URL: metallibURL),
           library.makeFunction(name: "flatPreviewKernel") != nil,
           library.makeFunction(name: "interactiveMaterialKernel") != nil,
           library.makeFunction(name: "pathTraceKernel") != nil,
           library.makeFunction(name: "simpleSpatialDenoiseKernel") != nil,
           library.makeFunction(name: "packSVGFDepthNormalKernel") != nil,
           library.makeFunction(name: "copySVGFOutputKernel") != nil,
           library.makeFunction(name: "sdfBakeKernel") != nil,
           library.makeFunction(name: "sdfSparseClassifyKernel") != nil,
           library.makeFunction(name: "sdfSparseBakeKernel") != nil,
           library.makeFunction(name: "sdfSparseDirectGridBakeKernel") != nil,
           library.makeFunction(name: "sdfSparseBuildMacroGridKernel") != nil,
           library.makeFunction(name: "sdfProgramSparseDirectGridBakeKernel") != nil,
           library.makeFunction(name: "sdfProgramSparseDirectGridBakeSelectedKernel") != nil {
            return library
        }

        if let library = try? device.makeDefaultLibrary(bundle: .module),
           library.makeFunction(name: "flatPreviewKernel") != nil,
           library.makeFunction(name: "interactiveMaterialKernel") != nil,
           library.makeFunction(name: "pathTraceKernel") != nil,
           library.makeFunction(name: "simpleSpatialDenoiseKernel") != nil,
           library.makeFunction(name: "packSVGFDepthNormalKernel") != nil,
           library.makeFunction(name: "copySVGFOutputKernel") != nil,
           library.makeFunction(name: "sdfBakeKernel") != nil,
           library.makeFunction(name: "sdfSparseClassifyKernel") != nil,
           library.makeFunction(name: "sdfSparseBakeKernel") != nil,
           library.makeFunction(name: "sdfSparseDirectGridBakeKernel") != nil,
           library.makeFunction(name: "sdfSparseBuildMacroGridKernel") != nil,
           library.makeFunction(name: "sdfProgramSparseDirectGridBakeKernel") != nil,
           library.makeFunction(name: "sdfProgramSparseDirectGridBakeSelectedKernel") != nil {
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
        let names = ["Denoise", "PathTrace", "SDFBake"]
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

    private func optionalPipeline(
        named functionName: String,
        cache keyPath: ReferenceWritableKeyPath<DenrimRenderer, MTLComputePipelineState?>
    ) throws -> MTLComputePipelineState? {
        pipelineLock.lock()
        defer {
            pipelineLock.unlock()
        }
        if let cached = self[keyPath: keyPath] {
            return cached
        }
        guard let function = library.makeFunction(name: functionName) else {
            return nil
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        self[keyPath: keyPath] = pipeline
        return pipeline
    }

    private func requiredPipeline(
        named functionName: String,
        cache keyPath: ReferenceWritableKeyPath<DenrimRenderer, MTLComputePipelineState?>
    ) throws -> MTLComputePipelineState {
        pipelineLock.lock()
        defer {
            pipelineLock.unlock()
        }
        if let cached = self[keyPath: keyPath] {
            return cached
        }
        guard let function = library.makeFunction(name: functionName) else {
            throw DenrimRendererError.missingShaderFunction(functionName)
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        self[keyPath: keyPath] = pipeline
        return pipeline
    }

    private func hardwarePipelineIfNeeded(
        scene: RenderScene,
        accelerationMode: RenderAccelerationMode
    ) throws -> MTLComputePipelineState? {
        guard device.supportsRaytracing,
              accelerationMode != .flatBVH,
              scene.volumeInstances.isEmpty,
              scene.sparseVolumeInstances.isEmpty,
              scene.gpuSparseVolumeInstances.isEmpty else {
            return nil
        }
        return try optionalPipeline(
            named: "pathTraceHardwareKernel",
            cache: \.cachedHardwareRayTracingPipeline
        )
    }

    private func primaryPipeline(for settings: RenderSettings) throws -> MTLComputePipelineState {
        switch settings.quality {
        case .preview:
            return try requiredPipeline(
                named: "flatPreviewKernel",
                cache: \.cachedFlatPreviewPipeline
            )
        case .interactive:
            return try requiredPipeline(
                named: "interactiveMaterialKernel",
                cache: \.cachedInteractivePipeline
            )
        case .final:
            return try requiredPipeline(
                named: "pathTraceKernel",
                cache: \.cachedPathTracePipeline
            )
        }
    }

    private func denoisePipelines(
        for settings: RenderSettings
    ) throws -> (
        simpleSpatial: MTLComputePipelineState?,
        svgfDepthNormal: MTLComputePipelineState?,
        svgfOutputCopy: MTLComputePipelineState?
    ) {
        switch settings.denoise.denoiser {
        case .none:
            return (nil, nil, nil)
        case .simpleSpatial:
            return (
                try optionalPipeline(
                    named: "simpleSpatialDenoiseKernel",
                    cache: \.cachedSimpleSpatialDenoisePipeline
                ),
                nil,
                nil
            )
        case .appleSVGF:
            return (
                nil,
                try optionalPipeline(
                    named: "packSVGFDepthNormalKernel",
                    cache: \.cachedSVGFDepthNormalPipeline
                ),
                try optionalPipeline(
                    named: "copySVGFOutputKernel",
                    cache: \.cachedSVGFOutputCopyPipeline
                )
            )
        }
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

    /// Creates a progressive render session while requesting a specific acceleration backend.
    ///
    /// This is primarily intended for diagnostics, benchmarks, and backend parity checks.
    /// Application integrations should usually call `makeSession(scene:settings:)` and use
    /// automatic backend selection.
    public func makeSession(
        scene: RenderScene,
        settings: RenderSettings = RenderSettings(),
        accelerationMode: RenderAccelerationMode
    ) throws -> RenderSession {
        let denoisePipelines = try denoisePipelines(for: settings)
        return try RenderSession(
            device: device,
            commandQueue: commandQueue,
            pipeline: try primaryPipeline(for: settings),
            hardwareRayTracingPipeline: settings.quality == .final
                ? try hardwarePipelineIfNeeded(
                    scene: scene,
                    accelerationMode: accelerationMode
                )
                : nil,
            simpleSpatialDenoisePipeline: denoisePipelines.simpleSpatial,
            svgfDepthNormalPipeline: denoisePipelines.svgfDepthNormal,
            svgfOutputCopyPipeline: denoisePipelines.svgfOutputCopy,
            scene: scene,
            settings: settings,
            accelerationMode: accelerationMode
        )
    }

    /// Creates a live progressive viewport that owns a scene snapshot and session.
    ///
    /// Use this for interactive integrations that need to rebuild the session and
    /// restart accumulation when fields, settings, or the scene change.
    public func makeViewport(
        scene: RenderScene,
        settings: RenderSettings = RenderSettings(),
        accelerationMode: RenderAccelerationMode = .automatic
    ) throws -> RenderViewport {
        try RenderViewport(
            renderer: self,
            scene: scene,
            settings: settings,
            accelerationMode: accelerationMode
        )
    }

    /// Creates a distance-field baker backed by this renderer's Metal device.
    ///
    /// The baker is the shared API for SceneScript and procedural products such
    /// as Denrim Form. It currently uses Metal for supported primitive graphs
    /// and falls back to the CPU reference baker for unsupported graph features.
    public func makeDistanceFieldBaker(
        preferredBackend: DistanceFieldBakeBackend = .automatic
    ) -> DistanceFieldBaker {
        DistanceFieldBaker(
            preferredBackend: preferredBackend,
            device: device,
            commandQueue: commandQueue,
            pipeline: try? optionalPipeline(
                named: "sdfBakeKernel",
                cache: \.cachedDistanceFieldBakePipeline
            ),
            sparseClassifyPipeline: try? optionalPipeline(
                named: "sdfSparseClassifyKernel",
                cache: \.cachedSparseDistanceFieldClassifyPipeline
            ),
            sparseBakePipeline: try? optionalPipeline(
                named: "sdfSparseBakeKernel",
                cache: \.cachedSparseDistanceFieldBakePipeline
            ),
            sparseDirectGridBakePipeline: try? optionalPipeline(
                named: "sdfSparseDirectGridBakeKernel",
                cache: \.cachedSparseDistanceFieldDirectGridBakePipeline
            ),
            sparseMacroGridPipeline: try? optionalPipeline(
                named: "sdfSparseBuildMacroGridKernel",
                cache: \.cachedSparseDistanceFieldMacroGridPipeline
            ),
            sparseProgramDirectGridBakePipeline: try? optionalPipeline(
                named: "sdfProgramSparseDirectGridBakeKernel",
                cache: \.cachedSparseDistanceFieldProgramDirectGridBakePipeline
            ),
            sparseProgramDirectGridSelectedBakePipeline: try? optionalPipeline(
                named: "sdfProgramSparseDirectGridBakeSelectedKernel",
                cache: \.cachedSparseDistanceFieldProgramDirectGridSelectedBakePipeline
            )
        )
    }
}
