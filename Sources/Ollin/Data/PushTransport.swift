import Foundation
import os

/// What a connection tells its `PushFeed`. One funnel, so the redial logic
/// never cares which kind of socket is underneath.
enum PushTransportEvent: Sendable {
    /// The connection is open.
    case opened
    /// One message, with whether the wire called it text, the label a stream
    /// that names its events sent, and the id a resumable stream sent.
    case message(Data, isText: Bool, event: String?, id: String?)
    /// Bytes that are not a message: a keepalive comment, a pong. Proof the
    /// other end is there.
    case heard
    /// The server named its own retry time, in seconds.
    case retryHint(Double)
    /// The connection is down, with why in a sentence. The feed redials.
    case closed(String)
    /// The server asked for no reconnection, with why in a sentence.
    case ended(String)
}

/// One connection. A transport is made per dial, delivers `PushTransportEvent`s
/// until it reports `closed` or `ended` once, and is done.
protocol PushTransport: AnyObject, Sendable {
    func open()
    func close()
    func send(_ text: String)
}

typealias PushTransportFactory =
    @Sendable (URLRequest, @escaping @Sendable (PushTransportEvent) -> Void) -> any PushTransport

// MARK: - A web socket

/// A `ws`/`wss` connection. The session is this transport's own and is
/// invalidated when the connection is done, because a session holds its
/// delegate until then.
final class WebSocketTransport: NSObject, PushTransport, URLSessionWebSocketDelegate,
                                @unchecked Sendable {

    /// Seconds between pings. A socket can die without a word, and the ping
    /// that fails is how the feed finds out and redials.
    private static let pingInterval = 20.0

    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let deliver: @Sendable (PushTransportEvent) -> Void
    private let timing = DispatchQueue(label: "co.eavl.ollin.data.push.socket")

    private struct Guarded {
        var session: URLSession?
        var task: URLSessionWebSocketTask?
        var finished = false
    }
    private let guarded = OSAllocatedUnfairLock(initialState: Guarded())

    init(request: URLRequest, configuration: URLSessionConfiguration,
         deliver: @escaping @Sendable (PushTransportEvent) -> Void) {
        self.request = request
        self.configuration = configuration
        self.deliver = deliver
    }

    func open() {
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self,
                                 delegateQueue: callbacks)
        let task = session.webSocketTask(with: request)
        guarded.withLock {
            $0.session = session
            $0.task = task
        }
        task.resume()
        receiveNext(on: task)
    }

    func close() {
        let session: URLSession? = guarded.withLock {
            guard !$0.finished else { return nil }
            $0.finished = true
            $0.task?.cancel(with: .goingAway, reason: nil)
            $0.task = nil
            let session = $0.session
            $0.session = nil
            return session
        }
        session?.invalidateAndCancel()
    }

    func send(_ text: String) {
        let task = guarded.withLock { $0.finished ? nil : $0.task }
        // A send that fails surfaces through the receive loop, which is
        // already how every other way the socket dies is reported.
        task?.send(.string(text)) { _ in }
    }

    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame):
                switch frame {
                case .string(let text):
                    self.deliver(.message(Data(text.utf8), isText: true, event: nil, id: nil))
                case .data(let bytes):
                    self.deliver(.message(bytes, isText: false, event: nil, id: nil))
                @unknown default:
                    break
                }
                self.receiveNext(on: task)
            case .failure(let error):
                self.finish(saying: error.localizedDescription)
            }
        }
    }

    private func schedulePing() {
        timing.asyncAfter(deadline: .now() + WebSocketTransport.pingInterval) { [weak self] in
            guard let self else { return }
            let task = self.guarded.withLock { $0.finished ? nil : $0.task }
            guard let task else { return }
            task.sendPing { [weak self] error in
                guard let self else { return }
                if let error {
                    self.finish(saying: error.localizedDescription)
                } else {
                    self.deliver(.heard)
                    self.schedulePing()
                }
            }
        }
    }

    /// Reports the connection down, once. Everything after the first report
    /// belongs to a connection the feed has already replaced.
    private func finish(saying reason: String) {
        let session: URLSession? = guarded.withLock {
            guard !$0.finished else { return nil }
            $0.finished = true
            $0.task = nil
            let session = $0.session
            $0.session = nil
            return session
        }
        guard let session else { return }
        session.invalidateAndCancel()
        deliver(.closed(reason))
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        deliver(.opened)
        schedulePing()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        finish(saying: "the connection closed (code \(closeCode.rawValue))")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        finish(saying: error?.localizedDescription ?? "the connection closed")
    }
}

// MARK: - A stream of server-sent events

/// An `http`/`https` connection read as server-sent events: one long response
/// whose body arrives a chunk at a time, parsed into messages as it does.
final class EventStreamTransport: NSObject, PushTransport, URLSessionDataDelegate,
                                  @unchecked Sendable {

    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let deliver: @Sendable (PushTransportEvent) -> Void

    private struct Guarded {
        var session: URLSession?
        var task: URLSessionDataTask?
        var finished = false
        var parser = ServerSentEventParser()
    }
    private let guarded = OSAllocatedUnfairLock(initialState: Guarded())

    init(request: URLRequest, configuration: URLSessionConfiguration,
         deliver: @escaping @Sendable (PushTransportEvent) -> Void) {
        self.request = request
        self.configuration = configuration
        self.deliver = deliver
    }

    func open() {
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self,
                                 delegateQueue: callbacks)
        let task = session.dataTask(with: request)
        guarded.withLock {
            $0.session = session
            $0.task = task
        }
        task.resume()
    }

    func close() {
        let session: URLSession? = guarded.withLock {
            guard !$0.finished else { return nil }
            $0.finished = true
            $0.task = nil
            let session = $0.session
            $0.session = nil
            return session
        }
        session?.invalidateAndCancel()
    }

    /// There is nothing to say it to: server-sent events only come this way.
    func send(_ text: String) {}

    private func finish(_ event: PushTransportEvent) {
        let session: URLSession? = guarded.withLock {
            guard !$0.finished else { return nil }
            $0.finished = true
            $0.task = nil
            let session = $0.session
            $0.session = nil
            return session
        }
        guard let session else { return }
        session.invalidateAndCancel()
        deliver(event)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        switch status {
        case 204:
            completionHandler(.cancel)
            finish(.ended("the server ended the stream"))
        case 200..<300:
            completionHandler(.allow)
            deliver(.opened)
        default:
            completionHandler(.cancel)
            finish(.closed("the server answered \(status)"))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        let read: ServerSentEventParser.Reading? = guarded.withLock {
            guard !$0.finished else { return nil }
            return $0.parser.consume(data)
        }
        guard let read else { return }
        if let retry = read.retry { deliver(.retryHint(retry)) }
        // A comment line is the common keepalive, so it counts as a sign of
        // life even though it carries no message.
        if read.comments > 0 && read.events.isEmpty { deliver(.heard) }
        for event in read.events {
            deliver(.message(Data(event.data.utf8), isText: true,
                             event: event.name, id: event.id))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        finish(.closed(error?.localizedDescription ?? "the stream ended"))
    }
}

// MARK: - The parser

/// Reads the server-sent-events wire shape: lines of `field: value`, blank
/// line between events, `:` opening a comment. Written from the published
/// technique; bytes go in as they arrive, whole events come out.
struct ServerSentEventParser: Sendable {

    struct Event: Sendable, Equatable {
        var name: String?
        var data: String
        var id: String?
    }

    /// What one chunk of bytes contained.
    struct Reading: Sendable {
        var events: [Event] = []
        var comments = 0
        var retry: Double?
    }

    private var line = Data()
    /// A line can end in a bare carriage return, a bare newline, or the pair.
    /// The pair can be split across two chunks, so a trailing carriage return
    /// is remembered and the newline that follows it swallowed.
    private var sawCarriageReturn = false
    private var strippedByteOrderMark = false

    private var dataLines: [String] = []
    private var eventName: String?
    /// The id is sticky: once a stream names one, every later event carries
    /// it until the stream names another.
    private var currentID: String?

    mutating func consume(_ chunk: Data) -> Reading {
        var reading = Reading()
        for byte in chunk {
            if sawCarriageReturn {
                sawCarriageReturn = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0D:
                finishLine(into: &reading)
                sawCarriageReturn = true
            case 0x0A:
                finishLine(into: &reading)
            default:
                line.append(byte)
            }
        }
        return reading
    }

    private mutating func finishLine(into reading: inout Reading) {
        var bytes = line
        line = Data()
        if !strippedByteOrderMark {
            strippedByteOrderMark = true
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        }

        if bytes.isEmpty {
            dispatch(into: &reading)
            return
        }
        if bytes.first == UInt8(ascii: ":") {
            reading.comments += 1
            return
        }

        let text = String(decoding: bytes, as: UTF8.self)
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = text[...]
            value = ""
        }

        switch field {
        case "data":
            dataLines.append(String(value))
        case "event":
            eventName = value.isEmpty ? nil : String(value)
        case "id":
            // An id carrying a NUL is ignored, per the wire shape's own rule.
            if !value.contains("\u{0}") { currentID = String(value) }
        case "retry":
            if !value.isEmpty, value.allSatisfy(\.isNumber), let ms = Double(value) {
                reading.retry = ms / 1000
            }
        default:
            break   // an unknown field is ignored, so the shape can grow
        }
    }

    private mutating func dispatch(into reading: inout Reading) {
        defer {
            dataLines = []
            eventName = nil
        }
        guard !dataLines.isEmpty else { return }
        reading.events.append(Event(name: eventName,
                                    data: dataLines.joined(separator: "\n"),
                                    id: currentID))
    }
}
