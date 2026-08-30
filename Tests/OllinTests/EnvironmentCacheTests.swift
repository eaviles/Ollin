import Testing
import Foundation
import os
@testable import Ollin

/// The remote-environment download cache, tested with an injected mock fetch (no network),
/// so it's deterministic and CI-safe. The real download path is exercised only when a user
/// runs a URL/high-res sketch; the render snapshots use only the bundled 1K environments.
@Suite struct EnvironmentCacheTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-envcache-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func cacheFileIsStableAndUniquePerURL() {
        let cache = EnvironmentCache(cacheDirectory: tempDir())
        let a = URL(string: "https://example.com/a/sky_4k.exr")!
        let b = URL(string: "https://example.com/b/sky_4k.exr")!   // same last path component
        #expect(cache.cacheFile(for: a) == cache.cacheFile(for: a))   // stable for the same URL
        #expect(cache.cacheFile(for: a) != cache.cacheFile(for: b))   // distinct despite same name
        #expect(cache.cacheFile(for: a).lastPathComponent.hasSuffix("sky_4k.exr"))   // recognizable
    }

    @Test func displayNameStripsCacheHashPrefix() {
        let cache = EnvironmentCache(cacheDirectory: tempDir())
        // A cache file carries a `<16-hex-hash>-` prefix; displayName drops it back to the
        // original name for progress lines.
        let url = URL(string: "https://example.com/golden_gate_hills_4k.exr")!
        #expect(EnvironmentCache.displayName(for: cache.cacheFile(for: url)) == "golden_gate_hills_4k.exr")
        // A user's own file (no hash prefix) is returned unchanged.
        #expect(EnvironmentCache.displayName(for: URL(fileURLWithPath: "/tmp/studio.hdr")) == "studio.hdr")
        // A name that merely starts with a dash, or non-hex chars before the dash, isn't stripped.
        #expect(EnvironmentCache.displayName(for: URL(fileURLWithPath: "/tmp/not-a-hash-name.exr")) == "not-a-hash-name.exr")
    }

    @Test func downloadFetchesOnceThenServesFromCache() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = EnvironmentCache(cacheDirectory: dir)
        let url = URL(string: "https://example.com/test_4k.exr")!
        // The canned bytes open with the OpenEXR magic: the cache validates that a
        // download at least starts like an image before writing it (an HTML error
        // body must never be cached as the HDRI).
        let canned = Data([0x76, 0x2F, 0x31, 0x01]) + Data("HDRI-BYTES".utf8)
        let fetchCount = OSAllocatedUnfairLock(initialState: 0)
        cache.fetch = { _ in fetchCount.withLock { $0 += 1 }; return canned }

        #expect(cache.cachedFile(for: url) == nil)                 // not cached yet
        let file = try #require(cache.downloadBlocking(url))       // downloads (mock)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == canned)             // the canned bytes landed
        #expect(cache.cachedFile(for: url) == file)               // now a cache hit
        _ = cache.downloadBlocking(url)                           // second call
        #expect(fetchCount.withLock { $0 } == 1)                  // served from cache, no second fetch
    }

    @Test func downloadRejectsNonImageBodies() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = EnvironmentCache(cacheDirectory: dir)
        let url = URL(string: "https://example.com/missing_4k.exr")!
        cache.fetch = { _ in Data("<html>404 not found</html>".utf8) }
        #expect(cache.downloadBlocking(url) == nil)   // rejected...
        #expect(cache.cachedFile(for: url) == nil)    // ...and nothing poisoned the cache
    }

    @Test func envVarOverridesCacheDirectory() {
        let dir = tempDir()
        setenv("OLLIN_ENVIRONMENT_CACHE", dir.path, 1)
        defer { unsetenv("OLLIN_ENVIRONMENT_CACHE") }
        #expect(EnvironmentCache().cacheDirectory.path == dir.path)
    }

    @Test func highResUpgradesABuiltinToARemoteDownload() {
        // A bundled built-in is a `.resource`; highResolution(_:) turns it into a `.remote` download
        // (with the bundled 1K kept as the placeholder), and .oneK returns the bundled form.
        guard case .resource = Environment.studio.source else { Issue.record("studio not bundled"); return }
        guard case .remote(let url, let fallback) = Environment.studio.highResolution(.fourK).source else {
            Issue.record("highRes not remote"); return
        }
        #expect(url.absoluteString.contains("4k"))
        #expect(url.absoluteString.contains("studio_small_01"))
        #expect(fallback == "studio")
        guard case .resource = Environment.studio.highResolution(.oneK).source else {
            Issue.record(".oneK not bundled"); return
        }
    }
}
