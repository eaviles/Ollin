import Foundation
import os

/// An address read again and again, so a sketch can draw something that is
/// currently true.
///
/// Where `loadTable` and `loadJSON` read a document once and keep it, a
/// `DataFeed` keeps asking. Make one in `setup()`, `start()` it, then read the
/// latest answer in `draw()`:
///
/// ```swift
/// let tide = DataFeed("https://example.org/tide.json", every: 600)
///
/// override func setup() { tide.start() }
///
/// override func draw() {
///     let height = tide.json["height"].number ?? 0
///     drawCircle(center: center, radius: 40 + height * 20)
/// }
/// ```
///
/// The request runs on a background queue, so `draw()` never waits for the
/// network, and the bytes are read into a `JSON` or a `Table` there too rather
/// than in the frame that first asks for them.
///
/// Until an answer arrives, `json` reads as null and `table`, `text`, and
/// `bytes` are `nil`. That is also what a feed reads when the network is down or
/// the server is unhappy: there is nothing to draw yet, rather than an error to
/// handle. `problem` says why, for a sketch that wants to show it.
///
/// `updates` counts the answers that differed from the one before, so a sketch
/// can tell news from a poll that changed nothing:
///
/// ```swift
/// if tide.updates != seen {
///     seen = tide.updates
///     startTheTransition()
/// }
/// ```
///
/// Polling is unhurried on purpose. `every:` is in seconds and never goes below
/// one; the next request is scheduled only once the last one has finished, so a
/// slow server can never make requests stack up; an unchanged answer is asked
/// for conditionally, so a server that supports it can reply with a header and
/// no body; and a run of failures backs off to as much as eight times the
/// interval before trying again.
///
/// In a headless export the feed reads once, while `start()` runs, and holds
/// that answer for every frame. An export that fetched per frame would render
/// something different each time it ran.
public final class DataFeed: @unchecked Sendable {

    /// How a feed's bytes are read.
    public enum Content: Sendable {
        /// Decide from the response's content type, and failing that from the
        /// bytes: a document opening with `{` or `[` is JSON, and anything else
        /// is tried as a table. Text is always available either way.
        case auto
        /// Read as JSON, whatever the server calls it.
        case json
        /// Read as CSV or TSV, whatever the server calls it.
        case table
        /// Keep the text and the bytes, and parse nothing.
        case text
    }

    /// The address as it was given.
    public let address: String

    /// Seconds between requests. Never below one.
    public let interval: Double

    /// What the bytes are read as.
    public let content: Content

    /// The largest multiple of `interval` a run of failures backs off to.
    private static let backoffLimit = 8.0

    private let url: URL?
    private let headers: [String: String]
    private let queue = DispatchQueue(label: "co.eavl.ollin.data.feed")
    private let session: URLSession

    private struct State: Sendable {
        var running = false
        var waiting = false
        /// Bumped by `start()` and `stop()`, so work scheduled by a previous run
        /// recognizes that it has been orphaned and does nothing.
        var generation = 0
        /// Read from the export state once, while `start()` runs on the thread
        /// the drive owns, so the rest of the feed can consult it from any
        /// thread.
        var headless = false
        var bytes: Data?
        var json: JSON = .null
        var table: Table?
        var text: String?
        var updates = 0
        var lastUpdate: Date?
        var failures = 0
        var problem: String?
        var etag: String?
        var modified: String?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: Lifecycle

    /// Reads `address` every `interval` seconds.
    ///
    /// An address that isn't one leaves the feed empty and says so in `problem`,
    /// the same as a server that never answers: a feed with nothing to draw is
    /// one state, not two.
    ///
    /// `headers:` are sent with every request, which is where an API key or a
    /// contact address goes when a service asks for one.
    public convenience init(_ address: String, every interval: Double = 300,
                            as content: Content = .auto, headers: [String: String] = [:]) {
        self.init(address: address, url: DataFeed.parse(address),
                  interval: interval, content: content, headers: headers)
    }

    /// `URL(string:)` accepts a bare phrase as a relative reference, which would
    /// then fail much later as an unloadable request. A feed wants an address it
    /// can actually go to, so it insists on a scheme.
    static func parse(_ address: String) -> URL? {
        guard let url = URL(string: address), url.scheme != nil else { return nil }
        return url
    }

    /// Reads `url` every `interval` seconds.
    public convenience init(_ url: URL, every interval: Double = 300,
                            as content: Content = .auto, headers: [String: String] = [:]) {
        self.init(address: url.absoluteString, url: url,
                  interval: interval, content: content, headers: headers)
    }

    /// A feed whose requests are answered by `protocolClasses` rather than by
    /// the network. The tests drive every branch of the polling through it, so
    /// the suite needs no socket and no server.
    convenience init(_ address: String, every interval: Double, as content: Content = .auto,
                     headers: [String: String] = [:], answeredBy protocolClasses: [AnyClass]) {
        self.init(address: address, url: DataFeed.parse(address), interval: interval,
                  content: content, headers: headers, protocolClasses: protocolClasses)
    }

    private init(address: String, url: URL?, interval: Double,
                 content: Content, headers: [String: String],
                 protocolClasses: [AnyClass]? = nil) {
        self.address = address
        self.url = url
        self.interval = max(1, interval)
        self.content = content
        self.headers = headers

        // Ephemeral, with the shared cache out of the way: the conditional
        // request below is how an unchanged answer is recognized, and a cache
        // that answered from disk would hide the very header that says so.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "Ollin"]
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        stop()
        session.invalidateAndCancel()
    }

    /// Asks now, and then every `interval` seconds. Calling it on a feed that is
    /// already running does nothing.
    ///
    /// In a headless export this reads once and returns when the answer is in,
    /// so every exported frame draws the same numbers, and the wait holds
    /// whichever thread called, `setup()`'s main one normally. Nothing here
    /// touches the main actor, so a piece is free to start a feed from a
    /// background task as well.
    public func start() {
        // A headless drive owns the main thread from `setup()` through the last
        // frame, so a feed a sketch made asks there and gets its own export.
        // A `start()` on any other thread is not part of that drive, and taking
        // the flag at face value there is how a test process reads somebody
        // else's render as its own: it renders headlessly back to back while
        // its other tests run on the concurrency pool, and a feed that believes
        // it is being exported reads once and never asks again.
        let headless = Thread.isMainThread && OllinApp.isRenderingHeadless
        let generation: Int? = state.withLock {
            guard !$0.running else { return nil }
            $0.running = true
            $0.headless = headless
            $0.generation += 1
            return $0.generation
        }
        guard let generation else { return }

        if headless {
            fetchOnceForExport(generation: generation)
        } else {
            schedule(after: 0, generation: generation)
        }
    }

    /// Stops asking. What arrived stays readable.
    public func stop() {
        state.withLock {
            $0.running = false
            $0.waiting = false
            $0.generation += 1
        }
    }

    /// Asks now rather than waiting for the next turn, which is what a key press
    /// or an incoming message binds to. Does nothing while a request is already
    /// in flight, or during a headless export.
    public func refresh() {
        // The generation moves, which orphans the request already sitting on the
        // schedule. Without that the feed would run two chains at once and ask
        // twice as often as it promised.
        let generation: Int? = state.withLock {
            guard $0.running, !$0.waiting, !$0.headless else { return nil }
            $0.generation += 1
            return $0.generation
        }
        guard let generation else { return }
        schedule(after: 0, generation: generation)
    }

    // MARK: What came back

    /// The latest answer read as JSON, or null before one arrives.
    public var json: JSON { state.withLock { $0.json } }

    /// The latest answer read as a table, or `nil` before one arrives or when
    /// the bytes are not one.
    public var table: Table? { state.withLock { $0.table } }

    /// The latest answer as text, or `nil` before one arrives or when the bytes
    /// are not UTF-8.
    public var text: String? { state.withLock { $0.text } }

    /// The latest answer's bytes, or `nil` before one arrives.
    public var bytes: Data? { state.withLock { $0.bytes } }

    /// How many answers have differed from the one before. A poll that brings
    /// back what the feed already had does not count.
    public var updates: Int { state.withLock { $0.updates } }

    /// Seconds since the answer last changed, or `nil` before the first one.
    ///
    /// A headless export reads zero: the one answer it holds was fetched for
    /// that export, so it is as fresh as it is going to get, and a wall clock
    /// here would make two runs of the same export differ.
    public var timeSinceUpdate: Double? {
        let (last, headless) = state.withLock { ($0.lastUpdate, $0.headless) }
        guard let last else { return nil }
        return headless ? 0 : Date().timeIntervalSince(last)
    }

    // MARK: How it is going

    /// Whether the feed is asking.
    public var isRunning: Bool { state.withLock { $0.running } }

    /// Whether a request is in flight right now.
    public var isWaiting: Bool { state.withLock { $0.waiting } }

    /// Requests that have failed in a row. Back to zero on the next answer.
    public var failures: Int { state.withLock { $0.failures } }

    /// Why the last request failed, in a sentence a sketch can draw. `nil` once
    /// an answer arrives.
    public var problem: String? { state.withLock { $0.problem } }

    // MARK: Asking

    private func schedule(after delay: Double, generation: Int) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.fetch(generation: generation)
        }
    }

    private func fetch(generation: Int) {
        let go: Bool = state.withLock {
            guard $0.running, $0.generation == generation else { return false }
            $0.waiting = true
            return true
        }
        guard go else { return }

        guard let request = makeRequest() else {
            state.withLock {
                $0.waiting = false
                $0.failures += 1
                $0.problem = "\(address) is not an address"
            }
            schedule(after: backoff(), generation: generation)
            return
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.received(data: data, response: response, error: error,
                          generation: generation, schedulingNext: true)
        }.resume()
    }

    /// The blocking read a headless export makes, so `setup()` returns with the
    /// numbers the whole export will draw.
    private func fetchOnceForExport(generation: Int) {
        guard let request = makeRequest() else {
            state.withLock {
                $0.failures += 1
                $0.problem = "\(address) is not an address"
            }
            return
        }
        state.withLock { $0.waiting = true }

        let arrived = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { [weak self] data, response, error in
            self?.received(data: data, response: response, error: error,
                           generation: generation, schedulingNext: false)
            arrived.signal()
        }.resume()
        _ = arrived.wait(timeout: .now() + 20)
        state.withLock { $0.waiting = false }
    }

    private func makeRequest() -> URLRequest? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        // Ask the server to answer with a header alone when it still holds what
        // we already have.
        let (etag, modified) = state.withLock { ($0.etag, $0.modified) }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        return request
    }

    private func received(data: Data?, response: URLResponse?, error: Error?,
                          generation: Int, schedulingNext: Bool) {
        var delay = interval

        if let error {
            state.withLock {
                $0.waiting = false
                $0.failures += 1
                $0.problem = error.localizedDescription
            }
            delay = backoff()
        } else {
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 200
            switch status {
            case 304:
                // The server still holds what we do, so nothing changed.
                state.withLock {
                    $0.waiting = false
                    $0.failures = 0
                    $0.problem = nil
                }
            case 200..<300:
                let bytes = data ?? Data()
                let read = DataFeed.read(bytes, contentType: http?.value(forHTTPHeaderField: "Content-Type"), as: content)
                state.withLock {
                    $0.waiting = false
                    $0.failures = 0
                    $0.problem = nil
                    $0.etag = http?.value(forHTTPHeaderField: "ETag")
                    $0.modified = http?.value(forHTTPHeaderField: "Last-Modified")
                    if $0.bytes != bytes {
                        $0.bytes = bytes
                        $0.json = read.json
                        $0.table = read.table
                        $0.text = read.text
                        $0.updates += 1
                        $0.lastUpdate = Date()
                    }
                }
            default:
                state.withLock {
                    $0.waiting = false
                    $0.failures += 1
                    $0.problem = "the server answered \(status)"
                }
                delay = backoff()
            }
        }

        guard schedulingNext else { return }
        let live: Int? = state.withLock { $0.running && $0.generation == generation ? generation : nil }
        guard let live else { return }
        schedule(after: delay, generation: live)
    }

    /// The wait after a failure: the interval doubled per consecutive failure,
    /// up to a ceiling, so a server that is down is not asked every few seconds
    /// for as long as the piece is up.
    private func backoff() -> Double {
        let failures = state.withLock { $0.failures }
        let multiple = min(pow(2, Double(max(0, failures - 1))), DataFeed.backoffLimit)
        return interval * multiple
    }

    // MARK: Reading the bytes

    /// Turns bytes into the shapes a sketch reads. Runs on the network queue, so
    /// no frame pays for the parse.
    static func read(_ bytes: Data, contentType: String?, as content: Content)
        -> (json: JSON, table: Table?, text: String?) {

        let text = String(data: bytes, encoding: .utf8)

        switch content {
        case .text:
            return (.null, nil, text)
        case .json:
            return (JSON(data: bytes) ?? .null, nil, text)
        case .table:
            return (.null, Table(data: bytes), text)
        case .auto:
            break
        }

        let type = (contentType ?? "").lowercased()
        if type.contains("json") || (type.isEmpty && opensLikeJSON(bytes)) {
            return (JSON(data: bytes) ?? .null, nil, text)
        }
        if type.contains("csv") || type.contains("tab-separated") {
            return (.null, Table(data: bytes), text)
        }
        // Nothing said what this is. A document that opens like JSON is read as
        // JSON, and anything else is offered as a table, which comes back nil
        // when the bytes are not one.
        if opensLikeJSON(bytes) {
            return (JSON(data: bytes) ?? .null, nil, text)
        }
        return (.null, Table(data: bytes), text)
    }

    /// Whether the first byte that isn't whitespace opens an object or an array.
    static func opensLikeJSON(_ bytes: Data) -> Bool {
        for byte in bytes {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: continue
            case UInt8(ascii: "{"), UInt8(ascii: "["): return true
            default: return false
            }
        }
        return false
    }
}
