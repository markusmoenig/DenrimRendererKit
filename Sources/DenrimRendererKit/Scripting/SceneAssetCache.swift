import Foundation

/// Reuses decoded scene assets across SceneScript parses.
///
/// `SceneAssetCache` is intended for interactive products that repeatedly load
/// the same script while changing camera, material, or render settings. It keeps
/// decoded meshes and image textures in CPU memory.
public final class SceneAssetCache: @unchecked Sendable {
    private struct MeshKey: Hashable {
        var path: String
        var flipsV: Bool
    }

    private struct TextureKey: Hashable {
        var path: String
        var colorEncoding: TextureColorEncoding
        var samplingMode: TextureSamplingMode
    }

    private let lock = NSLock()
    private var meshes: [MeshKey: Mesh] = [:]
    private var textures: [TextureKey: Texture2D] = [:]

    public init() {}

    /// Removes all cached assets.
    public func removeAll() {
        lock.lock()
        meshes.removeAll(keepingCapacity: true)
        textures.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func mesh(contentsOf url: URL, flipsV: Bool) throws -> Mesh {
        let key = MeshKey(path: cachePath(for: url), flipsV: flipsV)

        lock.lock()
        if let mesh = meshes[key] {
            lock.unlock()
            return mesh
        }
        lock.unlock()

        var mesh = try Mesh(contentsOf: url)
        if flipsV {
            mesh.flipTexcoordV()
        }

        lock.lock()
        if let existing = meshes[key] {
            lock.unlock()
            return existing
        }
        meshes[key] = mesh
        lock.unlock()
        return mesh
    }

    func texture(
        contentsOf url: URL,
        colorEncoding: TextureColorEncoding,
        samplingMode: TextureSamplingMode
    ) throws -> Texture2D {
        let key = TextureKey(
            path: cachePath(for: url),
            colorEncoding: colorEncoding,
            samplingMode: samplingMode
        )

        lock.lock()
        if let texture = textures[key] {
            lock.unlock()
            return texture
        }
        lock.unlock()

        let texture = try Texture2D(
            contentsOf: url,
            colorEncoding: colorEncoding,
            samplingMode: samplingMode
        )

        lock.lock()
        if let existing = textures[key] {
            lock.unlock()
            return existing
        }
        textures[key] = texture
        lock.unlock()
        return texture
    }

    private func cachePath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

extension Mesh {
    mutating func flipTexcoordV() {
        texcoords = texcoords.map { SIMD2<Float>($0.x, 1 - $0.y) }
    }
}
