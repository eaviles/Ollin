import Foundation
import Metal
import Testing
import Ollin
@testable import OllinSyphon

/// A stopped server stays stopped.
///
/// The server is an extension that asks for every rendered frame, and the next
/// frame after `stop()` used to stand the Syphon server back up and turn
/// `isPublishing` true again, so a sketch could not take its frames off the
/// network without dropping the extension itself.
@Suite
@MainActor
struct SyphonServerStopTests {

    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    @Test(.enabled(if: SyphonServerStopTests.hasMetal))
    func aStoppedServerStaysStoppedThroughARenderedFrame() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 16, height: 16, mipmapped: false)
        description.usage = [.renderTarget, .shaderRead, .pixelFormatView]
        description.storageMode = .private
        let texture = try #require(device.makeTexture(descriptor: description))
        let sketch = Sketch()
        let server = SyphonServer(name: "Ollin Test Stop \(UUID().uuidString.prefix(8))")
        defer { server.stop() }

        #expect(server.wantsRenderedTexture)
        server.frameRendered(sketch, texture: texture)
        #expect(server.isPublishing)

        server.stop()
        #expect(!server.isPublishing)
        #expect(server.phase == .stopped)
        // The runner reads this each frame; a stopped server asks for nothing.
        #expect(!server.wantsRenderedTexture)
        // A frame that arrives anyway is refused rather than published.
        server.frameRendered(sketch, texture: texture)
        #expect(!server.isPublishing)
        #expect(server.phase == .stopped)
    }
}
