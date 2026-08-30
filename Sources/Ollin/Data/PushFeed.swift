import Foundation
import os

/// A connection held open, so a machine can say something the moment it
/// happens.
///
/// A `DataFeed` asks on a schedule, which suits a value that changes slowly.
/// A `PushFeed` keeps a socket open instead and reads whatever the other end
/// sends, as it sends it. Make one in `setup()`, `start()` it, then read in
/// `draw()`:
///
/// ```swift
/// let edits = PushFeed("https://stream.wikimedia.org/v2/stream/recentchange")
///
/// override func setup() { edits.start() }
///
/// override func draw() {
///     for message in edits.messages() {
///         splash(message.json["title"].string ?? "")
///     }
/// }
/// ```
///
/// The address decides how the connection is made: `ws://` and `wss://` open
/// a web socket, and anything else is read as a stream of server-sent events,
/// the plain-HTTP way a server pushes. The surface is the same either way:
/// the latest message as `json` / `text` / `bytes`, everything since the last
/// frame from `messages()`, a count in `updates`, and `problem` saying why
/// when the connection is down.
///
/// Reconnection is the point, because a piece on a wall outlives any socket.
/// A dropped connection redials on its own: after a few seconds at first,
/// backing off to eight times that while the failures keep coming, and from
/// the start again once something arrives. A stream that labels its messages
/// with ids is resumed from the last id seen, so a blink loses nothing the
/// server still holds. The `greeting:` is said each time the connection
/// opens, not once, which is what keeps a service that wants a subscribe
/// message subscribed across every redial.
///
/// In a headless export the feed waits for one message while `start()` runs,
/// then closes and holds it for every frame. An export listening per frame
/// would render something different each time it ran.
public final class PushFeed: @unchecked Sendable {

    /// One thing the server said.
    public struct Message: Sendable {
        /// The message's bytes.
        public let bytes: Data
        /// The bytes as text, or `nil` when they are not UTF-8.
        public let text: String?
        /// The bytes read as JSON, or null when they are not JSON.
        public let json: JSON
        /// The label a stream that names its events sent, or `nil` for a
        /// message with no name.
        public let event: String?
    }

    /// The address as it was given.
    public let address: String

    /// Seconds before a dropped connection is redialed. Never below one, and
    /// a run of failures backs off to as much as eight times it. A stream
    /// that names its own retry time overrides it.
    public let retryInterval: Double

    /// Said to the server each time the connection opens. A service that
    /// wants a subscribe message wants it again after every redial, which is
    /// why this is part of the feed rather than a call made once.
    public let greeting: String?

    /// The largest multiple of the retry interval a run of failures backs
    /// off to.
    private static let backoffLimit = 8.0

    private let url: URL?
    private let headers: [String: String]
    private let queue = DispatchQueue(label: "co.eavl.ollin.data.push")
    private let makeTransport: PushTransportFactory
    /// Signaled on each message during a headless export, so `start()` can
    /// return the moment the one answer the export will draw is in.
    private let firstMessage = DispatchSemaphore(value: 0)

    private struct State: Sendable {
        var running = false
        var connected = false
        /// Bumped by `start()`, `stop()`, `reconnect()`, and every redial, so
        /// work belonging to a connection that has been replaced recognizes
        /// that it is orphaned and does nothing.
        var generation = 0
        /// Read from the export state once, while `start()` runs on the thread
        /// the drive owns, so the rest of the feed can consult it from any
        /// thread.
        var headless = false
        var transport: (any PushTransport)?
        var bytes: Data?
        var json: JSON = .null
        var text: String?
        var event: String?
        var pending: [Message] = []
        var updates = 0
        var lastUpdate: Date?
        var failures = 0
        var problem: String?
        var lastEventID: String?
        var serverRetry: Double?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// How many unread messages are kept between frames. A feed nobody is
    /// draining must not grow without bound, so past this the oldest go.
    static let pendingLimit = 256

    // MARK: Lifecycle

    /// Holds `address` open and reads what arrives.
    ///
    /// An address that isn't one leaves the feed empty and says so in
    /// `problem`, the same as a server that never answers: a feed with
    /// nothing to draw is one state, not two.
    ///
    /// `headers:` are sent with every connection, which is where an API key
    /// goes when a service asks for one. `greeting:` is sent each time the
    /// connection opens; a stream of server-sent events has no way to take
    /// it, so there it is ignored.
    public convenience init(_ address: String, headers: [String: String] = [:],
                            greeting: String? = nil, retryEvery retryInterval: Double = 3) {
        self.init(address: address, url: DataFeed.parse(address), headers: headers,
                  greeting: greeting, retryInterval: retryInterval)
    }

    /// Holds `url` open and reads what arrives.
    public convenience init(_ url: URL, headers: [String: String] = [:],
                            greeting: String? = nil, retryEvery retryInterval: Double = 3) {
        self.init(address: url.absoluteString, url: url, headers: headers,
                  greeting: greeting, retryInterval: retryInterval)
    }

    /// A feed whose connections are answered by `protocolClasses` rather than
    /// by the network. The tests stream server-sent events through it, so the
    /// suite needs no socket and no server.
    convenience init(_ address: String, headers: [String: String] = [:],
                     greeting: String? = nil, retryEvery retryInterval: Double = 3,
                     answeredBy protocolClasses: [AnyClass]) {
        self.init(address: address, url: DataFeed.parse(address), headers: headers,
                  greeting: greeting, retryInterval: retryInterval,
                  protocolClasses: protocolClasses)
    }

    /// A feed whose connections are the given factory's, so the tests drive
    /// the redial logic with a transport they script.
    convenience init(_ address: String, greeting: String? = nil,
                     retryEvery retryInterval: Double = 3,
                     carriedBy factory: @escaping PushTransportFactory) {
        self.init(address: address, url: DataFeed.parse(address), headers: [:],
                  greeting: greeting, retryInterval: retryInterval, factory: factory)
    }

    private init(address: String, url: URL?, headers: [String: String],
                 greeting: String?, retryInterval: Double,
                 protocolClasses: [AnyClass]? = nil,
                 factory: PushTransportFactory? = nil) {
        self.address = address
        self.url = url
        self.headers = headers
        self.greeting = greeting
        self.retryInterval = max(1, retryInterval)

        // Ephemeral, with the shared cache out of the way: a held-open stream
        // is not a document to cache. The request timeout doubles as the idle
        // limit on a stream of events, so a stream that has gone quiet for a
        // minute is treated as dead and redialed rather than trusted forever.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Ollin"]
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        self.makeTransport = factory ?? PushFeed.liveTransports(configuration: configuration)
    }

    deinit {
        stop()
    }

    /// Connects, and keeps the connection alive from then on. Calling it on a
    /// feed that is already running does nothing.
    ///
    /// In a headless export this waits for the first message and returns with
    /// the connection closed, so every exported frame draws the same thing,
    /// and the wait holds whichever thread called, `setup()`'s main one
    /// normally. Nothing here touches the main actor, so a piece is free to
    /// start a feed from a background task as well.
    public func start() {
        // A headless drive owns the main thread from `setup()` through the last
        // frame, so a feed a sketch made asks there and gets its own export.
        // A `start()` on any other thread is not part of that drive, and taking
        // the flag at face value there is how a test process reads somebody
        // else's render as its own: it renders headlessly back to back while
        // its other tests run on the concurrency pool, and a feed that believes
        // it is being exported waits 20 seconds for a message and hangs up.
        let headless = Thread.isMainThread && OllinApp.isRenderingHeadless
        let generation: Int? = state.withLock {
            guard !$0.running else { return nil }
            $0.running = true
            $0.headless = headless
            $0.generation += 1
            return $0.generation
        }
        guard let generation else { return }

        connect(generation: generation)
        guard headless else { return }

        _ = firstMessage.wait(timeout: .now() + 20)
        let transport: (any PushTransport)? = state.withLock {
            $0.generation += 1
            $0.connected = false
            let transport = $0.transport
            $0.transport = nil
            return transport
        }
        transport?.close()
    }

    /// Hangs up. What arrived stays readable.
    public func stop() {
        let transport: (any PushTransport)? = state.withLock {
            $0.running = false
            $0.connected = false
            $0.generation += 1
            let transport = $0.transport
            $0.transport = nil
            return transport
        }
        transport?.close()
    }

    /// Hangs up and dials again now, which is what a key press binds to when
    /// a piece looks stale. Does nothing before `start()`, or during a
    /// headless export.
    public func reconnect() {
        let handoff: (transport: (any PushTransport)?, generation: Int)? = state.withLock {
            guard $0.running, !$0.headless else { return nil }
            $0.connected = false
            $0.generation += 1
            let transport = $0.transport
            $0.transport = nil
            return (transport, $0.generation)
        }
        guard let handoff else { return }
        handoff.transport?.close()
        connect(generation: handoff.generation)
    }

    /// Says `text` to the server, on a feed that is a web socket and is
    /// connected. A stream of server-sent events has no way to take it. For
    /// something that must be said after every redial, use `greeting:`.
    public func send(_ text: String) {
        let transport = state.withLock { $0.connected ? $0.transport : nil }
        transport?.send(text)
    }

    // MARK: What came back

    /// The latest message read as JSON, or null before one arrives.
    public var json: JSON { state.withLock { $0.json } }

    /// The latest message as text, or `nil` before one arrives or when the
    /// bytes are not UTF-8.
    public var text: String? { state.withLock { $0.text } }

    /// The latest message's bytes, or `nil` before one arrives.
    public var bytes: Data? { state.withLock { $0.bytes } }

    /// The latest message's label, on a stream that names its events.
    public var event: String? { state.withLock { $0.event } }

    /// Every message since the last time this was called, oldest first.
    ///
    /// More than one can arrive between two frames, and the latest-message
    /// reads only show the last of them. This is the read that misses
    /// nothing. A feed nobody drains keeps the newest few hundred and lets
    /// the oldest go.
    public func messages() -> [Message] {
        state.withLock {
            let pending = $0.pending
            $0.pending = []
            return pending
        }
    }

    /// How many messages have arrived. Every one counts: where a poll can
    /// bring back what a feed already had, a push is sent because the server
    /// had something to say.
    public var updateCount: Int { state.withLock { $0.updates } }

    /// Seconds since the last message, or `nil` before the first one.
    ///
    /// A headless export reads zero: the one message it holds was fetched for
    /// that export, so it is as fresh as it is going to get, and a wall clock
    /// here would make two runs of the same export differ.
    public var timeSinceUpdate: Double? {
        let (last, headless) = state.withLock { ($0.lastUpdate, $0.headless) }
        guard let last else { return nil }
        return headless ? 0 : Date().timeIntervalSince(last)
    }

    // MARK: How it is going

    /// Whether the feed has been started.
    public var isRunning: Bool { state.withLock { $0.running } }

    /// Whether the connection is open right now. While it is down, the feed
    /// is redialing on its own; `problem` says what happened.
    public var isConnected: Bool { state.withLock { $0.connected } }

    /// Connections that have failed or dropped in a row. Back to zero once
    /// something arrives.
    public var failureCount: Int { state.withLock { $0.failures } }

    /// Why the connection is down, in a sentence a sketch can draw. `nil`
    /// while it is up.
    public var problem: String? { state.withLock { $0.problem } }

    // MARK: Connecting

    private func connect(generation: Int) {
        let go: Bool = state.withLock { $0.running && $0.generation == generation }
        guard go else { return }

        guard let request = makeRequest() else {
            // An address that is not one never becomes one, so there is
            // nothing to redial.
            state.withLock { $0.problem = "\(address) is not an address" }
            return
        }

        let transport = makeTransport(request) { [weak self] event in
            self?.handle(event, generation: generation)
        }
        state.withLock { $0.transport = transport }
        transport.open()
    }

    private func makeRequest() -> URLRequest? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "ws" && scheme != "wss" {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            // Resume from the last message seen, so the blink between a drop
            // and the redial loses nothing the server still holds.
            if let id = state.withLock({ $0.lastEventID }) {
                request.setValue(id, forHTTPHeaderField: "Last-Event-ID")
            }
        }
        return request
    }

    /// What `handle` decides under the lock and does after releasing it.
    /// Talking to a transport or a semaphore while holding the lock is how a
    /// deadlock starts, so the lock only ever returns instructions.
    private struct Followup: Sendable {
        var greetingCarrier: (any PushTransport)?
        var signalFirst = false
        var redial: (delay: Double, generation: Int)?
    }

    private func handle(_ event: PushTransportEvent, generation: Int) {
        let followup: Followup = state.withLock {
            var followup = Followup()
            guard $0.generation == generation else { return followup }
            switch event {
            case .opened:
                $0.connected = true
                $0.problem = nil
                if greeting != nil { followup.greetingCarrier = $0.transport }

            case .message(let bytes, let isText, let name, let id):
                let text = isText
                    ? String(decoding: bytes, as: UTF8.self)
                    : String(data: bytes, encoding: .utf8)
                let json = DataFeed.opensLikeJSON(bytes) ? (JSON(data: bytes) ?? .null) : .null
                let message = Message(bytes: bytes, text: text, json: json, event: name)
                $0.bytes = bytes
                $0.json = json
                $0.text = text
                $0.event = name
                $0.pending.append(message)
                if $0.pending.count > PushFeed.pendingLimit {
                    $0.pending.removeFirst($0.pending.count - PushFeed.pendingLimit)
                }
                $0.updates += 1
                $0.lastUpdate = Date()
                $0.failures = 0
                $0.problem = nil
                if let id { $0.lastEventID = id }
                followup.signalFirst = $0.headless

            case .heard:
                // A keepalive or a pong: not a message, but proof the other
                // end is there, which is what the backoff resets on.
                $0.failures = 0

            case .retryHint(let seconds):
                $0.serverRetry = max(1, seconds)

            case .closed(let reason):
                $0.connected = false
                $0.failures += 1
                $0.problem = reason
                $0.transport = nil
                if $0.running && !$0.headless {
                    // The generation moves, so anything the dead connection
                    // still says is orphaned rather than counted again.
                    $0.generation += 1
                    let base = $0.serverRetry ?? retryInterval
                    let delay = PushFeed.retryDelay(after: $0.failures, base: base)
                    followup.redial = (delay, $0.generation)
                }

            case .ended(let reason):
                // The server asked for no reconnection, which a stream of
                // server-sent events says with a 204. Honoring it is part of
                // being a polite client.
                $0.connected = false
                $0.running = false
                $0.problem = reason
                $0.transport = nil
                $0.generation += 1
            }
            return followup
        }

        if let carrier = followup.greetingCarrier, let greeting { carrier.send(greeting) }
        if followup.signalFirst { firstMessage.signal() }
        if let redial = followup.redial {
            queue.asyncAfter(deadline: .now() + redial.delay) { [weak self] in
                self?.connect(generation: redial.generation)
            }
        }
    }

    /// The base the next redial's wait is a multiple of: the server's own
    /// retry time when it named one, the feed's interval otherwise.
    var retryBase: Double { state.withLock { $0.serverRetry ?? retryInterval } }

    /// The wait before a redial: the base doubled per consecutive failure, up
    /// to a ceiling, so a server that is down is not dialed every few seconds
    /// for as long as the piece is up.
    static func retryDelay(after failures: Int, base: Double) -> Double {
        base * min(pow(2, Double(max(0, failures - 1))), PushFeed.backoffLimit)
    }

    // MARK: The live transports

    /// The address decides: `ws` and `wss` open a web socket, and anything
    /// else is read as a stream of server-sent events.
    private static func liveTransports(configuration: URLSessionConfiguration)
        -> PushTransportFactory {
        { request, deliver in
            let scheme = request.url?.scheme?.lowercased() ?? ""
            if scheme == "ws" || scheme == "wss" {
                return WebSocketTransport(request: request, configuration: configuration,
                                          deliver: deliver)
            }
            return EventStreamTransport(request: request, configuration: configuration,
                                        deliver: deliver)
        }
    }
}
