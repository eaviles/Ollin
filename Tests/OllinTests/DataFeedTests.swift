import Foundation
import os
import Testing
@testable import Ollin

/// A stand-in server for the feed's own `URLSession`. It records what was asked
/// and answers with whatever the test set, so the suite drives every branch of
/// the polling with no socket, no port, and no server to bring up.
///
/// Each test claims its own path and the script is kept per path, so tests that
/// run at the same time never see each other's requests.
final class StubServer: URLProtocol {

    /// One request as the stub saw it. Header names are lowercased, the way a
    /// server would treat them.
    struct Ask: Sendable {
        var path = ""
        var headers: [String: String] = [:]
    }

    /// What to answer with.
    struct Answer: Sendable {
        var status = 200
        var contentType: String? = "application/json"
        var body = ""
        /// When set, a request carrying a matching `If-None-Match` is answered
        /// 304 instead, which is how a server says "you already have it".
        var etag: String?
        /// When set, the request fails at the transport instead of answering.
        var failure: URLError.Code?
    }

    private struct Shared: Sendable {
        var answers: [String: Answer] = [:]
        var asks: [String: [Ask]] = [:]
        var claimed = 0
    }
    private static let shared = OSAllocatedUnfairLock(initialState: Shared())

    /// A path nothing else in the suite is using.
    static func claimPath() -> String {
        shared.withLock {
            $0.claimed += 1
            return "/feed\($0.claimed)"
        }
    }

    static func answer(_ answer: Answer, at path: String) {
        shared.withLock { $0.answers[path] = answer }
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

        let answer: Answer = StubServer.shared.withLock {
            $0.asks[path, default: []].append(ask)
            return $0.answers[path] ?? Answer()
        }

        if let failure = answer.failure {
            client.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }

        var status = answer.status
        var body = answer.body
        if let etag = answer.etag, status == 200, headers["if-none-match"] == etag {
            status = 304
            body = ""
        }

        var fields: [String: String] = [:]
        if let type = answer.contentType, status != 304 { fields["Content-Type"] = type }
        if let etag = answer.etag { fields["ETag"] = etag }

        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: fields)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client.urlProtocol(self, didLoad: Data(body.utf8)) }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `DataFeed`: what the bytes are read as, and the polling behavior driven end
/// to end. No GPU and no network, so it runs anywhere.
///
/// Deliberately not `@MainActor`, and nothing here may touch the main actor,
/// `start()` included. The drawing suites are main-actor bound and run one at a
/// time, so a job this suite enqueues waits for every one of them already in
/// line, and the wait is far longer than anything this suite measures. The
/// sibling suite carries the numbers ([[PushFeedTests]]), and `start()` is
/// nonisolated so neither has to pay them.
@Suite
struct DataFeedTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a non-nil value or the timeout elapses.
    ///
    /// The probe comes *before* the clock is read, and that order is the whole
    /// helper. A test body on the concurrency pool can be starved past its own
    /// deadline without having looked once, and a deadline test placed first
    /// then throws while the answer it was waiting for is already sitting in
    /// the feed. Measured on 2026-08-29: thirteen tests here threw `Timeout`
    /// together inside a 3,107-test run, every one of them with the stub's
    /// answer in hand.
    func waitFor<T>(timeout: Double = 20.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    /// A stub answering on its own path, with a feed pointed at it. The
    /// default interval is far past any test's lifetime, so a test drives the
    /// feed with `refresh()` and nothing fires behind the assertions: an
    /// interval a starved full-suite run can outlive lets the schedule
    /// legitimately ask again mid-test, and an exact-count assertion reads
    /// that as a bug. A test of the schedule itself passes `every: 1`.
    func makePair(_ body: String, contentType: String? = "application/json",
                  every interval: Double = 100_000, as content: DataFeed.Content = .auto,
                  headers: [String: String] = [:])
        -> (path: String, feed: DataFeed) {

        let path = StubServer.claimPath()
        StubServer.answer(StubServer.Answer(contentType: contentType, body: body), at: path)
        let feed = DataFeed("https://feed.test\(path)", every: interval, as: content,
                            headers: headers, answeredBy: [StubServer.self])
        return (path, feed)
    }

    /// Waits until the stub has seen `asks` requests and the feed has taken in
    /// the last of them.
    func settle(_ feed: DataFeed, after asks: Int, at path: String) async throws {
        _ = try await waitFor { StubServer.asks(at: path).count >= asks ? true : nil }
        _ = try await waitFor { feed.isWaiting ? nil : true }
    }

    // MARK: Reading the bytes

    @Test func readsJSONWhenTheServerSaysSo() {
        let read = DataFeed.read(Data(#"{"height": 3}"#.utf8),
                                 contentType: "application/json; charset=utf-8", as: .auto)
        #expect(read.json["height"].number == 3)
        #expect(read.table == nil)
        #expect(read.text == #"{"height": 3}"#)
    }

    @Test func readsJSONFromTheBytesWhenNobodySays() {
        let read = DataFeed.read(Data("\n  [1, 2, 3]".utf8), contentType: nil, as: .auto)
        #expect(read.json.array.count == 3)
        #expect(read.table == nil)
    }

    @Test func readsATableWhenTheServerSaysCSV() {
        let read = DataFeed.read(Data("city,size\nOaxaca,4\n".utf8),
                                 contentType: "text/csv", as: .auto)
        #expect(read.table?.count == 1)
        #expect(read.table?[0]["city"] == "Oaxaca")
        #expect(read.json.isNull)
    }

    @Test func anExplicitShapeWinsOverTheGuess() {
        // The server calls it JSON and the bytes open like JSON, and the sketch
        // still gets the text it asked for and no parse.
        let read = DataFeed.read(Data(#"{"a": 1}"#.utf8),
                                 contentType: "application/json", as: .text)
        #expect(read.json.isNull)
        #expect(read.table == nil)
        #expect(read.text == #"{"a": 1}"#)
    }

    @Test func bytesThatAreNotTextStillArrive() {
        let read = DataFeed.read(Data([0xFF, 0xFE, 0x00]), contentType: nil, as: .auto)
        #expect(read.text == nil)
        #expect(read.json.isNull)
    }

    @Test func intervalNeverGoesBelowOneSecond() {
        #expect(DataFeed("https://example.org", every: 0.01).interval == 1)
        #expect(DataFeed("https://example.org", every: -5).interval == 1)
        #expect(DataFeed("https://example.org", every: 42).interval == 42)
    }

    @Test func anAddressNeedsAScheme() {
        // `URL(string:)` takes a bare phrase as a relative reference, which
        // would fail much later and much less clearly.
        #expect(DataFeed.parse("not an address") == nil)
        #expect(DataFeed.parse("example.org/tide.json") == nil)
        #expect(DataFeed.parse("https://example.org/tide.json") != nil)
    }

    // MARK: Asking

    @Test func readsTheAnswerAndCountsOneUpdate() async throws {
        let (path, feed) = makePair(#"{"height": 2.5}"#)
        defer { feed.stop() }

        #expect(feed.timeSinceUpdate == nil)      // nothing has arrived yet
        feed.start()
        _ = try await waitFor { feed.updateCount == 1 ? true : nil }
        #expect(feed.json["height"].number == 2.5)
        #expect(feed.text == #"{"height": 2.5}"#)
        #expect(feed.problem == nil)
        #expect(feed.failureCount == 0)
        #expect((feed.timeSinceUpdate ?? -1) >= 0)
        #expect(StubServer.asks(at: path).count == 1)
    }

    @Test func anUnchangedAnswerIsNotAnUpdate() async throws {
        let (path, feed) = makePair(#"{"height": 2.5}"#)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount == 1 ? true : nil }
        feed.refresh()
        try await settle(feed, after: 2, at: path)

        #expect(feed.updateCount == 1)
        #expect(feed.json["height"].number == 2.5)
    }

    @Test func aNotModifiedAnswerKeepsWhatItHas() async throws {
        let (path, feed) = makePair(#"{"height": 2.5}"#)
        defer { feed.stop() }
        StubServer.answer(StubServer.Answer(body: #"{"height": 2.5}"#, etag: "\"v1\""), at: path)

        feed.start()
        _ = try await waitFor { feed.updateCount == 1 ? true : nil }
        feed.refresh()
        try await settle(feed, after: 2, at: path)

        // The second request carried the tag, the server sent no body, and the
        // feed still holds the first answer.
        #expect(StubServer.asks(at: path)[1].headers["if-none-match"] == "\"v1\"")
        #expect(feed.updateCount == 1)
        #expect(feed.json["height"].number == 2.5)
        #expect(feed.problem == nil)
        #expect(feed.failureCount == 0)
    }

    @Test func aChangedAnswerReplacesIt() async throws {
        let (path, feed) = makePair(#"{"height": 2.5}"#)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount == 1 ? true : nil }
        StubServer.answer(StubServer.Answer(body: #"{"height": 4}"#), at: path)
        feed.refresh()
        _ = try await waitFor { feed.updateCount == 2 ? true : nil }

        #expect(feed.json["height"].number == 4)
    }

    @Test func aServerErrorLeavesTheLastGoodAnswerReadable() async throws {
        let (path, feed) = makePair(#"{"height": 2.5}"#)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount == 1 ? true : nil }
        StubServer.answer(StubServer.Answer(status: 500, body: "no"), at: path)
        feed.refresh()
        let problem = try await waitFor { feed.problem }

        #expect(problem.contains("500"))
        #expect(feed.failureCount == 1)
        // Nothing to draw is worse than something slightly old.
        #expect(feed.json["height"].number == 2.5)
        #expect(feed.updateCount == 1)
    }

    @Test func aTransportFailureIsReportedTheSameWay() async throws {
        let (path, feed) = makePair("{}")
        defer { feed.stop() }
        StubServer.answer(StubServer.Answer(failure: .cannotConnectToHost), at: path)

        feed.start()
        let problem = try await waitFor { feed.problem }
        #expect(!problem.isEmpty)
        #expect(feed.failureCount == 1)
        #expect(feed.json.isNull)
    }

    @Test func aFailureIsForgottenOnTheNextAnswer() async throws {
        let (path, feed) = makePair("{}")
        defer { feed.stop() }
        StubServer.answer(StubServer.Answer(failure: .timedOut), at: path)

        feed.start()
        _ = try await waitFor { feed.problem }
        StubServer.answer(StubServer.Answer(body: #"{"height": 1}"#), at: path)
        feed.refresh()
        _ = try await waitFor { feed.updateCount == 1 ? true : nil }

        #expect(feed.problem == nil)
        #expect(feed.failureCount == 0)
    }

    @Test func anAddressThatIsNotOneIsAProblemRatherThanACrash() async throws {
        let feed = DataFeed("not an address", every: 300, answeredBy: [StubServer.self])
        defer { feed.stop() }

        feed.start()
        let problem = try await waitFor { feed.problem }
        #expect(problem.contains("not an address"))
        #expect(feed.json.isNull)
        #expect(feed.updateCount == 0)
    }

    @Test func headersReachTheServer() async throws {
        let (path, feed) = makePair("{}", headers: ["X-Api-Key": "abc123"])
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { StubServer.asks(at: path).first }
        #expect(StubServer.asks(at: path)[0].headers["x-api-key"] == "abc123")
        #expect(StubServer.asks(at: path)[0].path == path)
    }

    @Test func stopEndsTheSchedule() async throws {
        let (path, feed) = makePair("{}", every: 1)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { StubServer.asks(at: path).count >= 1 ? true : nil }
        feed.stop()
        let asked = StubServer.asks(at: path).count
        #expect(!feed.isRunning)

        // Well past two turns of a one-second feed.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        #expect(StubServer.asks(at: path).count == asked)
    }

    /// A refresh replaces the schedule rather than adding to it. Two chains
    /// running at once would ask twice as often as the feed promised, which is
    /// the one failure here that lands on somebody else's server.
    @Test func refreshReplacesTheScheduleRatherThanForkingIt() async throws {
        let (path, feed) = makePair("{}", every: 1)
        defer { feed.stop() }

        // One chain asks about once a second, plus the start and the refresh.
        // Two chains ask about twice that, so the bound is measured against
        // the time that actually passed rather than the time asked for. The
        // window opens before the first ask and closes after the count is
        // read: a loaded machine stretches every wait here, and a window that
        // misses any of the asking time (one over just the sleep, say)
        // undercounts the allowance and fails a starved run.
        let began = Date()
        feed.start()
        _ = try await waitFor { StubServer.asks(at: path).count >= 1 ? true : nil }
        feed.refresh()
        try await Task.sleep(nanoseconds: 3_300_000_000)
        let count = StubServer.asks(at: path).count
        let elapsed = Date().timeIntervalSince(began)
        #expect(count <= Int(elapsed) + 3)
    }

    @Test func aFeedThatIsAlreadyRunningIgnoresASecondStart() async throws {
        let (path, feed) = makePair("{}")
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { StubServer.asks(at: path).count == 1 ? true : nil }
        feed.start()
        feed.start()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(StubServer.asks(at: path).count == 1)
    }

    @Test func refreshDoesNothingBeforeStart() async throws {
        let (path, feed) = makePair("{}")
        defer { feed.stop() }

        feed.refresh()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(StubServer.asks(at: path).isEmpty)
    }

    // MARK: A load the system really performs

    /// Every test above answers inside `URLSession`. This one goes all the way
    /// through it, at the one address that needs nothing running.
    @Test func readsARealURLAndNoticesItChange() async throws {
        let folder = ollinTempURL("ollin-feed\(StubServer.claimPath().dropFirst(5))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("tide.json")
        try Data(#"{"height": 1}"#.utf8).write(to: file)

        let feed = DataFeed(file, every: 300)
        defer { feed.stop() }

        // Both waits ask `>=`, the counter rule: this one goes through the real
        // loading system rather than a stub, so the answer can land while the
        // test is still waiting for a thread, and an equality question has no
        // answer by the time a late task gets to ask it.
        feed.start()
        _ = try await waitFor { feed.updateCount >= 1 ? true : nil }
        #expect(feed.json["height"].number == 1)

        feed.refresh()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(feed.updateCount == 1)          // the same bytes are not news

        try Data(#"{"height": 9}"#.utf8).write(to: file)
        feed.refresh()
        _ = try await waitFor { feed.updateCount >= 2 ? true : nil }
        #expect(feed.json["height"].number == 9)
    }
}

/// The export contract, and the one thing about this feed that is really about
/// the main thread.
///
/// A headless drive owns the main thread from `setup()` through the last frame,
/// so that is where a feed a sketch made asks whether it is being exported, and
/// `start()` only believes the flag there. Its own suite, `@MainActor`, for two
/// reasons: the suite above must touch the main actor nowhere, and the flag set
/// here is process-wide, so only a test that holds the main thread may set it
/// (nothing else runs there while it does, and a feed on any other thread now
/// knows the render is not its own).
@Suite @MainActor
struct DataFeedExportTests {

    private func makeFeed(_ body: String, every interval: Double = 1)
        -> (path: String, feed: DataFeed) {
        let path = StubServer.claimPath()
        StubServer.answer(StubServer.Answer(body: body), at: path)
        let feed = DataFeed("https://feed.test\(path)", every: interval,
                            answeredBy: [StubServer.self])
        return (path, feed)
    }

    @Test func anExportReadsOnceBeforeStartReturns() {
        let (path, feed) = makeFeed(#"{"height": 4}"#)
        defer { feed.stop() }

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        feed.start()

        // The answer is in by the time `start()` returns, with no waiting at
        // the call site: that is what lets `setup()` hand the same numbers to
        // every frame of the export.
        #expect(feed.updateCount == 1)
        #expect(feed.json["height"].number == 4)
        #expect(feed.timeSinceUpdate == 0)
        #expect(StubServer.asks(at: path).count == 1)
    }

    /// The same feed on any other thread reads the same flag and polls as
    /// usual, because the render it can see belongs to somebody else. This is
    /// what keeps a test process from handing its own renders to every feed
    /// under test, and it is the whole reason `start()` needs no main actor.
    @Test func aStartOffTheMainThreadIsNotPartOfTheExport() async throws {
        let (path, feed) = makeFeed(#"{"height": 4}"#, every: 100_000)
        defer { feed.stop() }

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        await Task.detached { feed.start() }.value

        // Nothing is read synchronously here: the request is scheduled, so the
        // answer arrives later and the clock is a real one.
        let deadline = Date().addingTimeInterval(20)
        while true {
            if feed.updateCount >= 1 { break }
            if Date() >= deadline { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(feed.updateCount == 1)
        #expect((feed.timeSinceUpdate ?? -1) > 0)
        #expect(StubServer.asks(at: path).count == 1)
    }
}
