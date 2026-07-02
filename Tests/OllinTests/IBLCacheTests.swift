import Testing
import Metal
@testable import Ollin

/// The baked-environment cache (`MetalRenderer.iblCache`): entries are keyed by source and
/// evicted least-recently-used past the byte budget, so a sketch cycling many HDRIs (a
/// gallery, a varying URL) stays bounded instead of retaining every bake for the session.
/// Uses bundled 1K environments (offline, CI-safe) and a tiny budget override so eviction
/// is observable without baking gigabytes.
@MainActor
struct IBLCacheTests {

    private func makeRenderer() throws -> (MetalRenderer, MTLCommandQueue)? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        return (renderer, queue)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func cacheHoldsDistinctSourcesWithinBudget() throws {
        guard let (renderer, queue) = try makeRenderer(),
              let cb = queue.makeCommandBuffer() else { return }
        #expect(renderer.resolveIBL(for: .studio, commandBuffer: cb, blocking: true))
        #expect(renderer.resolveIBL(for: .sunset, commandBuffer: cb, blocking: true))
        // Within the (default) budget both stay, and a re-resolve is a cache hit
        // (the entry count doesn't grow).
        #expect(renderer.iblCacheStats.count == 2)
        #expect(renderer.resolveIBL(for: .studio, commandBuffer: cb, blocking: true))
        #expect(renderer.iblCacheStats.count == 2)
        #expect(renderer.iblCacheStats.bytes > 0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func leastRecentlyUsedEntryEvictsPastBudget() throws {
        guard let (renderer, queue) = try makeRenderer(),
              let cb = queue.makeCommandBuffer() else { return }
        renderer.iblCacheBudgetOverride = 1   // any second entry exceeds it
        #expect(renderer.resolveIBL(for: .studio, commandBuffer: cb, blocking: true))
        #expect(renderer.iblCacheStats.count == 1)
        // Baking a second source evicts the first (LRU), never the one just baked.
        #expect(renderer.resolveIBL(for: .sunset, commandBuffer: cb, blocking: true))
        #expect(renderer.iblCacheStats.count == 1)
        // Returning to the first source re-bakes it (it was evicted) and evicts the other.
        #expect(renderer.resolveIBL(for: .studio, commandBuffer: cb, blocking: true))
        #expect(renderer.iblCacheStats.count == 1)
    }
}
