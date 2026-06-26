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

    /// The fetch used to download a URL's bytes. Defaults to a `URLSession` download that
    /// prints terminal progress (so a large HDRI fetch isn't a silent pause); a test replaces
    /// it with a stub that returns canned data, so the cache logic runs without the network.
    var fetch: @Sendable (URL) async throws -> Data = { url in
        try await EnvironmentCache.downloadReportingProgress(url)
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

    /// A cache file's friendly display name: the original file name with the `<16-hex-hash>-`
    /// prefix that `cacheFile(for:)` prepends stripped off, so a progress line reads as the
    /// plain HDRI name. A file with no such prefix (a user's own `hdri(path:)`) is unchanged.
    static func displayName(for fileURL: URL) -> String {
        let name = fileURL.lastPathComponent
        guard name.count > 17, name[name.index(name.startIndex, offsetBy: 16)] == "-",
              name.prefix(16).allSatisfy(\.isHexDigit) else { return name }
        return String(name.dropFirst(17))
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
            inFlight.withLock { _ = $0.remove(url) }
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

    /// Download a URL's bytes, printing throttled progress to the terminal. A remote HDRI (and
    /// then a large EXR decode) is otherwise a silent multi-second pause on the first run; this
    /// names the file and shows MB/percent as it downloads, then a "decoding…" note follows from
    /// the renderer where the decode happens.
    ///
    /// Uses a classic `URLSessionDownloadTask` on a delegate-configured session (not the async
    /// `download(from:delegate:)` convenience, whose per-task delegate doesn't get the
    /// `didWriteData` progress callback), bridged to async with a continuation. The download
    /// task streams to a temp file natively, so there's no per-byte copy cost.
    static func downloadReportingProgress(_ url: URL) async throws -> Data {
        let name = url.lastPathComponent
        print("Ollin: downloading \(name)…")
        let data = try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgress(name: name, continuation: continuation)
            // The session strongly retains the delegate, and the delegate holds the session, so
            // the pair stays alive through the running task; the delegate breaks the cycle by
            // invalidating the session once it finishes.
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: url).resume()
        }
        print(String(format: "Ollin: downloaded %@ (%.1f MB)", name, Double(data.count) / 1_048_576))
        return data
    }
}

/// Drives a download task: prints throttled byte/percent progress, and resumes a continuation
/// once the file lands (read in the callback, where the temp file is still valid) or the task
/// fails. Progress prints only when the bucket advances (every 10%, or every ~8 MB when the
/// server gives no content length), so a fast download stays a few lines, not a flood.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let name: String
    private let continuation: CheckedContinuation<Data, Error>
    private let lastBucket = OSAllocatedUnfairLock(initialState: -1)
    private let finished = OSAllocatedUnfairLock(initialState: false)
    var session: URLSession?

    init(name: String, continuation: CheckedContinuation<Data, Error>) {
        self.name = name
        self.continuation = continuation
    }

    /// Resume the continuation exactly once and tear down the session (breaking its retain cycle
    /// with this delegate). `didFinishDownloadingTo` is followed by a `didCompleteWithError(nil)`,
    /// so the guard keeps the second from double-resuming.
    private func finish(_ result: Result<Data, Error>) {
        let first = finished.withLock { done -> Bool in
            guard !done else { return false }
            done = true
            return true
        }
        guard first else { return }
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        let mb = Double(written) / 1_048_576
        let bucket: Int
        let line: String
        if total > 0 {
            let pct = Int(Double(written) / Double(total) * 100)
            bucket = pct / 10
            line = String(format: "Ollin:   %@ %d%% (%.1f / %.1f MB)", name, pct, mb, Double(total) / 1_048_576)
        } else {
            bucket = Int(mb / 8)
            line = String(format: "Ollin:   %@ %.1f MB", name, mb)
        }
        let advanced = lastBucket.withLock { (last: inout Int) -> Bool in
            guard bucket > last else { return false }
            last = bucket
            return true
        }
        if advanced { print(line) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        finish(Result { try Data(contentsOf: location) })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
