import Testing
import Metal
import Foundation
import Ollin
@testable import OllinSyphon
import CSyphon
import OllinTestSupport

/// Syphon has no wire format we author (it's IOSurface + Mach under the hood), so
/// the testable surface is thin. These exercise the receive side — discovery and
/// the `SyphonClient` → texture-backed `Image` bridge — against a publisher the
/// test stands up itself with the vendored `SyphonMetalServer`.
///
/// The loopback needs a Metal device, so it's gated to skip on a GPU-less box.
/// Discovery is asynchronous (Mach/distributed notifications) and not guaranteed
/// in every sandbox, so a probe publishes once and looks for itself, and the
/// loopback refuses itself where the source never surfaces; the missing-source
/// test is the always-on guard. Run on a real Mac it goes end to end.
@MainActor
@Suite struct SyphonLoopbackTests {

    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Whether a published source surfaces in discovery here, asked once: a
    /// server under a unique name publishes one frame, and the client's listing
    /// is polled for it.
    static let announcementsSurface = Task<Bool, Never> { @MainActor in
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(), let commandBuffer = queue.makeCommandBuffer() else { return false }
        let name = "Ollin Probe \(UUID().uuidString.prefix(8))"
        let server = SyphonMetalServer(name: name, device: device, options: nil)
        defer { server.stop() }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 8, height: 8, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return false }
        server.publishFrameTexture(texture, on: commandBuffer,
                                   imageRegion: NSRect(x: 0, y: 0, width: 8, height: 8), flipped: false)
        commandBuffer.commit()
        await commandBuffer.completed()
        return (try? await waitFor(timeout: 4, { SyphonClient.availableServers().first { $0.name == name } })) != nil
    }

    static let discoveryTrait: ConditionTrait = .enabled("a published source does not surface in discovery here") {
        await SyphonLoopbackTests.announcementsSurface.value
    }

    /// A source that is not there is said, not swallowed: the client stands
    /// unconnected with a sentence naming what it looked for.
    @Test func aMissingSourceSaysSo() {
        let client = SyphonClient(named: "ollin-no-such-source", appName: "ollin-no-such-app")
        #expect(!client.isConnected)
        #expect(client.frame == nil)
        let reason = client.unavailableReason ?? ""
        #expect(reason.contains("ollin-no-such-source") && reason.contains("ollin-no-such-app"), Comment(rawValue: reason))
    }

    @Test(.enabled(if: SyphonLoopbackTests.hasMetal), discoveryTrait)
    func publishedSourceIsDiscoveredAndDelivered() async throws {
        let device = MTLCreateSystemDefaultDevice()!
        let name = "Ollin Test \(UUID().uuidString.prefix(8))"
        let server = SyphonMetalServer(name: name, device: device, options: nil)
        defer { server.stop() }

        let queue = device.makeCommandQueue()!
        let size = 64
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let texture = device.makeTexture(descriptor: desc)!

        func publishOnce() {
            guard let commandBuffer = queue.makeCommandBuffer() else { return }
            server.publishFrameTexture(texture, on: commandBuffer,
                                       imageRegion: NSRect(x: 0, y: 0, width: size, height: size),
                                       flipped: false)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        publishOnce()

        // The probe saw its own source surface, so this one has to.
        _ = try await waitFor(timeout: 4, { SyphonClient.availableServers().first { $0.name == name } })

        let client = SyphonClient(named: name)
        defer { client.disconnect() }
        #expect((try? await waitFor(timeout: 4, { client.isConnected ? true : nil })) == true)

        // Keep publishing and confirm a frame comes back as an Image of the right size.
        let frame = try? await waitFor(timeout: 4) { () -> Image? in
            publishOnce()
            return client.frame
        }
        #expect(frame != nil)
        #expect(frame?.width == size)
        #expect(frame?.height == size)
    }
}
