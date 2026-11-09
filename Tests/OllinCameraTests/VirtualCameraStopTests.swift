import Foundation
import Metal
import Testing
import Ollin
@testable import OllinCamera

/// A stopped server stays stopped, and goes looking for no camera.
///
/// The server retries its connection to the camera from every rendered frame,
/// and after `stop()` the next frame used to reconnect and publish again, so
/// a sketch could not stop feeding the camera without dropping the extension.
@Suite
@MainActor
struct VirtualCameraStopTests {

    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    @Test func aStoppedServerAsksForNoFrame() {
        let server = VirtualCameraServer(deviceName: "Ollin Nowhere \(UUID().uuidString.prefix(8))")
        #expect(server.wantsRenderedTexture)
        #expect(server.phase == .waiting)
        server.stop()
        #expect(server.phase == .stopped)
        #expect(!server.isPublishing)
        #expect(!server.wantsRenderedTexture)
    }

    @Test(.enabled(if: VirtualCameraStopTests.hasMetal))
    func aFrameAfterStopIsRefusedWithoutLookingForTheCamera() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 16, height: 16, mipmapped: false)
        description.usage = [.renderTarget, .shaderRead]
        let texture = try #require(device.makeTexture(descriptor: description))
        let server = VirtualCameraServer(deviceName: "Ollin Nowhere \(UUID().uuidString.prefix(8))")
        server.stop()
        server.frameRendered(Sketch(), texture: texture)
        // No connection was attempted, so there is nothing to be unavailable.
        #expect(server.unavailableReason == nil)
        #expect(!server.isPublishing)
        #expect(server.phase == .stopped)
    }
}
