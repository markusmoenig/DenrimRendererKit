import PackagePlugin

@main
struct MetalLibraryPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard target.name == "DenrimRendererKit" else {
            return []
        }

        let shaderDirectory = target.directoryURL
            .appending(path: "Resources", directoryHint: .isDirectory)
            .appending(path: "Shaders", directoryHint: .isDirectory)
        let shaderNames = [
            "Denoise.metal",
            "MetalRayTracingProbe.metal",
            "PathTrace.metal",
            "SDFBake.metal"
        ]
        let shaderURLs = shaderNames.map {
            shaderDirectory.appending(path: $0, directoryHint: .notDirectory)
        }
        let outputDirectory = context.pluginWorkDirectoryURL
        let metallibOutput = outputDirectory.appending(path: "DenrimRendererKit.metallib")
        let generator = try context.tool(named: "MetalLibraryGenerator")

        return [
            .buildCommand(
                displayName: "Compile DenrimRendererKit Metal shaders",
                executable: generator.url,
                arguments: [
                    metallibOutput.path()
                ] + shaderURLs.map { $0.path() },
                inputFiles: shaderURLs,
                outputFiles: [
                    metallibOutput
                ]
            )
        ]
    }
}
