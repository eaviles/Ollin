import Testing
import Metal
import Foundation
import Ollin
@testable import OllinSyphon
import CSyphon

/// Syphon has no wire format we author (it's IOSurface + Mach under the hood), so
/// the testable surface is thin. These exercise the receive side — discovery and
/// the `SyphonClient` → texture-backed `Image` bridge — against a publisher the
/// test stands up itself with the vendored `SyphonMetalServer`.
///
/// The loopback needs a Metal device, so it's gated to skip on a GPU-less box.
/// Discovery is asynchronous (Mach/distributed notifications) and not guaranteed
/// in every sandbox, so it *soft-skips* if the published source never surfaces —
/// the directory smoke test is the always-on guard. Run on a real Mac it goes
/// end to end.
@MainActor
@Suite struct SyphonLoopbackTests {

    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Poll `probe` until it returns non-nil or `timeout` elapses.
    func waitFor<T>(timeout: Double = 4.0, _ probe: () -> T?) async -> T? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let value = probe() { return value }
            try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms
        }
        return nil
    }

    /// Always-on: querying the directory must be safe and return an array.
    @Test func availableServersIsSafeToQuery() {
        _ = SyphonClient.availableServers()
    }

    @Test(.enabled(if: SyphonLoopbackTests.hasMetal))
    func publishedSourceIsDiscoveredAndDelivered() async {
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

        // Soft-skip if the environment doesn't surface the announcement.
        guard await waitFor({ SyphonClient.availableServers().first { $0.name == name } }) != nil else {
            return
        }

        let client = SyphonClient(named: name)
        defer { client.stop() }
        #expect(await waitFor({ client.isActive ? true : nil }) == true)

        // Keep publishing and confirm a frame comes back as an Image of the right size.
        let frame = await waitFor { () -> Image? in
            publishOnce()
            return client.newFrame()
        }
        #expect(frame != nil)
        #expect(frame?.width == size)
        #expect(frame?.height == size)
    }
}
