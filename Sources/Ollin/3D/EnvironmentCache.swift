import Foundation
import os

/// Downloads and caches remote HDRI environments (`Environment.hdri(downloadURL:)` and the
/// `highRes(_:)` built-in upgrades). The bundled 1K environments need none of this; a remote
/// one is fetched once, written to a cache directory, and loaded from there forever after.
///
/// The cache lives at `~/Library/Caches/Ollin/Environments/` by default, overridable with the
/// `OLLIN_ENVIRONMENT_CACHE` environment variable. The actual fetch is injectable (`fetch`),
/// so tests stub it with canned bytes: no real network, no flakiness.
final class EnvironmentCache: @unchecked Sendable {

    static let shared = EnvironmentCache()

    /// The directory cached HDRIs are written to. `OLLIN_ENVIRONMENT_CACHE` overrides the
    /// default per-user caches location.
    let cacheDirectory: URL

    /// The fetch used to download a URL's bytes. Defaults to `URLSession`; a test replaces it
    /// with a stub that returns canned data, so the cache logic runs without the network.
    var fetch: @Sendable (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }

    /// URLs currently downloading, so a repeated request (every frame, while it's in flight)
    /// doesn't start a second download. An unfair lock is safe from the async download task.
    private let inFlight = OSAllocatedUnfairLock(initialState: Set<URL>())

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else if let override = ProcessInfo.processInfo.environment["OLLIN_ENVIRONMENT_CACHE"] {
            self.cacheDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = caches.appendingPathComponent("Ollin/Environments", isDirectory: true)
        }
    }

    /// The cache file a remote URL maps to: a stable hash of the full URL plus the original
    /// file name (so two URLs sharing a last component don't collide, and the name stays
    /// recognizable on disk).
    func cacheFile(for url: URL) -> URL {
        var hash: UInt64 = 1469598103934665603   // FNV-1a over the URL string
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let name = String(format: "%016llx-%@", hash, url.lastPathComponent)
        return cacheDirectory.appendingPathComponent(name)
    }

    /// The cached file for a URL if it has already been downloaded, else nil.
    func cachedFile(for url: URL) -> URL? {
        let file = cacheFile(for: url)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The cache file for a *processed* equirect (the raw float pixels a source HDRI decodes
    /// to), so a relaunch can skip re-decoding a large EXR. Keyed by the source file's path,
    /// distinct from the download file by suffix, and kept in the same cache directory (so a
    /// user's own `hdri(path:)` blob lands here, not beside their file).
    func equirectBlobFile(for fileURL: URL) -> URL {
        cacheFile(for: fileURL).appendingPathExtension("equirectf16")
    }

    /// Kick off a background download if the file isn't cached and isn't already downloading.
    /// Returns immediately; the live render loop picks up the file once it lands.
    func ensureDownloading(_ url: URL) {
        if cachedFile(for: url) != nil { return }
        let started = inFlight.withLock { state -> Bool in
            guard !state.contains(url) else { return false }
            state.insert(url); return true
        }
        guard started else { return }
        // Capture only Sendable locals (not self) so the detached task is race-free.
        let file = cacheFile(for: url), dir = cacheDirectory, fetch = self.fetch, inFlight = self.inFlight
        Task.detached {
            _ = try? await EnvironmentCache.store(url, to: file, in: dir, fetch: fetch)
            inFlight.withLock { $0.remove(url) }
        }
    }

    /// Download synchronously (for the headless/export path, so exported art gets the high-res
    /// version rather than the placeholder). Returns the cached file, or nil on failure.
    func downloadBlocking(_ url: URL) -> URL? {
        if let cached = cachedFile(for: url) { return cached }
        let file = cacheFile(for: url), dir = cacheDirectory, fetch = self.fetch
        let result = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            let r = try? await EnvironmentCache.store(url, to: file, in: dir, fetch: fetch)
            result.withLock { $0 = r }
            sema.signal()
        }
        sema.wait()
        return result.withLock { $0 }
    }

    /// Fetch a URL's bytes and write them to the cache file (atomically). Static so the
    /// download task captures no non-Sendable state.
    private static func store(_ url: URL, to file: URL, in dir: URL,
                              fetch: @Sendable (URL) async throws -> Data) async throws -> URL {
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let data = try await fetch(url)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = file.appendingPathExtension("download")
        try data.write(to: tmp, options: .atomic)
        // Rename into place so a half-written file is never observed as cached.
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
        return file
    }
}
