import Foundation
import Metal

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
        return true
    }

    /// Resets progressive accumulation on the current session.
    public func resetAccumulation() {
        session.resetAccumulation()
    }

    /// Renders one additional progressive sample synchronously.
    public func renderNextSample() throws {
        try session.renderNextSample()
    }

    /// Encodes one additional progressive sample into an application-owned command buffer.
    public func encodeNextSample(into commandBuffer: MTLCommandBuffer) throws {
        try session.encodeNextSample(into: commandBuffer)
    }

    /// Renders a fixed number of additional samples synchronously.
    public func render(samples: Int) throws {
        try session.render(samples: samples)
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
}
