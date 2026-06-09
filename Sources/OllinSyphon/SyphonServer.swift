import Foundation
import Metal
import Ollin
import CSyphon

/// Publishes a sketch's rendered frames as a **Syphon source**, so other apps on
/// the Mac can read its live visuals — openFrameworks (via `ofxSyphon`),
/// Resolume, MadMapper, VDMX, or Syphon's own Simple Client. It's a `Sketch`
/// extension: register one in `setup()` and every frame is shared automatically.
///
/// ```swift
/// final class Visuals: Sketch {
///     override func setup() {
///         publishSyphon(name: "Ollin")        // or: extend(SyphonServer(name: "Ollin"))
///     }
///     override func draw() { /* draw as usual */ }
/// }
/// ```
///
/// The frame is taken straight from the GPU (no CPU round-trip): Ollin re-renders
/// it off-screen into a texture and hands it here through the rendered-texture
/// seam, which only runs while something is sharing. Sharing happens on the
/// sketch's own Metal device, which is what every consumer on a single-GPU Mac
/// expects.
public final class SyphonServer: SketchExtension {

    /// The human-readable name the server announces (paired with the host app's
    /// name by consumers). Not required to be unique.
    public let name: String

    /// The underlying Syphon server, created lazily on the first shared frame
    /// (when the Metal device is known) and released on `stop()`.
    private var server: SyphonMetalServer?
    /// A command queue for Syphon's publish commands, on the sketch's device.
    private var queue: MTLCommandQueue?

    /// `true` once at least one frame has been published.
    public private(set) var isPublishing = false

    /// Create a server that will publish under `name` (default `"Ollin"`).
    public init(name: String = "Ollin") {
        self.name = name
    }

    /// Whether any client is currently reading this source. Frames are published
    /// every frame regardless; this just lets a sketch skip its own expensive work
    /// when nobody's watching.
    public var hasClients: Bool { server?.hasClients ?? false }

    /// Stop announcing the source and release the Syphon server. Optional —
    /// dropping all references to this extension has the same effect.
    public func stop() {
        server?.stop()
        server = nil
        isPublishing = false
    }

    // MARK: SketchExtension

    /// Always wants the rendered frame as a texture — that's what gets published.
    public var wantsRenderedTexture: Bool { true }

    /// Publish each rendered frame. Runs on the main actor (the render loop),
    /// right after the frame is drawn.
    public func frameRendered(_ sketch: Sketch, texture: MTLTexture) {
        if server == nil {
            // First frame: stand up the server on the sketch's own device.
            queue = texture.device.makeCommandQueue()
            server = SyphonMetalServer(name: name, device: texture.device, options: nil)
        }
        guard let server, let queue, let commandBuffer = queue.makeCommandBuffer() else { return }

        let region = NSRect(x: 0, y: 0, width: texture.width, height: texture.height)
        // `flipped: false` — Ollin's render target is a normal top-left-origin
        // Metal texture, i.e. not vertically flipped in Metal coordinates.
        server.publishFrameTexture(texture, on: commandBuffer,
                                   imageRegion: region, flipped: false)
        commandBuffer.commit()
        isPublishing = true
    }
}

extension Sketch {
    /// Start sharing this sketch's frames as a Syphon source named `name`
    /// (default `"Ollin"`). Sugar for building a ``SyphonServer`` and registering
    /// it; returns it so you can query `hasClients`. Call in `setup()`.
    @discardableResult
    public func publishSyphon(name: String = "Ollin") -> SyphonServer {
        let server = SyphonServer(name: name)
        extend(server)
        return server
    }
}
