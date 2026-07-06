import Foundation
import Metal
import simd

/// Result of a tiled viewport render step.
public struct RenderTileProgress: Sendable, Equatable {
    public var tile: RenderTile
    public var tileIndex: Int
    public var tileCount: Int
    public var completedSample: Bool
    public var sampleCount: Int
}

/// Live progressive viewport wrapper for applications that edit a scene over time.
///
/// `RenderSession` is a compiled snapshot. `RenderViewport` owns both the editable
/// scene snapshot and the current session, so app integrations can replace render
/// fields, rebuild the session, and restart accumulation through one API.
public final class RenderViewport {
    /// Scene snapshot used to build the current session.
    public private(set) var scene: RenderScene

    /// Settings used to build the current session.
    public private(set) var settings: RenderSettings

    /// Acceleration mode requested for the current session.
    public private(set) var accelerationMode: RenderAccelerationMode

    /// Current compiled progressive render session.
    public private(set) var session: RenderSession

    private let renderer: DenrimRenderer
    private var tilePlan: TilePlan?

    /// Number of samples accumulated by the current session.
    public var sampleCount: Int {
        session.sampleCount
    }

    /// Creates a live viewport from an initial renderable scene.
    public init(
        renderer: DenrimRenderer,
        scene: RenderScene,
        settings: RenderSettings = RenderSettings(),
        accelerationMode: RenderAccelerationMode = .automatic
    ) throws {
        self.renderer = renderer
        self.scene = scene
        self.settings = settings
        self.accelerationMode = accelerationMode
        self.session = try renderer.makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: accelerationMode
        )
    }

    /// Rebuilds the current session from the stored scene/settings snapshot.
    public func rebuildSession() throws {
        session = try makeSession(scene: scene, settings: settings, accelerationMode: accelerationMode)
        resetTilePlan()
    }

    /// Replaces the entire scene and starts a fresh accumulation session.
    public func replaceScene(_ scene: RenderScene) throws {
        let newSession = try makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: accelerationMode
        )
        self.scene = scene
        self.session = newSession
        resetTilePlan()
    }

    /// Replaces render settings and starts a fresh accumulation session.
    public func replaceSettings(
        _ settings: RenderSettings,
        accelerationMode: RenderAccelerationMode? = nil
    ) throws {
        let newAccelerationMode = accelerationMode ?? self.accelerationMode
        let newSession = try makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: newAccelerationMode
        )
        self.settings = settings
        self.accelerationMode = newAccelerationMode
        self.session = newSession
        resetTilePlan()
    }

    /// Adds a render field bundle to the scene and starts a fresh accumulation session.
    @discardableResult
    public func addField(
        _ fieldBundle: RenderFieldBundle,
        transform: Transform = .identity
    ) throws -> RenderFieldID {
        var updatedScene = scene
        let id = updatedScene.add(fieldBundle: fieldBundle, transform: transform)
        let newSession = try makeSession(
            scene: updatedScene,
            settings: settings,
            accelerationMode: accelerationMode
        )
        scene = updatedScene
        session = newSession
        resetTilePlan()
        return id
    }

    /// Replaces a render field bundle and starts a fresh accumulation session.
    ///
    /// Returns `false` when the handle no longer points at a compatible field in
    /// the stored scene. On thrown rebuild errors, the previous scene/session stay
    /// active.
    @discardableResult
    public func replaceField(
        _ id: RenderFieldID,
        with fieldBundle: RenderFieldBundle,
        transform: Transform? = nil
    ) throws -> Bool {
        var updatedScene = scene
        guard updatedScene.replaceField(id, with: fieldBundle, transform: transform) else {
            return false
        }
        let newSession = try makeSession(
            scene: updatedScene,
            settings: settings,
            accelerationMode: accelerationMode
        )
        scene = updatedScene
        session = newSession
        resetTilePlan()
        return true
    }

    /// Replaces a GPU-resident sparse field and refreshes SDF buffers without rebuilding the session.
    ///
    /// This is the topology-changing counterpart to dirty-brick updates. It can
    /// swap brick descriptors, grids, and the resident sample buffer while keeping
    /// the current render targets and render session object alive. Use regular
    /// `replaceField` when the edit also changes meshes, materials, lights,
    /// textures, camera, or other non-field scene state.
    @discardableResult
    public func replaceGPUSparseFieldPreservingSession(
        _ id: RenderFieldID,
        with fieldBundle: RenderFieldBundle,
        transform: Transform? = nil
    ) throws -> Bool {
        guard id.storage == .gpuSparse,
              case .gpuSparse = fieldBundle.storage else {
            return false
        }
        var updatedScene = scene
        guard updatedScene.replaceField(id, with: fieldBundle, transform: transform) else {
            return false
        }
        try session.replaceDistanceFieldResources(from: updatedScene)
        scene = updatedScene
        resetTilePlan()
        return true
    }

    /// Encodes same-topology dirty-brick sample updates for a GPU-resident sparse field.
    ///
    /// The current session is preserved and accumulation is reset. Use `replaceField`
    /// instead when an edit changes brick topology, dimensions, or transforms.
    @discardableResult
    public func encodeUpdateGPUSparseFieldBricks(
        _ id: RenderFieldID,
        updates: [RenderGPUSparseFieldBrickUpdate],
        into commandBuffer: MTLCommandBuffer
    ) throws -> Bool {
        guard id.storage == .gpuSparse,
              scene.gpuSparseVolumeInstances.indices.contains(id.index) else {
            return false
        }
        let resource = scene.gpuSparseVolumeInstances[id.index].resource
        try resource.encodeReplaceBrickSamples(updates, into: commandBuffer)
        session.resetAccumulation()
        resetTilePlan()
        return true
    }

    /// Encodes an in-place direct-grid `DistanceFieldProgram` brick update.
    ///
    /// The field must reference a GPU-resident direct-grid resource produced by
    /// `DistanceFieldBaker.bakeGPUResident(..., metadataMode: .directGridGPU)`.
    /// The current session is preserved and accumulation is reset after encoding.
    @discardableResult
    public func encodeUpdateGPUResidentProgramBricks(
        _ id: RenderFieldID,
        baker: DistanceFieldBaker,
        program: DistanceFieldProgram,
        brickIndices: [Int],
        narrowBand: Float,
        fallbackMaterial: MaterialID? = nil,
        updatesTopology: Bool = true,
        into commandBuffer: MTLCommandBuffer
    ) throws -> Bool {
        guard id.storage == .gpuSparse,
              scene.gpuSparseVolumeInstances.indices.contains(id.index) else {
            return false
        }
        let resource = scene.gpuSparseVolumeInstances[id.index].resource
        try baker.encodeUpdateGPUResidentProgramBricks(
            resource,
            program: program,
            brickIndices: brickIndices,
            narrowBand: narrowBand,
            fallbackMaterial: fallbackMaterial,
            updatesTopology: updatesTopology,
            into: commandBuffer
        )
        session.resetAccumulation()
        resetTilePlan()
        return true
    }

    /// Maps field-local edit bounds to direct-grid brick slots, then encodes an in-place
    /// `DistanceFieldProgram` update for those slots.
    ///
    /// Geometry edits should keep `activeOnly` false. Material/attribute-only edits can set
    /// `activeOnly` true and `updatesTopology` false when the active brick set is unchanged.
    @discardableResult
    public func encodeUpdateGPUResidentProgramBricks(
        _ id: RenderFieldID,
        baker: DistanceFieldBaker,
        program: DistanceFieldProgram,
        overlappingLocalBoundsMin editedBoundsMin: SIMD3<Float>,
        localBoundsMax editedBoundsMax: SIMD3<Float>,
        padding: Float = 0,
        activeOnly: Bool = false,
        narrowBand: Float,
        fallbackMaterial: MaterialID? = nil,
        updatesTopology: Bool = true,
        into commandBuffer: MTLCommandBuffer
    ) throws -> Bool {
        guard id.storage == .gpuSparse,
              scene.gpuSparseVolumeInstances.indices.contains(id.index) else {
            return false
        }
        let resource = scene.gpuSparseVolumeInstances[id.index].resource
        let brickIndices = try resource.directGridBrickIndices(
            overlappingLocalBoundsMin: editedBoundsMin,
            localBoundsMax: editedBoundsMax,
            padding: padding,
            activeOnly: activeOnly
        )
        guard !brickIndices.isEmpty else {
            return true
        }
        try baker.encodeUpdateGPUResidentProgramBricks(
            resource,
            program: program,
            brickIndices: brickIndices,
            narrowBand: narrowBand,
            fallbackMaterial: fallbackMaterial,
            updatesTopology: updatesTopology,
            into: commandBuffer
        )
        session.resetAccumulation()
        resetTilePlan()
        return true
    }

    /// Converts world-space edit bounds through the field instance transform, then encodes an
    /// in-place direct-grid `DistanceFieldProgram` update for the overlapping brick slots.
    /// `padding` is applied in world units before transforming the bounds.
    @discardableResult
    public func encodeUpdateGPUResidentProgramBricks(
        _ id: RenderFieldID,
        baker: DistanceFieldBaker,
        program: DistanceFieldProgram,
        overlappingWorldBoundsMin editedWorldBoundsMin: SIMD3<Float>,
        worldBoundsMax editedWorldBoundsMax: SIMD3<Float>,
        padding: Float = 0,
        activeOnly: Bool = false,
        narrowBand: Float,
        fallbackMaterial: MaterialID? = nil,
        updatesTopology: Bool = true,
        into commandBuffer: MTLCommandBuffer
    ) throws -> Bool {
        guard id.storage == .gpuSparse,
              scene.gpuSparseVolumeInstances.indices.contains(id.index) else {
            return false
        }
        let instance = scene.gpuSparseVolumeInstances[id.index]
        let localBounds = Self.localBounds(
            enclosingWorldBoundsMin: editedWorldBoundsMin,
            worldBoundsMax: editedWorldBoundsMax,
            padding: padding,
            transform: instance.transform
        )
        return try encodeUpdateGPUResidentProgramBricks(
            id,
            baker: baker,
            program: program,
            overlappingLocalBoundsMin: localBounds.min,
            localBoundsMax: localBounds.max,
            padding: 0,
            activeOnly: activeOnly,
            narrowBand: narrowBand,
            fallbackMaterial: fallbackMaterial,
            updatesTopology: updatesTopology,
            into: commandBuffer
        )
    }

    /// Resets progressive accumulation on the current session.
    public func resetAccumulation() {
        session.resetAccumulation()
        resetTilePlan()
    }

    /// Renders one additional progressive sample synchronously.
    public func renderNextSample() throws {
        try session.renderNextSample()
        resetTilePlan()
    }

    /// Encodes one additional progressive sample into an application-owned command buffer.
    public func encodeNextSample(into commandBuffer: MTLCommandBuffer) throws {
        try session.encodeNextSample(into: commandBuffer)
        resetTilePlan()
    }

    /// Renders the next spiral-ordered tile synchronously.
    ///
    /// The session's `sampleCount` advances only after the last tile in the current
    /// sweep has rendered. Use this for UI-driven viewports that want bounded work
    /// per frame, e.g. one tile per display refresh.
    @discardableResult
    public func renderNextTile(
        tileWidth: Int = 128,
        tileHeight: Int = 128
    ) throws -> RenderTileProgress {
        let step = nextTileStep(tileWidth: tileWidth, tileHeight: tileHeight)
        try session.renderNextTile(step.tile, completesSample: step.completedSample)
        return RenderTileProgress(
            tile: step.tile,
            tileIndex: step.tileIndex,
            tileCount: step.tileCount,
            completedSample: step.completedSample,
            sampleCount: session.sampleCount
        )
    }

    /// Encodes the next spiral-ordered tile into an application-owned command buffer.
    @discardableResult
    public func encodeNextTile(
        tileWidth: Int = 128,
        tileHeight: Int = 128,
        into commandBuffer: MTLCommandBuffer
    ) throws -> RenderTileProgress {
        let step = nextTileStep(tileWidth: tileWidth, tileHeight: tileHeight)
        try session.encodeNextTile(step.tile, completesSample: step.completedSample, into: commandBuffer)
        return RenderTileProgress(
            tile: step.tile,
            tileIndex: step.tileIndex,
            tileCount: step.tileCount,
            completedSample: step.completedSample,
            sampleCount: session.sampleCount
        )
    }

    /// Renders a fixed number of additional samples synchronously.
    public func render(samples: Int) throws {
        try session.render(samples: samples)
        resetTilePlan()
    }

    /// Returns the current Metal texture for a render output.
    public func metalTexture(for output: RenderOutput = .beauty) throws -> MTLTexture {
        try session.metalTexture(for: output)
    }

    /// Returns the current raw Metal texture without encoding hidden renderer work.
    public func liveMetalTexture(for output: RenderOutput = .beauty) -> MTLTexture {
        session.liveMetalTexture(for: output)
    }

    /// Reads a render output back as floating-point RGBA pixels.
    public func pixels(for output: RenderOutput) throws -> [RenderOutputPixel] {
        try session.pixels(for: output)
    }

    private func makeSession(
        scene: RenderScene,
        settings: RenderSettings,
        accelerationMode: RenderAccelerationMode
    ) throws -> RenderSession {
        try renderer.makeSession(
            scene: scene,
            settings: settings,
            accelerationMode: accelerationMode
        )
    }

    private func resetTilePlan() {
        tilePlan = nil
    }

    private static func localBounds(
        enclosingWorldBoundsMin worldBoundsMin: SIMD3<Float>,
        worldBoundsMax: SIMD3<Float>,
        padding: Float,
        transform: Transform
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        let padding = max(padding, 0)
        let minWorld = simd_min(worldBoundsMin, worldBoundsMax) - SIMD3<Float>(repeating: padding)
        let maxWorld = simd_max(worldBoundsMin, worldBoundsMax) + SIMD3<Float>(repeating: padding)
        let worldToLocal = Transform(matrix: transform.matrix.inverse)
        var localMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var localMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for z in 0..<2 {
            for y in 0..<2 {
                for x in 0..<2 {
                    let corner = SIMD3<Float>(
                        x == 0 ? minWorld.x : maxWorld.x,
                        y == 0 ? minWorld.y : maxWorld.y,
                        z == 0 ? minWorld.z : maxWorld.z
                    )
                    let local = worldToLocal.transformPoint(corner)
                    localMin = simd_min(localMin, local)
                    localMax = simd_max(localMax, local)
                }
            }
        }
        return (localMin, localMax)
    }

    private func nextTileStep(tileWidth: Int, tileHeight: Int) -> (
        tile: RenderTile,
        tileIndex: Int,
        tileCount: Int,
        completedSample: Bool
    ) {
        let normalizedWidth = max(tileWidth, 1)
        let normalizedHeight = max(tileHeight, 1)
        if tilePlan?.matches(
            width: settings.width,
            height: settings.height,
            tileWidth: normalizedWidth,
            tileHeight: normalizedHeight
        ) != true {
            tilePlan = TilePlan(
                imageWidth: settings.width,
                imageHeight: settings.height,
                tileWidth: normalizedWidth,
                tileHeight: normalizedHeight
            )
        }
        guard var plan = tilePlan, !plan.tiles.isEmpty else {
            let tile = RenderTile(x: 0, y: 0, width: settings.width, height: settings.height)
            return (tile, 0, 1, true)
        }
        let tileIndex = plan.nextIndex
        let tile = plan.tiles[tileIndex]
        let completedSample = tileIndex == plan.tiles.count - 1
        plan.nextIndex = completedSample ? 0 : tileIndex + 1
        tilePlan = plan
        return (tile, tileIndex, plan.tiles.count, completedSample)
    }

    private struct TilePlan: Equatable {
        var imageWidth: Int
        var imageHeight: Int
        var tileWidth: Int
        var tileHeight: Int
        var tiles: [RenderTile]
        var nextIndex: Int = 0

        init(imageWidth: Int, imageHeight: Int, tileWidth: Int, tileHeight: Int) {
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
            self.tiles = Self.spiralTiles(
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                tileWidth: tileWidth,
                tileHeight: tileHeight
            )
        }

        func matches(width: Int, height: Int, tileWidth: Int, tileHeight: Int) -> Bool {
            imageWidth == width
                && imageHeight == height
                && self.tileWidth == tileWidth
                && self.tileHeight == tileHeight
        }

        private static func spiralTiles(
            imageWidth: Int,
            imageHeight: Int,
            tileWidth: Int,
            tileHeight: Int
        ) -> [RenderTile] {
            guard imageWidth > 0, imageHeight > 0 else {
                return []
            }
            let columns = (imageWidth + tileWidth - 1) / tileWidth
            let rows = (imageHeight + tileHeight - 1) / tileHeight
            let centerX = (columns - 1) / 2
            let centerY = (rows - 1) / 2
            var cells: [(x: Int, y: Int)] = []
            var visited = Set<Int>()

            func appendIfValid(_ x: Int, _ y: Int) {
                guard x >= 0, y >= 0, x < columns, y < rows else {
                    return
                }
                let key = x + y * columns
                guard visited.insert(key).inserted else {
                    return
                }
                cells.append((x, y))
            }

            var x = centerX
            var y = centerY
            appendIfValid(x, y)
            var stepLength = 1
            while cells.count < columns * rows {
                for _ in 0..<stepLength {
                    x += 1
                    appendIfValid(x, y)
                }
                for _ in 0..<stepLength {
                    y += 1
                    appendIfValid(x, y)
                }
                stepLength += 1
                for _ in 0..<stepLength {
                    x -= 1
                    appendIfValid(x, y)
                }
                for _ in 0..<stepLength {
                    y -= 1
                    appendIfValid(x, y)
                }
                stepLength += 1
            }

            return cells.map { cell in
                let x = cell.x * tileWidth
                let y = cell.y * tileHeight
                return RenderTile(
                    x: x,
                    y: y,
                    width: min(tileWidth, imageWidth - x),
                    height: min(tileHeight, imageHeight - y)
                )
            }
        }
    }
}
