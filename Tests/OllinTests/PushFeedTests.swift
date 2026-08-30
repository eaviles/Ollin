import Foundation
import os
import Testing
@testable import Ollin

/// A stand-in server that streams server-sent events through the feed's own
/// `URLSession`, so the suite drives the whole connection with no socket, no
/// port, and no server to bring up.
///
/// Each test claims its own path. A path holds one script per connection, so
/// a test can say what the first dial gets and what the redial gets.
final class StreamStub: URLProtocol {

    enum Step: Sendable {
        /// Answer with this status, called a stream of events.
        case respond(status: Int)
        /// Deliver these bytes into the open body.
        case send(String)
        /// Fail at the transport.
        case fail(URLError.Code)
        /// End the body in an orderly way.
        case finish
    }

    /// One connection as the stub saw it. Header names are lowercased, the
    /// way a server would treat them.
    struct Ask: Sendable {
        var path = ""
        var headers: [String: String] = [:]
    }

    private struct Shared: Sendable {
        var scripts: [String: [[Step]]] = [:]
        var asks: [String: [Ask]] = [:]
        var claimed = 0
    }
    private static let shared = OSAllocatedUnfairLock(initialState: Shared())

    /// A path nothing else in the suite is using.
    static func claimPath() -> String {
        shared.withLock {
            $0.claimed += 1
            return "/push\($0.claimed)"
        }
    }

    /// One entry per connection, in dial order. A connection past the end of
    /// the list replays the last entry.
    static func script(_ connections: [[Step]], at path: String) {
        shared.withLock { $0.scripts[path] = connections }
    }

    static func asks(at path: String) -> [Ask] {
        shared.withLock { $0.asks[path] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let path = url.path
        var headers: [String: String] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            headers[name.lowercased()] = value
        }

        let ask = Ask(path: path, headers: headers)
        let steps: [Step] = StreamStub.shared.withLock {
            let count = $0.asks[path, default: []].count
            $0.asks[path, default: []].append(ask)
            let connections = $0.scripts[path] ?? []
            guard !connections.isEmpty else { return [] }
            return connections[min(count, connections.count - 1)]
        }

        var sent = false
        for step in steps {
            switch step {
            case .respond(let status):
                let response = HTTPURLResponse(url: url, statusCode: status,
                                               httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "text/event-stream"])!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            case .send(let text):
                client.urlProtocol(self, didLoad: Data(text.utf8))
                sent = true
            case .fail(let code):
                // A failure on the heels of a body chunk races the session
                // dropping the undelivered bytes, so the end waits a beat for
                // the bytes to flush through to the delegate.
                end(after: sent ? 0.2 : 0) { stub, client in
                    client.urlProtocol(stub, didFailWithError: URLError(code))
                }
                return
            case .finish:
                end(after: sent ? 0.2 : 0) { stub, client in
                    client.urlProtocolDidFinishLoading(stub)
                }
                return
            }
        }
        // A script that neither fails nor finishes stays open, the way a
        // healthy stream does.
    }

    private let stopped = OSAllocatedUnfairLock(initialState: false)

    private func end(after delay: Double,
                     _ terminal: @escaping @Sendable (StreamStub, URLProtocolClient) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let client = self.client else { return }
            guard !self.stopped.withLock({ $0 }) else { return }
            terminal(self, client)
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }
}

/// A transport the test scripts by hand, so the redial logic is driven with
/// no network shape underneath at all.
final class ScriptedCarrier: @unchecked Sendable {

    final class Transport: PushTransport, @unchecked Sendable {
        let deliver: @Sendable (PushTransportEvent) -> Void

        private struct Log: Sendable {
            var sent: [String] = []
            var opened = false
            var closed = false
        }
        private let log = OSAllocatedUnfairLock(initialState: Log())

        init(deliver: @escaping @Sendable (PushTransportEvent) -> Void) {
            self.deliver = deliver
        }

        var sent: [String] { log.withLock { $0.sent } }
        var wasOpened: Bool { log.withLock { $0.opened } }
        var wasClosed: Bool { log.withLock { $0.closed } }

        func open() { log.withLock { $0.opened = true } }
        func close() { log.withLock { $0.closed = true } }
        func send(_ text: String) { log.withLock { $0.sent.append(text) } }
    }

    private struct Dialled {
        var made: [Transport] = []
        var waiting: [(index: Int, resume: CheckedContinuation<Transport, Never>)] = []
    }
    private let dialled = OSAllocatedUnfairLock(initialState: Dialled())

    var transports: [Transport] { dialled.withLock { $0.made } }

    var factory: PushTransportFactory {
        { [dialled] request, deliver in
            let transport = Transport(deliver: deliver)
            let due: [(CheckedContinuation<Transport, Never>, Transport)] = dialled.withLock { state in
                state.made.append(transport)
                let count = state.made.count
                let ready = state.waiting.filter { $0.index < count }
                state.waiting.removeAll { $0.index < count }
                return ready.map { ($0.resume, state.made[$0.index]) }
            }
            // Resumed outside the lock: a continuation runs its caller, and
            // that caller reaching back into the carrier would deadlock.
            for (resume, transport) in due { resume.resume(returning: transport) }
            return transport
        }
    }

    /// The transport of the `index`th dial, awaited rather than polled.
    ///
    /// A redial is a dispatch timer, and a full run can leave one unserviced
    /// for far longer than it asked to wait, so a deadline over it measures how
    /// busy the machine is rather than whether the feed redialled. This resumes
    /// the moment the feed dials, however late that is; the suite's time limit
    /// is what catches a feed that never does.
    func dial(_ index: Int) async -> Transport {
        await withCheckedContinuation { continuation in
            let already: Transport? = dialled.withLock { state in
                if index < state.made.count { return state.made[index] }
                state.waiting.append((index, continuation))
                return nil
            }
            if let already { continuation.resume(returning: already) }
        }
    }
}

/// `PushFeed`: the wire shape parsed, and the redial behavior driven end to
/// end. No GPU and no network, so it runs anywhere.
///
/// Deliberately not `@MainActor`, and **nothing here may touch the main actor,
/// `start()` included.** A hop costs the queue, not the hop: the drawing suites
/// are main-actor bound and run one at a time, so a job this suite enqueues
/// waits for every one of them already in line. Measured inside the 3,107-test
/// run on 2026-08-29, where the numbers are arithmetic in the number of visits:
/// no hop 74.8 s, one hop 142.6 s, and `aSecondStartDoesNothing`, which called
/// `start()` twice, 617.0 s, over the limit and the run's only failure. The
/// same tests together take 2.5 s on their own. So a hop is not a cost, it is a
/// coin toss on where in the queue the test lands, which is what made this
/// suite red in one batch and green in the next. `start()` is nonisolated for
/// that
/// reason (`OllinApp.isRenderingHeadless` is the flag it reads, and it is
/// `nonisolated(unsafe)` to keep it so). Reach for `MainActor.run` here and the
/// timeouts come back.
///
/// Nothing may park a thread on a semaphore either. Test bodies run on the
/// concurrency pool, which is exactly one thread per core: parking one there
/// costs the whole process a worker, and this suite runs enough of these at
/// once to take every worker there is. Nothing anywhere in the process then
/// resumes, every other suite's `Task.sleep` included, and the deadlines below
/// expire on a machine doing nothing at all. Measured that way once: eight of
/// eight pool threads in `semaphore_wait_trap`, the process at 2% CPU, seven
/// tests timing out together on a stopwatch none of them got to read.
///
/// The time limit is a hang backstop, not a performance expectation. It is
/// sized to catch a feed that never dials rather than a machine that is busy,
/// and `dial(_:)` above is what has no deadline of its own.
@Suite(.timeLimit(.minutes(5)))
struct PushFeedTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a non-nil value or the timeout elapses.
    ///
    /// Every stream probe below asks `>=`, never `==`, and never for a value
    /// the feed only passes through. A full run resumes this task up to 74
    /// seconds after the connection it is watching already opened (measured),
    /// and the session's own 60-second request timeout redials an idle stream
    /// in the meantime, so by the first poll the counters have moved on: 4
    /// updates where the test wanted 2, three dials where it wanted two, a
    /// failure already reset by the redial that cleared it. Nothing is slow
    /// there. The test is late, and an equality question has no answer once
    /// it is.
    ///
    /// The loop probes *before* it reads the clock, for the same reason. A task
    /// this starved can wake past its own deadline having never looked once,
    /// and a deadline test placed first then throws while the value it wanted
    /// is sitting there. That is what the sibling suite failed on, thirteen
    /// tests at once, with the stub's answer already in hand.
    func waitFor<T>(timeout: Double = 20.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    func parse(_ chunks: [String]) -> ServerSentEventParser.Reading {
        var parser = ServerSentEventParser()
        var whole = ServerSentEventParser.Reading()
        for chunk in chunks {
            let reading = parser.consume(Data(chunk.utf8))
            whole.events.append(contentsOf: reading.events)
            whole.comments += reading.comments
            if let retry = reading.retry { whole.retry = retry }
        }
        return whole
    }

    // MARK: The wire shape

    @Test func aSimpleEventParses() {
        let read = parse(["data: hello\n\n"])
        #expect(read.events == [.init(name: nil, data: "hello", id: nil)])
    }

    @Test func dataLinesJoinWithNewlines() {
        let read = parse(["data: first\ndata: second\n\n"])
        #expect(read.events.first?.data == "first\nsecond")
    }

    @Test func anEventNameLabelsTheMessage() {
        let read = parse(["event: tick\ndata: 1\n\ndata: 2\n\n"])
        #expect(read.events.first?.name == "tick")
        // The name is per event, not sticky.
        #expect(read.events.last?.name == nil)
    }

    @Test func aCommentIsCountedAndDeliversNothing() {
        let read = parse([":ok\n\n"])
        #expect(read.events.isEmpty)
        #expect(read.comments == 1)
    }

    @Test func theIDIsStickyAcrossEvents() {
        let read = parse(["id: 7\ndata: a\n\ndata: b\n\n"])
        #expect(read.events.map(\.id) == ["7", "7"])
    }

    @Test func anIDCarryingNULIsIgnored() {
        let read = parse(["id: bad\u{0}id\ndata: a\n\n"])
        #expect(read.events.first?.id == nil)
    }

    @Test func retryIsMillisecondsOnTheWireAndSecondsHere() {
        #expect(parse(["retry: 1500\n"]).retry == 1.5)
        #expect(parse(["retry: soon\n"]).retry == nil)
    }

    @Test func aLineSplitAcrossChunksParses() {
        let read = parse(["da", "ta: hel", "lo\n\n"])
        #expect(read.events.first?.data == "hello")
    }

    @Test func aCarriageReturnPairSplitAcrossChunksIsOneEnding() {
        // The pair split across two chunks must not read as two endings, or
        // an empty line appears out of nowhere and dispatches half an event.
        let read = parse(["data: a\r", "\ndata: b\r\n\r\n"])
        #expect(read.events == [.init(name: nil, data: "a\nb", id: nil)])
    }

    @Test func aByteOrderMarkIsStripped() {
        let read = parse(["\u{FEFF}data: x\n\n"])
        #expect(read.events.first?.data == "x")
    }

    @Test func onlyTheFirstSpaceAfterTheColonIsEaten() {
        #expect(parse(["data:bare\n\n"]).events.first?.data == "bare")
        #expect(parse(["data:  two\n\n"]).events.first?.data == " two")
    }

    @Test func anUnfinishedEventIsNotDelivered() {
        // No blank line yet, so the event is still being said.
        let read = parse(["data: x\n"])
        #expect(read.events.isEmpty)
    }

    // MARK: The redial policy

    @Test func theRetryDelayDoublesUpToEightTimes() {
        #expect(PushFeed.retryDelay(after: 1, base: 3) == 3)
        #expect(PushFeed.retryDelay(after: 2, base: 3) == 6)
        #expect(PushFeed.retryDelay(after: 3, base: 3) == 12)
        #expect(PushFeed.retryDelay(after: 4, base: 3) == 24)
        #expect(PushFeed.retryDelay(after: 9, base: 3) == 24)
    }

    @Test func theServerNamedRetryTimeWins() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        #expect(feed.retryBase == 3)

        feed.start()
        carrier.transports[0].deliver(.retryHint(5))
        #expect(feed.retryBase == 5)
        carrier.transports[0].deliver(.retryHint(0.2))
        #expect(feed.retryBase == 1)   // politeness clamps it, like everything here
    }

    @Test func theRetryIntervalNeverGoesBelowOneSecond() {
        #expect(PushFeed("wss://x.test", retryEvery: 0.01).retryInterval == 1)
        #expect(PushFeed("wss://x.test", retryEvery: 30).retryInterval == 30)
    }

    // MARK: Messages, scripted

    @Test func aMessageBecomesTheLatestAndCounts() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let transport = carrier.transports[0]
        #expect(transport.wasOpened)
        transport.deliver(.opened)
        #expect(feed.isConnected)

        transport.deliver(.message(Data(#"{"n": 4}"#.utf8), isText: true, event: nil, id: nil))
        #expect(feed.json["n"].number == 4)
        #expect(feed.text == #"{"n": 4}"#)
        #expect(feed.updateCount == 1)
        #expect((feed.timeSinceUpdate ?? -1) >= 0)
    }

    @Test func everyMessageCountsEvenARepeat() async {
        // A poll that brings back the same bytes is not news, but a push is
        // sent because the server had something to say.
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let transport = carrier.transports[0]
        transport.deliver(.opened)
        transport.deliver(.message(Data("same".utf8), isText: true, event: nil, id: nil))
        transport.deliver(.message(Data("same".utf8), isText: true, event: nil, id: nil))
        #expect(feed.updateCount == 2)
    }

    @Test func messagesDrainsOldestFirst() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let transport = carrier.transports[0]
        transport.deliver(.opened)
        transport.deliver(.message(Data("one".utf8), isText: true, event: nil, id: nil))
        transport.deliver(.message(Data("two".utf8), isText: true, event: nil, id: nil))

        #expect(feed.messages().map(\.text) == ["one", "two"])
        #expect(feed.messages().isEmpty)
        #expect(feed.text == "two")     // the latest reads are not the drain
    }

    @Test func aFeedNobodyDrainsKeepsTheNewest() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let transport = carrier.transports[0]
        transport.deliver(.opened)
        for n in 0..<300 {
            transport.deliver(.message(Data("\(n)".utf8), isText: true, event: nil, id: nil))
        }
        let kept = feed.messages()
        #expect(kept.count == PushFeed.pendingLimit)
        #expect(kept.first?.text == "44")   // the oldest went
        #expect(kept.last?.text == "299")
        #expect(feed.updateCount == 300)        // dropped is not uncounted
    }

    @Test func bytesThatAreNotTextStillArrive() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let transport = carrier.transports[0]
        transport.deliver(.opened)
        transport.deliver(.message(Data([0xFF, 0xFE]), isText: false, event: nil, id: nil))
        #expect(feed.text == nil)
        #expect(feed.bytes == Data([0xFF, 0xFE]))
        #expect(feed.json.isNull)
    }

    // MARK: Dropping and redialing, scripted

    @Test func aDropRedialsAndSaysTheGreetingAgain() async throws {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", greeting: #"{"op": "subscribe"}"#,
                            retryEvery: 1, carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let first = carrier.transports[0]
        first.deliver(.opened)
        #expect(first.sent == [#"{"op": "subscribe"}"#])
        first.deliver(.message(Data("a".utf8), isText: true, event: nil, id: nil))

        first.deliver(.closed("the connection closed"))
        #expect(!feed.isConnected)
        #expect(feed.failureCount == 1)
        #expect(feed.problem == "the connection closed")
        #expect(feed.text == "a")           // a drop never clears what arrived

        // The redial makes a fresh transport, and the greeting is said to it
        // too, which is what keeps a subscription alive across the blink.
        let second = await carrier.dial(1)
        second.deliver(.opened)
        #expect(second.sent == [#"{"op": "subscribe"}"#])
        second.deliver(.message(Data("b".utf8), isText: true, event: nil, id: nil))
        #expect(feed.failureCount == 0)
        #expect(feed.problem == nil)
    }

    @Test func aDeadConnectionOnlyCountsOnce() async throws {
        // A socket can report its end twice, once as a close and once as the
        // task completing. The second report belongs to a connection the feed
        // has already replaced, so it must not count another failure or dial
        // a second chain.
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", retryEvery: 1, carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let first = carrier.transports[0]
        first.deliver(.opened)
        first.deliver(.closed("the connection closed"))
        first.deliver(.closed("the connection closed"))
        #expect(feed.failureCount == 1)

        _ = await carrier.dial(1)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(carrier.transports.count == 2)   // one redial, not two
    }

    @Test func stopHangsUpAndStaysDown() async throws {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", retryEvery: 1, carriedBy: carrier.factory)
        feed.start()

        let transport = carrier.transports[0]
        transport.deliver(.opened)
        feed.stop()
        #expect(transport.wasClosed)
        #expect(!feed.isRunning)
        #expect(!feed.isConnected)

        // A drop reported after the hangup belongs to nobody.
        transport.deliver(.closed("the connection closed"))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(carrier.transports.count == 1)
        #expect(feed.failureCount == 0)
    }

    @Test func reconnectRedialsNow() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        carrier.transports[0].deliver(.opened)
        feed.reconnect()
        #expect(carrier.transports[0].wasClosed)
        #expect(carrier.transports.count == 2)
    }

    @Test func theServerCanEndTheFeedForGood() async throws {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", retryEvery: 1, carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        carrier.transports[0].deliver(.opened)
        carrier.transports[0].deliver(.ended("the server ended the stream"))
        #expect(!feed.isRunning)
        #expect(feed.problem == "the server ended the stream")

        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(carrier.transports.count == 1)   // no redial: it was asked to stop
    }

    @Test func sendOnlySpeaksWhileConnected() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let transport = carrier.transports[0]
        feed.send("too early")
        #expect(transport.sent.isEmpty)
        transport.deliver(.opened)
        feed.send("hello")
        #expect(transport.sent == ["hello"])
    }

    @Test func aSecondStartDoesNothing() async {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("wss://feed.test/x", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()
        feed.start()
        #expect(carrier.transports.count == 1)
    }

    @Test func anAddressThatIsNotOneIsAProblemRatherThanACrash() async throws {
        let carrier = ScriptedCarrier()
        let feed = PushFeed("not an address", carriedBy: carrier.factory)
        defer { feed.stop() }
        feed.start()

        let problem = try await waitFor { feed.problem }
        #expect(problem.contains("not an address"))
        #expect(carrier.transports.isEmpty)
        #expect(feed.updateCount == 0)
    }

    // MARK: A stream of server-sent events, end to end

    func makeStream(_ connections: [[StreamStub.Step]], retryEvery: Double = 1,
                    headers: [String: String] = [:]) -> (path: String, feed: PushFeed) {
        let path = StreamStub.claimPath()
        StreamStub.script(connections, at: path)
        let feed = PushFeed("https://feed.test\(path)", headers: headers,
                            retryEvery: retryEvery, answeredBy: [StreamStub.self])
        return (path, feed)
    }

    @Test func aStreamOfEventsArrives() async throws {
        let (path, feed) = makeStream([[
            .respond(status: 200),
            .send("event: quake\ndata: {\"mag\": 5}\n\n"),
            .send("data: plain\n\n"),
        ]], headers: ["X-Api-Key": "abc123"])
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount >= 2 ? true : nil }

        let messages = feed.messages()
        #expect(messages[0].event == "quake")
        #expect(messages[0].json["mag"].number == 5)
        #expect(messages[1].event == nil)
        #expect(feed.isConnected)
        #expect(feed.problem == nil)

        let ask = StreamStub.asks(at: path)[0]
        #expect(ask.headers["accept"] == "text/event-stream")
        #expect(ask.headers["x-api-key"] == "abc123")
    }

    @Test func theLastIDSeenRidesTheRedial() async throws {
        let (path, feed) = makeStream([
            [.respond(status: 200),
             .send("id: 42\ndata: before the drop\n\n"),
             .fail(.networkConnectionLost)],
            [.respond(status: 200),
             .send("data: after it\n\n")],
        ])
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount >= 2 ? true : nil }

        // The redial told the server where it was, so the blink loses nothing
        // the server still holds.
        let asks = StreamStub.asks(at: path)
        #expect(asks[0].headers["last-event-id"] == nil)
        #expect(asks[1].headers["last-event-id"] == "42")
        #expect(feed.text == "after it")
        #expect(feed.failureCount == 0)
    }

    @Test func aKeepaliveCommentResetsTheFailures() async throws {
        let (path, feed) = makeStream([
            [.fail(.networkConnectionLost)],
            [.respond(status: 200), .send(":ok\n")],
        ])
        defer { feed.stop() }

        feed.start()
        // Watch the redial, and not the 1 the failure count passed through:
        // the keepalive clears that the moment it lands. A second dial only
        // follows a failure, so the pair below is what says the keepalive
        // reset it; the count on a drop is asserted synchronously in the
        // scripted tests above.
        _ = try await waitFor { StreamStub.asks(at: path).count >= 2 ? true : nil }
        _ = try await waitFor { feed.isConnected && feed.failureCount == 0 ? true : nil }
        #expect(feed.updateCount == 0)   // a keepalive is a sign of life, not a message
    }

    @Test func aNoContentAnswerEndsTheFeed() async throws {
        let (path, feed) = makeStream([[.respond(status: 204)]])
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.isRunning ? nil : true }
        #expect(feed.problem == "the server ended the stream")

        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(StreamStub.asks(at: path).count == 1)   // asked to stop, so it did
    }

    @Test func aServerErrorIsADropAndRedials() async throws {
        let (path, feed) = makeStream([
            [.respond(status: 503), .finish],
            [.respond(status: 200), .send("data: back\n\n")],
        ])
        defer { feed.stop() }

        feed.start()
        // Same rule: the redial is a fact that stays true, while the drop's own
        // `problem` is cleared the instant the redial connects. What a server
        // error says is checked next door, on a feed that stays down.
        _ = try await waitFor { StreamStub.asks(at: path).count >= 2 ? true : nil }
        _ = try await waitFor { feed.updateCount >= 1 ? true : nil }
        #expect(feed.text == "back")
        #expect(StreamStub.asks(at: path).count >= 2)
    }

    @Test func aServerErrorIsSaidInThePlainText() async throws {
        // Every dial gets the same answer, so the feed never comes up and what
        // it says about the last try stays readable however late the read is.
        let (_, feed) = makeStream([[.respond(status: 503), .finish]])
        defer { feed.stop() }

        feed.start()
        let problem = try await waitFor { feed.problem }
        #expect(problem.contains("503"))
        #expect(!feed.isConnected)
    }

    // MARK: A load the system really performs

    /// Every stream test above answers inside `URLSession`. This one goes all
    /// the way through it, at the one address that needs nothing running.
    @Test func readsARealEventStreamFile() async throws {
        let folder = ollinTempURL("ollin-push\(StreamStub.claimPath().dropFirst(5))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("stream.txt")
        try Data("data: {\"n\": 1}\n\ndata: {\"n\": 2}\n\n".utf8).write(to: file)

        let feed = PushFeed(file)
        defer { feed.stop() }

        feed.start()
        // At least two, not exactly two: the file ends, so the feed redials and
        // reads it again. The last message is `n: 2` on every pass.
        _ = try await waitFor { feed.updateCount >= 2 ? true : nil }
        #expect(feed.json["n"].number == 2)
        feed.stop()   // the file ends, and a redial would only read it again
    }
}

/// The export contract, and the one thing about this feed that is really about
/// the main thread.
///
/// A headless drive owns the main thread from `setup()` through the last frame,
/// so that is where a feed a sketch made asks whether it is being exported, and
/// `start()` only believes the flag there. Its own suite, `@MainActor`, for two
/// reasons: the suite next door must touch the main actor nowhere, and the flag
/// set here is process-wide, so only a test that holds the main thread may set
/// it (nothing else runs there while it does, and a feed on any other thread
/// now knows the render is not its own).
@Suite @MainActor
struct PushFeedExportTests {

    /// Says its piece the moment it is opened, which is what a real stream with
    /// something waiting does. `start()` opens the connection before it waits,
    /// so the wait is over before it begins and the test needs no second
    /// thread to satisfy it.
    final class EagerTransport: PushTransport, @unchecked Sendable {
        let deliver: @Sendable (PushTransportEvent) -> Void
        private(set) var wasClosed = false

        init(deliver: @escaping @Sendable (PushTransportEvent) -> Void) {
            self.deliver = deliver
        }

        func open() {
            deliver(.opened)
            deliver(.message(Data(#"{"n": 1}"#.utf8), isText: true, event: nil, id: nil))
        }
        func close() { wasClosed = true }
        func send(_ text: String) {}
    }

    @Test func anExportReadsOneMessageAndHangsUp() {
        let made = OSAllocatedUnfairLock(initialState: [EagerTransport]())
        let feed = PushFeed("wss://feed.test/x", retryEvery: 1) { _, deliver in
            let transport = EagerTransport(deliver: deliver)
            made.withLock { $0.append(transport) }
            return transport
        }
        defer { feed.stop() }

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        feed.start()

        // One message, the connection let go, and no clock: an export that
        // listened per frame would render something different every run.
        #expect(feed.updateCount == 1)
        #expect(feed.json["n"].number == 1)
        #expect(!feed.isConnected)
        #expect(feed.timeSinceUpdate == 0)
        #expect(made.withLock { $0.count } == 1)
        #expect(made.withLock { $0.first?.wasClosed } == true)
    }

    /// The same feed on any other thread reads the same flag and stays live,
    /// because the render it can see belongs to somebody else. This is what
    /// keeps a test process from handing its own renders to every feed under
    /// test, and it is the whole reason `start()` needs no main actor.
    @Test func aStartOffTheMainThreadIsNotPartOfTheExport() async {
        let made = OSAllocatedUnfairLock(initialState: [EagerTransport]())
        let feed = PushFeed("wss://feed.test/x", retryEvery: 1) { _, deliver in
            let transport = EagerTransport(deliver: deliver)
            made.withLock { $0.append(transport) }
            return transport
        }
        defer { feed.stop() }

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        await Task.detached { feed.start() }.value

        #expect(feed.updateCount == 1)
        #expect(feed.isConnected)                                  // still up
        #expect((feed.timeSinceUpdate ?? -1) >= 0)                 // a real clock
        #expect(made.withLock { $0.first?.wasClosed } == false)
    }
}
