import Foundation
import Metal
import Ollin
import CSyphon

/// Publishes a sketch's rendered frames as a **Syphon source**, so any other
/// Syphon-capable app on the Mac can read its live visuals in real time. It's a
/// `Sketch` extension: register one in `setup()` and every frame is shared automatically.
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

        // Publish the frame's bytes verbatim. Ollin renders into an sRGB target, so
        // its bytes are already sRGB-encoded display pixels — what the Syphon
        // ecosystem exchanges. But Syphon's server samples the source texture, and a
        // sRGB-tagged texture would be decoded to linear (washing the colors out), so
        // hand it a non-sRGB *view* of the same bytes: sampled raw, stored raw.
        let publishTexture = texture.makeTextureView(pixelFormat: .bgra8Unorm) ?? texture
        let region = NSRect(x: 0, y: 0, width: publishTexture.width, height: publishTexture.height)
        // `flipped: true` — Ollin's render target is top-left origin, which Syphon
        // treats as vertically flipped relative to its GL/bottom-left convention.
        // Passing true makes standard Syphon consumers show the frame upright;
        // Ollin's own SyphonClient flips back
        // on its side (Image(texture:flippedVertically:)), so the loopback and
        // viewing a standard source both land upright too.
        server.publishFrameTexture(publishTexture, on: commandBuffer,
                                   imageRegion: region, flipped: true)
        commandBuffer.commit()
        // The renderer hands out a texture it reuses in place, re-rendering into
        // it next frame on its own command queue. Metal's hazard tracking doesn't
        // span queues, so wait for Syphon's copy to finish before returning, or
        // the next frame's overwrite could race this read. The blit is small and
        // this already runs on the render loop.
        commandBuffer.waitUntilCompleted()
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
