import Foundation
import Network
import os
import Testing
@testable import Ollin
import OllinTestSupport

/// A web socket server on this machine's loopback, one per test, on a port
/// the system picks. It keeps what each connection's handshake carried and
/// what each connection said, and a test tells it what to say back.
///
/// Unchecked: everything it shares across threads is under its lock, and a
/// connection is only ever touched on the server's own queue.
final class SocketServer: @unchecked Sendable {
    private struct Log {
        var port: UInt16?
        var connections: [NWConnection] = []
        var headers: [[String: String]] = []
        var heard: [[String]] = []
        var ended: [Bool] = []
        var closeCodes: [NWProtocolWebSocket.CloseCode?] = []
    }

    private let log = OSAllocatedUnfairLock(uncheckedState: Log())
    private let queue = DispatchQueue(label: "co.eavl.ollin.tests.socket")
    private let listener: NWListener
    private let onOpen: @Sendable (SocketServer, Int) -> Void

    /// `onOpen` runs each time a connection finishes its handshake, with the
    /// connection's number, counted from zero.
    init(onOpen: @escaping @Sendable (SocketServer, Int) -> Void = { _, _ in }) throws {
        self.onOpen = onOpen
        let socket = NWProtocolWebSocket.Options()
        socket.autoReplyPing = true
        let log = self.log
        socket.setClientRequestHandler(queue) { _, headers in
            let named = Dictionary(headers.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            log.withLock { $0.headers.append(named) }
            return NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        parameters.defaultProtocolStack.applicationProtocols.insert(socket, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            self.log.withLock { $0.port = self.listener.port?.rawValue }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        for connection in log.withLock({ $0.connections }) { connection.cancel() }
    }

    /// The port the listener took, once it is ready.
    var port: UInt16? { log.withLock { $0.port } }
    var connectionCount: Int { log.withLock { $0.heard.count } }
    func heard(on index: Int) -> [String] { log.withLock { $0.heard.indices.contains(index) ? $0.heard[index] : [] } }
    func headers(of index: Int) -> [String: String]? {
        log.withLock { $0.headers.indices.contains(index) ? $0.headers[index] : nil }
    }
    func hasEnded(_ index: Int) -> Bool { log.withLock { $0.ended.indices.contains(index) && $0.ended[index] } }
    func closeCode(of index: Int) -> NWProtocolWebSocket.CloseCode? {
        log.withLock { $0.closeCodes.indices.contains(index) ? $0.closeCodes[index] : nil }
    }

    private func accept(_ connection: NWConnection) {
        let index = log.withLock { log -> Int in
            log.connections.append(connection)
            log.heard.append([])
            log.ended.append(false)
            log.closeCodes.append(nil)
            return log.connections.count - 1
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.onOpen(self, index)
            case .failed, .cancelled: self.log.withLock { $0.ended[index] = true }
            default: break
            }
        }
        receive(on: connection, index)
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, _ index: Int) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .text:
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                self.log.withLock { $0.heard[index].append(text) }
            case .close:
                self.log.withLock {
                    $0.closeCodes[index] = metadata?.closeCode
                    $0.ended[index] = true
                }
            default:
                break
            }
            if error == nil, metadata?.opcode != .close {
                self.receive(on: connection, index)
            } else {
                self.log.withLock { $0.ended[index] = true }
            }
        }
    }

    private func send(_ data: Data?, as opcode: NWProtocolWebSocket.Opcode, to index: Int,
                      closing code: NWProtocolWebSocket.CloseCode? = nil) {
        guard let connection = log.withLock({ $0.connections.indices.contains(index) ? $0.connections[index] : nil })
        else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        if let code { metadata.closeCode = code }
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in
                            if opcode == .close { connection.cancel() }
                        })
    }

    func say(_ text: String, to index: Int) { send(Data(text.utf8), as: .text, to: index) }
    func send(bytes: [UInt8], to index: Int) { send(Data(bytes), as: .binary, to: index) }
    /// Close the connection the polite way, with a close frame, its code,
    /// and a reason in text when one is given.
    func hangUp(on index: Int, code: NWProtocolWebSocket.CloseCode = .protocolCode(.normalClosure),
                reason: String? = nil) {
        send(reason.map { Data($0.utf8) }, as: .close, to: index, closing: code)
    }
}

/// The web socket transport against a real socket: a server on the loopback
/// through Network.framework, the feed dialing it with the session it dials
/// any server with. Everything the scripted carrier in `PushFeedTests` stands
/// in for is real here: the handshake and its headers, text and binary frames,
/// the greeting on every connection, a close frame from either side, a redial
/// after a drop, and a port nobody is listening on.
///
/// The server takes a port the system picks, so two runs at once cannot meet.
/// The waits are probes with a deadline sized for a full run, never a measure
/// of speed; a redial is the feed's own retry time, one second at the least.
@Suite(.timeLimit(.minutes(5)))
struct PushFeedWebSocketTests {

    func waitFor<T>(timeout: Double = 30.0, _ probe: () -> T?) async throws -> T {
        try await OllinTestSupport.waitFor(timeout: timeout, probe)
    }

    func feed(to server: SocketServer, path: String = "/live", headers: [String: String] = [:],
              greeting: String? = nil) async throws -> PushFeed {
        let port = try await waitFor { server.port }
        return PushFeed("ws://127.0.0.1:\(port)\(path)", headers: headers, greeting: greeting, retryEvery: 1)
    }

    @Test func aTextFrameArrivesAsAMessage() async throws {
        let server = try SocketServer { server, index in server.say(#"{"mag": 5, "place": "Oaxaca"}"#, to: index) }
        defer { server.stop() }
        let feed = try await feed(to: server)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount >= 1 ? true : nil }
        #expect(feed.json["mag"].number == 5)
        #expect(feed.json["place"].text == "Oaxaca")
        #expect(feed.text == #"{"mag": 5, "place": "Oaxaca"}"#)
        #expect(feed.isConnected)
        #expect(feed.problem == nil)
        #expect(feed.failureCount == 0)
    }

    @Test func aBinaryFrameArrivesAsBytesAndNotAsText() async throws {
        let bytes: [UInt8] = [0x00, 0xFF, 0x9F, 0x92, 0x96, 0x07]      // not text in any reading
        let server = try SocketServer { server, index in server.send(bytes: bytes, to: index) }
        defer { server.stop() }
        let feed = try await feed(to: server)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount >= 1 ? true : nil }
        #expect(feed.bytes == Data(bytes))
        #expect(feed.text == nil)
    }

    @Test func framesArriveInTheOrderTheyWereSent() async throws {
        let server = try SocketServer { server, index in
            for n in 1 ... 5 { server.say("{\"n\": \(n)}", to: index) }
        }
        defer { server.stop() }
        let feed = try await feed(to: server)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.updateCount >= 5 ? true : nil }
        #expect(feed.messages().map { $0.json["n"].number } == [1, 2, 3, 4, 5])
    }

    @Test func theHandshakeCarriesTheHeadersAndThePath() async throws {
        let server = try SocketServer()
        defer { server.stop() }
        let feed = try await feed(to: server, headers: ["X-Api-Key": "abc123"])
        defer { feed.stop() }

        feed.start()
        let headers = try await waitFor { server.headers(of: 0) }
        #expect(headers["x-api-key"] == "abc123")
        _ = try await waitFor { feed.isConnected ? true : nil }
    }

    @Test func sendReachesTheServerOnceConnected() async throws {
        let server = try SocketServer()
        defer { server.stop() }
        let feed = try await feed(to: server)
        defer { feed.stop() }

        feed.send("too early")          // before start: nothing to say it to
        feed.start()
        _ = try await waitFor { feed.isConnected ? true : nil }
        feed.send("hello")
        _ = try await waitFor { server.heard(on: 0).contains("hello") ? true : nil }
        #expect(server.heard(on: 0) == ["hello"])
    }

    @Test func theGreetingIsSaidAgainAfterARedial() async throws {
        // The first connection is hung up on as soon as it has subscribed.
        let server = try SocketServer()
        defer { server.stop() }
        let feed = try await feed(to: server, greeting: "subscribe quakes")
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { server.heard(on: 0) == ["subscribe quakes"] ? true : nil }
        server.hangUp(on: 0)
        // The feed's own retry time, then the second dial.
        _ = try await waitFor { server.heard(on: 1) == ["subscribe quakes"] ? true : nil }
        #expect(server.connectionCount >= 2)
        _ = try await waitFor { feed.isConnected ? true : nil }
    }

    @Test func aServerThatHangsUpIsADropTheFeedNames() async throws {
        let server = try SocketServer()
        defer { server.stop() }
        let feed = try await feed(to: server)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.isConnected ? true : nil }
        server.hangUp(on: 0)
        let problem = try await waitFor { feed.problem }
        #expect(feed.failureCount >= 1)
        // The close frame's own code, not the socket's error after it.
        #expect(problem == "the server closed the connection (code 1000)")
        // A message on the redial is the feed working again, and says so.
        _ = try await waitFor { server.connectionCount >= 2 ? true : nil }
        _ = try await waitFor { feed.isConnected ? true : nil }
        server.say("{\"back\": true}", to: 1)
        _ = try await waitFor { feed.updateCount >= 1 ? true : nil }
        #expect(feed.failureCount == 0)
        #expect(feed.problem == nil)
    }

    @Test func aCloseWithAReasonSaysTheReason() async throws {
        let server = try SocketServer()
        defer { server.stop() }
        let feed = try await feed(to: server)
        defer { feed.stop() }

        feed.start()
        _ = try await waitFor { feed.isConnected ? true : nil }
        server.hangUp(on: 0, code: .protocolCode(.policyViolation), reason: "no key on this request")
        let problem = try await waitFor { feed.problem }
        #expect(problem == "the server closed the connection (code 1008): no key on this request")
    }

    @Test func aCloseFrameIsASentenceAndNoFrameIsNone() {
        #expect(WebSocketTransport.closeSentence(.invalid, nil) == nil)
        #expect(WebSocketTransport.closeSentence(.goingAway, nil) == "the server closed the connection (code 1001)")
        #expect(WebSocketTransport.closeSentence(.normalClosure, Data("  \n".utf8))
                == "the server closed the connection (code 1000)")
        #expect(WebSocketTransport.closeSentence(.internalServerError, Data([0xFF, 0xFE]))
                == "the server closed the connection (code 1011)")
    }

    @Test func stopHangsUpAtTheServerToo() async throws {
        let server = try SocketServer()
        defer { server.stop() }
        let feed = try await feed(to: server)

        feed.start()
        _ = try await waitFor { feed.isConnected ? true : nil }
        feed.stop()
        _ = try await waitFor { server.hasEnded(0) ? true : nil }
        #expect(!feed.isRunning)
        #expect(!feed.isConnected)
        // Stopped is stopped: no second dial arrives.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(server.connectionCount == 1)
    }

    @Test func aPortNobodyListensOnIsAProblemAndNotACrash() async throws {
        // Take a port, then give it back, so nothing answers there.
        let server = try SocketServer()
        let port = try await waitFor { server.port }
        server.stop()
        try await Task.sleep(for: .milliseconds(200))

        let feed = PushFeed("ws://127.0.0.1:\(port)/live", retryEvery: 1)
        defer { feed.stop() }
        feed.start()
        let problem = try await waitFor { feed.problem }
        #expect(!problem.isEmpty)
        #expect(feed.failureCount >= 1)
        #expect(!feed.isConnected)
        #expect(feed.isRunning, "a feed that cannot connect keeps trying until it is stopped")
    }
}
